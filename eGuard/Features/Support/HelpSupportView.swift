import SwiftUI

/// 18 Help & Support, from `GET /help?q=&category=`.
struct HelpSupportView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var category: String?
    @State private var state: LoadState<HelpIndex> = .loading

    var body: some View {
        EGuardScreen {
            HStack(spacing: EGuardSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(EGuardColors.neutral)
                TextField("Search for help…", text: $query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { Task { await loadHelp() } }
                if !query.isEmpty {
                    Button { query = ""; Task { await loadHelp() } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(EGuardColors.neutral) }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(EGuardSpacing.sm)
            .background(EGuardColors.surface, in: EGuardShapes.button)
            .overlay(EGuardShapes.button.strokeBorder(EGuardColors.divider))

            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadHelp() } }
            case .loaded(let index):
                if query.isEmpty {
                    EGuardCard {
                        ForEach(index.categories) { item in
                            EGuardNavRow(title: item.name, subtitle: item.description, symbolName: LucideIcon.symbol(for: item.icon, fallback: "questionmark.circle.fill"), tint: tint(item.id)) {
                                category = category == item.id ? nil : item.id
                                Task { await loadHelp() }
                            } trailing: {
                                if category == item.id { StatusPill(text: "Showing", tint: EGuardColors.primary) }
                            }
                            if item.id != index.categories.last?.id { Divider() }
                        }
                        if let contact = index.contact {
                            Divider()
                            EGuardNavRow(title: "Contact Support", subtitle: contact.replyTime ?? contact.email, symbolName: "bubble.left.and.bubble.right.fill", tint: EGuardColors.tileTeal) {
                                router.push(.supportTicket)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                    SectionHeader(title: category.map { id in index.categories.first { $0.id == id }?.name ?? "Articles" } ?? (query.isEmpty ? "Popular articles" : "Results"))
                    EGuardCard {
                        if index.articles.isEmpty {
                            Text("No articles match. Try another word, or contact support.")
                                .font(EGuardTypography.callout)
                                .foregroundStyle(EGuardColors.textSecondary)
                        }
                        ForEach(index.articles) { article in
                            EGuardNavRow(title: article.title, subtitle: article.summary, symbolName: "doc.text.fill", tint: tint(article.category)) {
                                router.push(.helpArticle(slug: article.slug))
                            }
                            if article.id != index.articles.last?.id { Divider() }
                        }
                    }
                }

                supportBanner
            }
        } actions: {
            Button("Contact Support") { router.push(.supportTicket) }
                .buttonStyle(.eGuardPrimary)
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHelp() }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { await loadHelp() }
        }
    }

    private func loadHelp() async {
        if state.value == nil { state = .loading }
        state = await load { try await model.api.help(query: query, category: category) }
    }

    private func tint(_ category: String) -> Color {
        switch category {
        case "SETUP": EGuardColors.primary
        case "TROUBLESHOOTING": EGuardColors.tileOrange
        case "PRIVACY": EGuardColors.tilePurple
        default: EGuardColors.tileTeal
        }
    }

    private var supportBanner: some View {
        ZStack(alignment: .bottomLeading) {
            FamilyIllustration(height: 160)
            Text("We're here to help your family stay safe.")
                .font(EGuardTypography.headline)
                .foregroundStyle(EGuardColors.textPrimary)
                .padding(EGuardSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.75))
        }
        .clipShape(EGuardShapes.card)
    }
}

/// `GET /help/{slug}`
struct HelpArticleView: View {
    let slug: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<HelpArticle> = .loading

    var body: some View {
        EGuardScreen {
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { state = await load { try await model.api.helpArticle(slug: slug) } } }
            case .loaded(let article):
                ScreenHeader(title: article.title, subtitle: article.summary)
                EGuardCard {
                    ForEach(Array(article.body.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(EGuardTypography.body)
                            .foregroundStyle(EGuardColors.textPrimary)
                    }
                }
            }
        } actions: {
            Button("Still need help? Contact Support") { router.push(.supportTicket) }
                .buttonStyle(.eGuardSecondary)
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
        .task { state = await load { try await model.api.helpArticle(slug: slug) } }
    }
}

/// `POST /support/tickets` and the parent's previous tickets.
struct SupportTicketView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var category = "OTHER"
    @State private var subject = ""
    @State private var message = ""
    @State private var confirmation: String?
    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var tickets: [SupportTicket] = []

    private let categories = [("SETUP", "Setup"), ("DEVICE", "Device"), ("BILLING", "Billing"), ("ACCOUNT", "Account"), ("OTHER", "Other")]

    private var canSend: Bool {
        (3...120).contains(subject.trimmingCharacters(in: .whitespaces).count) && (10...5000).contains(message.trimmingCharacters(in: .whitespaces).count) && !isSending
    }

    var body: some View {
        EGuardScreen {
            ScreenHeader(title: "Contact support", subtitle: "Tell us what's happening. We reply within one business day.")

            if let confirmation {
                EGuardCard {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.success)
                }
                .accessibilityIdentifier("ticket.confirmation")
            }

            EGuardCard {
                Picker("Topic", selection: $category) {
                    ForEach(categories, id: \.0) { id, title in Text(title).tag(id) }
                }
                .pickerStyle(.segmented)
                EGuardTextField(label: "Subject", placeholder: "Bedtime isn't verifying", text: $subject, symbolName: "text.alignleft", autocapitalization: .sentences)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Message").font(EGuardTypography.caption).foregroundStyle(EGuardColors.textSecondary)
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                        .font(EGuardTypography.body)
                }
                .padding(EGuardSpacing.sm)
                .background(EGuardColors.surface, in: EGuardShapes.button)
                .overlay(EGuardShapes.button.strokeBorder(EGuardColors.divider))
            }
            InlineError(message: errorMessage)

            if !tickets.isEmpty {
                VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                    SectionHeader(title: "Your requests")
                    EGuardCard {
                        ForEach(tickets) { ticket in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(ticket.subject ?? "Support request").font(EGuardTypography.label)
                                    Spacer()
                                    StatusPill(text: ticket.status.capitalized, tint: ticket.status == "OPEN" ? EGuardColors.primary : EGuardColors.success)
                                }
                                Text(ticket.createdAt.verifiedDescription()).font(EGuardTypography.caption).foregroundStyle(EGuardColors.textSecondary)
                            }
                            .padding(.vertical, EGuardSpacing.xxs)
                            if ticket.id != tickets.last?.id { Divider() }
                        }
                    }
                }
            }
        } actions: {
            Button(isSending ? "Sending…" : "Send") { Task { await send() } }
                .buttonStyle(.eGuardPrimary)
                .disabled(!canSend)
                .accessibilityIdentifier("ticket.send")
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .task { tickets = (try? await model.api.tickets()) ?? [] }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let ticket = try await model.api.createTicket(category: category, subject: subject.trimmingCharacters(in: .whitespaces), message: message.trimmingCharacters(in: .whitespaces))
            confirmation = ticket.message
            subject = ""
            message = ""
            errorMessage = nil
            tickets = (try? await model.api.tickets()) ?? tickets
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        HelpSupportView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
