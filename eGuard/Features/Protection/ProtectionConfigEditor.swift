import SwiftUI

/// Native controls for one protection's config object, keyed by the server's protection `KEY`.
/// Edits the JSON directly so the same form serves Recommended Setup overrides and single-protection changes.
struct ProtectionConfigEditor: View {
    let key: String
    @Binding var config: JSONValue

    static let minuteOptions = [30, 45, 60, 90, 120, 150, 180, 210, 240, 300, 360, 480]
    /// As the web offers them (flow-dialogs RATINGS).
    static let ratingTiers = [4, 9, 12, 13, 16, 17, 18]

    /// The options plus the stored value: a Picker whose selection has no tag shows blank, and the web (or the
    /// server's own defaults, e.g. 270 weekend minutes for a teen) can store values off this list.
    static func options(_ list: [Int], including current: Int?) -> [Int] {
        Array(Set(list + [current].compactMap { $0 })).sorted()
    }

    /// Why the server would refuse this config, checked before saving; nil when it's fine.
    static func problem(key: String, config: JSONValue) -> String? {
        // Mirrors ConfigSchema: each limit 15–1440 minutes (an unset field shows, and keeps, the server's default)
        if key == "SCREEN_TIME",
           ["dailyMinutes", "weekendMinutes"].contains(where: { config[$0]?.intValue.map { $0 < 15 || $0 > 1440 } ?? false }) {
            return "Set each limit between 15 minutes and 24 hours."
        }
        if key == "BEDTIME", config["enabled"]?.boolValue != false,
           let start = config["start"]?.stringValue, start == config["end"]?.stringValue {
            return "Bedtime needs different start and end times."
        }
        return nil
    }

    var body: some View {
        Section {
            switch key {
            case "SCREEN_TIME":
                durationRow("Weekdays", field: "dailyMinutes")
                durationRow("Weekends", field: "weekendMinutes")
                if let problem = Self.problem(key: key, config: config) {
                    Text(problem)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.danger)
                }
            case "BEDTIME":
                toggle("Bedtime", field: "enabled")
                if config["enabled"]?.boolValue != false {
                    timePicker("Starts", field: "start", fallback: "21:30")
                    timePicker("Ends", field: "end", fallback: "06:00")
                    Picker("Days", selection: stringBinding("days", fallback: "EVERY_DAY")) {
                        Text("Every day").tag("EVERY_DAY")
                        Text("School nights").tag("SCHOOL_NIGHTS")
                    }
                    if let problem = Self.problem(key: key, config: config) {
                        Text(problem)
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.danger)
                    }
                }
            case "APP_RESTRICTIONS":
                ratingPicker("Apps rated up to")
            case "CONTENT":
                ratingPicker("Content rated up to")
            case "APP_APPROVAL":
                toggle("Require approval for new apps", field: "enabled")
            case "WEB":
                Picker("Web filtering", selection: stringBinding("mode", fallback: "FILTER")) {
                    Text("Off").tag("OFF")
                    Text("Filter adult websites").tag("FILTER")
                    Text("Allowed sites only").tag("ALLOWLIST")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            case "DOWNLOADS":
                toggle("Ask a parent before downloading", field: "requireApproval")
            case "LOCATION":
                toggle("Share location with parents", field: "sharing")
            case "NOTIFICATIONS":
                toggle("Quiet notifications during bedtime", field: "quietDuringBedtime")
            case "UNINSTALL_PROTECTION":
                toggle("Prevent removing eGuard", field: "enabled")
            default:
                Text("This protection has no adjustable values.")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(ProtectionKey.explanation(key))
        }
    }

    // MARK: Controls

    private func toggle(_ title: String, field: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { config[field]?.boolValue ?? false },
            set: { config = config.setting(field, to: .bool($0)) }
        ))
        .tint(EGuardColors.primary)
    }

    /// Hours + minutes for one limit, as on the web (flow-dialogs DurationField); stored as total minutes.
    private func durationRow(_ title: String, field: String) -> some View {
        let total = config[field]?.intValue ?? 180
        let store = { (h: Int, m: Int) in
            // 24 h is the most allowed, so its minutes drop to 0
            config = config.setting(field, to: .number(Double(h == 24 ? 1440 : h * 60 + m)))
        }
        return LabeledContent(title) {
            HStack(spacing: 4) {
                Picker("\(title) hours", selection: Binding(get: { total / 60 }, set: { store($0, total % 60) })) {
                    ForEach(0...24, id: \.self) { Text("\($0) h").tag($0) }
                }
                Picker("\(title) minutes", selection: Binding(get: { total % 60 }, set: { store(total / 60, $0) })) {
                    // Every 5 minutes, plus a stored value off that step so the picker isn't blank
                    ForEach(Self.options(Array(stride(from: 0, to: 60, by: 5)), including: total % 60), id: \.self) { Text("\($0) min").tag($0) }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func ratingPicker(_ title: String) -> some View {
        Picker(title, selection: Binding(
            get: { config["maxAgeRating"]?.intValue ?? 13 },
            set: { config = config.setting("maxAgeRating", to: .number(Double($0))) }
        )) {
            ForEach(Self.options(Self.ratingTiers, including: config["maxAgeRating"]?.intValue), id: \.self) { tier in
                Text("\(tier)+").tag(tier)
            }
        }
        // A menu: seven or more ratings don't fit a segmented control on a phone
        .pickerStyle(.menu)
    }

    private func timePicker(_ title: String, field: String, fallback: String) -> some View {
        DatePicker(
            title,
            selection: Binding(
                get: { ProtectionConfigFormatter.timeOfDay(config[field]?.stringValue ?? fallback).date() },
                set: { config = config.setting(field, to: .string(ProtectionConfigFormatter.hhmm(TimeOfDay(date: $0)))) }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private func stringBinding(_ field: String, fallback: String) -> Binding<String> {
        Binding(
            get: { config[field]?.stringValue ?? fallback },
            set: { config = config.setting(field, to: .string($0)) }
        )
    }
}

/// A sheet wrapping the editor with a title and Done button.
struct ProtectionConfigSheet: View {
    let key: String
    @Binding var config: JSONValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ProtectionConfigEditor(key: key, config: $config)
                Section {
                    EGuardValueRow(label: "Summary", value: ProtectionConfigFormatter.label(key: key, config: config))
                }
            }
            .navigationTitle(ProtectionKey.name(key))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("editor.done")
                }
            }
        }
    }
}

#Preview {
    ProtectionConfigSheet(key: "BEDTIME", config: .constant(ProtectionDefaults.config(key: "BEDTIME", age: 12, profile: "PROTECTED")))
}
