import Observation
import PhotosUI
import SwiftUI

/// Holds the draft profile and validation for the Add Child step.
@Observable
final class ChildDeviceViewModel {
    var profile = ChildProfile()
    var photoItem: PhotosPickerItem?
    var isShowingPhotoPicker = false
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

    /// Loads the chosen photo and shrinks it so the profile stays small in the Keychain.
    func loadPhoto() async {
        guard let photoItem else { return }
        guard let data = try? await photoItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        profile.photoData = Self.thumbnailData(from: image)
    }

    static func thumbnailData(from image: UIImage, maxDimension: CGFloat = 300) -> Data? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8)
    }

    func save(to model: AppModel) {
        model.saveChildProfile(profile)
    }
}

/// 04 Add Child (Child & Device)
struct ChildDeviceView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ChildDeviceViewModel()
    @FocusState private var isNameFocused: Bool

    private var isEditing: Bool { model.isSetupComplete }

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            if !isEditing {
                OnboardingProgressIndicator(step: .childDevice)
            }
            ScreenHeader(
                title: isEditing ? "Edit child & device" : "Tell us about your child",
                subtitle: "We'll personalize the setup for your family."
            )

            photoPicker

            VStack(spacing: EGuardSpacing.sm) {
                EGuardTextField(
                    label: "Child's name",
                    placeholder: "Mia",
                    text: $viewModel.profile.name,
                    symbolName: "person",
                    contentType: .givenName,
                    autocapitalization: .words,
                    identifier: "child.nameField"
                )

                HStack(spacing: EGuardSpacing.sm) {
                    Image(systemName: "birthday.cake")
                        .foregroundStyle(EGuardColors.neutral)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Age")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                        Picker("Age", selection: $viewModel.profile.age) {
                            ForEach(ChildProfile.ageRange, id: \.self) { age in
                                Text("\(age) years old").tag(age)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(EGuardColors.textPrimary)
                        .accessibilityIdentifier("child.agePicker")
                    }
                    Spacer()
                }
                .padding(.horizontal, EGuardSpacing.sm)
                .padding(.vertical, EGuardSpacing.xs)
                .background(EGuardColors.surface, in: EGuardShapes.button)
                .overlay(EGuardShapes.button.strokeBorder(EGuardColors.divider, lineWidth: 1))
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
                        symbolName: symbol(for: status),
                        tint: EGuardColors.primary,
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
            Button(isEditing ? "Save" : "Continue") {
                viewModel.save(to: model)
                if isEditing {
                    router.pop()
                } else {
                    router.push(.protectionProfile)
                }
            }
            .buttonStyle(.eGuardPrimary)
            .disabled(!viewModel.canContinue)
            .accessibilityIdentifier("child.continue")
        }
        .brandNavigationTitle()
        .onAppear { viewModel.load(from: model) }
        .task(id: viewModel.photoItem) { await viewModel.loadPhoto() }
    }

    /// A plain button presents the system picker, so no remote view sits in the layout
    /// and intercepts taps meant for the fields below.
    private var photoPicker: some View {
        @Bindable var viewModel = viewModel
        return Button {
            viewModel.isShowingPhotoPicker = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(name: viewModel.profile.trimmedName, imageData: viewModel.profile.photoData, size: 108)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: EGuardColors.primary.opacity(0.15), radius: 10, y: 4)
                Image(systemName: "camera.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(EGuardColors.primary, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(viewModel.profile.photoData == nil ? "Add a photo" : "Change photo")
        .accessibilityIdentifier("child.photo")
        .photosPicker(isPresented: $viewModel.isShowingPhotoPicker, selection: $viewModel.photoItem, matching: .images)
    }

    private func symbol(for status: FamilyRelationshipStatus) -> String {
        switch status {
        case .childInFamilySharing: "person.2.fill"
        case .thisDeviceOwner: "iphone"
        case .notSure: "questionmark.circle.fill"
        }
    }
}

#Preview {
    NavigationStack {
        ChildDeviceView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}
