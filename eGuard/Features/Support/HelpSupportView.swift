import SwiftUI

/// 18 Help & Support: searchable topics, FAQs, and contact options.
struct HelpSupportView: View {
    private struct Topic: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let body: String
    }

    private struct FAQ: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var expandedTopic: UUID?

    private let topics = [
        Topic(title: "Setup Guides", subtitle: "Step-by-step instructions", symbol: "list.clipboard.fill", tint: EGuardColors.primary,
              body: "Start on the Home tab and tap Manage Protection. Each protection is a numbered step: automatic ones are applied by eGuard, guided ones open Settings with instructions and are confirmed by you."),
        Topic(title: "Troubleshooting", subtitle: "Common solutions", symbol: "wrench.and.screwdriver.fill", tint: EGuardColors.tileOrange,
              body: "If a protection shows Action required, open it and tap Configure again. If authorization fails, make sure the device is signed in with a child account in your Family Sharing group and that no other parental-controls app is authorized."),
        Topic(title: "Contact Support", subtitle: "Chat or email us", symbol: "bubble.left.and.bubble.right.fill", tint: EGuardColors.tileTeal,
              body: "Email support@eguard.app with the Configuration Health summary from the Home tab. We reply within one business day."),
        Topic(title: "Privacy & Security", subtitle: "How we protect your data", symbol: "lock.shield.fill", tint: EGuardColors.tilePurple,
              body: "eGuard keeps everything on this device. App choices are Apple's opaque tokens, the child's profile lives in the Keychain, and nothing is uploaded."),
    ]

    private let faqs = [
        FAQ(question: "Why can't eGuard verify the Screen Time passcode?", answer: "Apple doesn't expose that setting to apps. eGuard guides you through Settings and records your confirmation instead of pretending to verify it."),
        FAQ(question: "Does eGuard work in the simulator?", answer: "The app runs, but Apple's Screen Time frameworks only enforce protections on a real device."),
        FAQ(question: "Can I protect more than one child?", answer: "Install eGuard on each child's device. Apple's controls apply to the device the app is installed on."),
        FAQ(question: "What happens when I reset?", answer: "Every restriction eGuard applied is removed immediately and all local data, including the account, is deleted."),
    ]

    private var filteredTopics: [Topic] {
        guard !query.isEmpty else { return topics }
        return topics.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
    }

    private var filteredFAQs: [FAQ] {
        guard !query.isEmpty else { return faqs }
        return faqs.filter { $0.question.localizedCaseInsensitiveContains(query) || $0.answer.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        EGuardScreen {
            HStack(spacing: EGuardSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(EGuardColors.neutral)
                TextField("Search for help…", text: $query)
                    .textInputAutocapitalization(.never)
            }
            .padding(EGuardSpacing.sm)
            .background(EGuardColors.surface, in: EGuardShapes.button)
            .overlay(EGuardShapes.button.strokeBorder(EGuardColors.divider))

            if filteredTopics.isEmpty && filteredFAQs.isEmpty {
                EmptyStateView(symbolName: "magnifyingglass", title: "No results", message: "Try a different word, or contact support below.")
            }

            if !filteredTopics.isEmpty {
                EGuardCard {
                    ForEach(filteredTopics) { topic in
                        VStack(alignment: .leading, spacing: EGuardSpacing.xs) {
                            EGuardNavRow(title: topic.title, subtitle: topic.subtitle, symbolName: topic.symbol, tint: topic.tint) {
                                withAnimation(.snappy) {
                                    expandedTopic = expandedTopic == topic.id ? nil : topic.id
                                }
                            }
                            if expandedTopic == topic.id {
                                Text(topic.body)
                                    .font(EGuardTypography.callout)
                                    .foregroundStyle(EGuardColors.textSecondary)
                                    .padding(.leading, 48)
                                    .padding(.bottom, EGuardSpacing.xs)
                            }
                        }
                        if topic.id != filteredTopics.last?.id { Divider() }
                    }
                }
            }

            if !filteredFAQs.isEmpty {
                VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                    SectionHeader(title: "FAQs")
                    EGuardCard {
                        ForEach(filteredFAQs) { faq in
                            DisclosureGroup {
                                Text(faq.answer)
                                    .font(EGuardTypography.callout)
                                    .foregroundStyle(EGuardColors.textSecondary)
                                    .padding(.top, EGuardSpacing.xxs)
                            } label: {
                                Text(faq.question)
                                    .font(EGuardTypography.label)
                                    .foregroundStyle(EGuardColors.textPrimary)
                            }
                            .tint(EGuardColors.primary)
                            if faq.id != filteredFAQs.last?.id { Divider() }
                        }
                    }
                }
            }

            supportBanner
        } actions: {
            Button("Email Support") {
                if let url = URL(string: "mailto:support@eguard.app?subject=eGuard%20support") { openURL(url) }
            }
            .buttonStyle(.eGuardPrimary)
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
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

#Preview {
    NavigationStack {
        HelpSupportView()
    }
}
