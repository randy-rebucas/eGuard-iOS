import SwiftUI

/// Website rules for a child's eGuard browser extensions: `GET`/`PUT /children/{id}/browser-policy`.
/// Saves carry the version the parent saw, so a concurrent change is refused instead of undone.
struct BrowserPolicyView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @State private var state: LoadState<BrowserPolicy> = .loading
    @State private var draft: BrowserPolicy?
    @State private var newBlocked = ""
    @State private var newAllowed = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var message: String?

    private let unknownPolicies = [("ALLOW", "Allow"), ("WARN", "Warn first"), ("BLOCK", "Block")]

    var body: some View {
        EGuardScreen {
            ScreenHeader(title: "Website rules", subtitle: "Applies to every eGuard browser extension connected for this child. Browsers pick up changes within 5 minutes.")
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let error):
                ErrorCard(message: error) { Task { await loadPolicy() } }
            case .loaded(let policy):
                if let draft {
                    editor(policy: policy, draft: Binding(get: { draft }, set: { self.draft = $0 }))
                }
            }
            if let message {
                Label(message, systemImage: "checkmark.circle.fill").font(EGuardTypography.caption).foregroundStyle(EGuardColors.success)
            }
            InlineError(message: errorMessage)
        } actions: {
            Button(isSaving ? "Saving…" : "Save Rules") { Task { await save() } }
                .buttonStyle(.eGuardPrimary)
                .disabled(isSaving || draft == nil || draft == state.value)
        }
        .navigationTitle("Website rules")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPolicy() }
    }

    @ViewBuilder
    private func editor(policy: BrowserPolicy, draft: Binding<BrowserPolicy>) -> some View {
        EGuardCard {
            Toggle("Safe browsing", isOn: draft.safeBrowsing).tint(EGuardColors.primary)
            Divider()
            Toggle("Safe search", isOn: draft.safeSearch).tint(EGuardColors.primary)
            Divider()
            VStack(alignment: .leading, spacing: EGuardSpacing.xs) {
                Text("Sites on neither list").font(EGuardTypography.label)
                Picker("Sites on neither list", selection: draft.unknownSitesPolicy) {
                    ForEach(unknownPolicies, id: \.0) { id, title in Text(title).tag(id) }
                }
                .pickerStyle(.segmented)
                Text(draft.wrappedValue.unknownSitesPolicy == "BLOCK" ? "Only the allowed list can be visited." : (draft.wrappedValue.unknownSitesPolicy == "WARN" ? "A notice shows before an unlisted site opens." : "Unlisted sites open normally."))
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }

        if let categories = policy.categories, !categories.isEmpty {
            EGuardCard {
                SectionHeader(title: "Blocked categories")
                ForEach(categories) { category in
                    Toggle(isOn: Binding(
                        get: { draft.wrappedValue.blockedCategories.contains(category.key) },
                        set: { on in
                            if on { draft.wrappedValue.blockedCategories.append(category.key) } else { draft.wrappedValue.blockedCategories.removeAll { $0 == category.key } }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.label).font(EGuardTypography.label)
                            if let hint = category.hint { Text(hint).font(EGuardTypography.caption).foregroundStyle(EGuardColors.textSecondary) }
                        }
                    }
                    .tint(EGuardColors.primary)
                    if category.id != categories.last?.id { Divider() }
                }
            }
        }

        domainList(title: "Blocked sites", domains: draft.blockedDomains, input: $newBlocked, placeholder: "example.com")
        domainList(title: "Allowed sites", domains: draft.allowedDomains, input: $newAllowed, placeholder: "school.edu")

        EGuardCard {
            Toggle("Focus hours", isOn: Binding(
                get: { draft.wrappedValue.schedule?.enabled ?? false },
                set: { on in
                    if on {
                        draft.wrappedValue.schedule = BrowserSchedule(enabled: true, startTime: draft.wrappedValue.schedule?.startTime ?? "21:00", endTime: draft.wrappedValue.schedule?.endTime ?? "06:00")
                    } else {
                        draft.wrappedValue.schedule = nil
                    }
                }
            ))
            .tint(EGuardColors.primary)
            if let schedule = draft.wrappedValue.schedule {
                DatePicker("From", selection: Binding(
                    get: { ProtectionConfigFormatter.timeOfDay(schedule.startTime).date() },
                    set: { draft.wrappedValue.schedule?.startTime = ProtectionConfigFormatter.hhmm(TimeOfDay(date: $0)) }
                ), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: Binding(
                    get: { ProtectionConfigFormatter.timeOfDay(schedule.endTime).date() },
                    set: { draft.wrappedValue.schedule?.endTime = ProtectionConfigFormatter.hhmm(TimeOfDay(date: $0)) }
                ), displayedComponents: .hourAndMinute)
                Text("During focus hours only the allowed list can be visited.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }

        if let updatedBy = policy.updatedBy {
            Text("Last changed by \(updatedBy)\(policy.updatedAt.map { " · \($0.verifiedDescription())" } ?? "")")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
        }
    }

    private func domainList(title: String, domains: Binding<[String]>, input: Binding<String>, placeholder: String) -> some View {
        EGuardCard {
            SectionHeader(title: title)
            ForEach(domains.wrappedValue, id: \.self) { domain in
                HStack {
                    Text(domain).font(EGuardTypography.callout)
                    Spacer()
                    Button { domains.wrappedValue.removeAll { $0 == domain } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(EGuardColors.danger)
                    }
                    .accessibilityLabel("Remove \(domain)")
                }
            }
            HStack(spacing: EGuardSpacing.xs) {
                TextField(placeholder, text: input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(EGuardTypography.callout)
                Button("Add") {
                    let site = Self.normalize(input.wrappedValue)
                    guard !site.isEmpty, !domains.wrappedValue.contains(site) else { return }
                    domains.wrappedValue.append(site)
                    domains.wrappedValue.sort()
                    input.wrappedValue = ""
                }
                .font(EGuardTypography.label)
                .disabled(Self.normalize(input.wrappedValue).isEmpty)
            }
        }
    }

    /// `https://www.x.com/page` becomes `www.x.com`, matching the server's normalisation.
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        return text
    }

    private func loadPolicy() async {
        state = await load { try await model.api.browserPolicy(childId: childId) }
        draft = state.value
    }

    private func save() async {
        guard let draft else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await model.api.updateBrowserPolicy(childId: childId, policy: draft.update)
            state = .loaded(saved)
            self.draft = saved
            message = "Saved. Browsers pick this up within 5 minutes."
            errorMessage = nil
        } catch let error as APIError where error.code == "stale_version" {
            errorMessage = error.localizedDescription
            await loadPolicy()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        BrowserPolicyView(childId: "child_3")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
