import Observation
import SwiftUI

/// Holds the draft profile and validation for the Child & Device step.
@Observable
final class ChildDeviceViewModel {
    var profile = ChildProfile()
    private(set) var hasLoaded = false

    func load(from model: AppModel) {
        guard !hasLoaded else { return }
        if let existing = model.childProfile {
            profile = existing
        }
        hasLoaded = true
    }

    var canContinue: Bool {
        profile.isValid
    }

    /// Plain-language explanation of Apple's prerequisites for the chosen relationship.
    var prerequisiteNote: String? {
        switch profile.relationship {
        case .childInFamilySharing:
            "eGuard must be installed on \(profile.trimmedName.isEmpty ? "your child" : profile.trimmedName)'s device. A parent or guardian in your Family Sharing group approves it there."
        case .thisDeviceOwner:
            "Apple lets the device owner approve eGuard with Face ID, Touch ID, or the device passcode. Some protections that stop a child from removing eGuard do not apply."
        case .notSure:
            "Check Settings › your name › Family on this device. If the account appears under Family and is marked as a child, choose the first option."
        }
    }

    func save(to model: AppModel) {
        model.saveChildProfile(profile)
    }
}

/// 02 Child & Device
struct ChildDeviceView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ChildDeviceViewModel()
    @FocusState private var isNameFocused: Bool

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            OnboardingProgressIndicator(step: .childDevice)
            ScreenHeader(title: "Who are you protecting?")

            EGuardCard {
                Text("Child")
                    .font(EGuardTypography.overline)
                    .foregroundStyle(EGuardColors.textSecondary)
                TextField("Child's name", text: $viewModel.profile.name)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .font(EGuardTypography.title)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier("child.nameField")
                Divider()
                Picker("Age", selection: $viewModel.profile.age) {
                    ForEach(ChildProfile.ageRange, id: \.self) { age in
                        Text("\(age) years old").tag(age)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("child.agePicker")
            }

            EGuardCard {
                Text("Device")
                    .font(EGuardTypography.overline)
                    .foregroundStyle(EGuardColors.textSecondary)
                Picker("Device", selection: $viewModel.profile.device) {
                    ForEach(DevicePlatform.allCases) { device in
                        Label(device.displayName, systemImage: device.symbolName).tag(device)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("child.devicePicker")
                EGuardValueRow(label: "System", value: viewModel.profile.device.operatingSystemName)
            }

            VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                Text("Apple account")
                    .font(EGuardTypography.overline)
                    .foregroundStyle(EGuardColors.textSecondary)
                ForEach(FamilyRelationshipStatus.allCases) { status in
                    SelectableOptionRow(
                        title: status.title,
                        subtitle: status.explanation,
                        isSelected: viewModel.profile.relationship == status
                    ) {
                        viewModel.profile.relationship = status
                    }
                    .accessibilityIdentifier("child.relationship.\(status.rawValue)")
                }
            }

            if let note = viewModel.prerequisiteNote {
                EGuardCard {
                    Label {
                        Text(note)
                            .font(EGuardTypography.callout)
                            .foregroundStyle(EGuardColors.textSecondary)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(EGuardColors.primary)
                    }
                }
            }
        } actions: {
            Button("Continue") {
                viewModel.save(to: model)
                router.push(.protectionProfile)
            }
            .buttonStyle(.eGuardPrimary)
            .disabled(!viewModel.canContinue)
            .accessibilityIdentifier("child.continue")
        }
        .navigationTitle(OnboardingStep.childDevice.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load(from: model) }
    }
}

#Preview {
    NavigationStack {
        ChildDeviceView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}
