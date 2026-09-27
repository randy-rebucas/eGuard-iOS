import SwiftUI

/// Native controls for one protection's config object, keyed by the server's protection `KEY`.
/// Edits the JSON directly so the same form serves Recommended Setup overrides and single-protection changes.
struct ProtectionConfigEditor: View {
    let key: String
    @Binding var config: JSONValue

    static let minuteOptions = [30, 45, 60, 90, 120, 150, 180, 210, 240, 300, 360, 480]
    static let ratingTiers = ProtectionDefaults.ratingTiers

    var body: some View {
        Section {
            switch key {
            case "SCREEN_TIME":
                minutesPicker("Weekdays", field: "dailyMinutes")
                minutesPicker("Weekends", field: "weekendMinutes")
            case "BEDTIME":
                toggle("Bedtime", field: "enabled")
                if config["enabled"]?.boolValue != false {
                    timePicker("Starts", field: "start", fallback: "21:30")
                    timePicker("Ends", field: "end", fallback: "06:00")
                    Picker("Days", selection: stringBinding("days", fallback: "EVERY_DAY")) {
                        Text("Every day").tag("EVERY_DAY")
                        Text("School nights").tag("SCHOOL_NIGHTS")
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
                    Text("Allow list only").tag("ALLOWLIST")
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

    private func minutesPicker(_ title: String, field: String) -> some View {
        Picker(title, selection: Binding(
            get: { config[field]?.intValue ?? 180 },
            set: { config = config.setting(field, to: .number(Double($0))) }
        )) {
            ForEach(Self.minuteOptions, id: \.self) { minutes in
                Text(ProtectionConfigFormatter.duration(minutes)).tag(minutes)
            }
        }
    }

    private func ratingPicker(_ title: String) -> some View {
        Picker(title, selection: Binding(
            get: { config["maxAgeRating"]?.intValue ?? 13 },
            set: { config = config.setting("maxAgeRating", to: .number(Double($0))) }
        )) {
            ForEach(Self.ratingTiers, id: \.self) { tier in
                Text("\(tier)+").tag(tier)
            }
        }
        .pickerStyle(.segmented)
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
