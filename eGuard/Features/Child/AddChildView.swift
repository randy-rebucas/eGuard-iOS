import Observation
import PhotosUI
import SwiftUI

/// Creates or edits a child on the server, then uploads the photo.
@Observable
final class AddChildViewModel {
    var name = ""
    var age = 12
    var photoItem: PhotosPickerItem?
    var photoData: Data?
    var isShowingPhotoPicker = false
    var isSubmitting = false
    var errorMessage: String?
    private(set) var hasLoaded = false

    static let ageRange = 0...17

    var canContinue: Bool {
        (1...40).contains(name.trimmingCharacters(in: .whitespaces).count) && !isSubmitting
    }

    func load(childId: String?, model: AppModel) async {
        guard !hasLoaded, let childId else { hasLoaded = true; return }
        hasLoaded = true
        if let child = model.children.first(where: { $0.id == childId }) {
            name = child.name
            age = child.age
            if let url = child.photoUrl { photoData = await model.photo(for: childId, url: url) }
        }
    }

    /// Loads the chosen photo and shrinks it to about 512 px so it stays under the 2 MB limit.
    func loadPhoto() async {
        guard let photoItem else { return }
        guard let data = try? await photoItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        photoData = Self.thumbnailData(from: image)
    }

    static func thumbnailData(from image: UIImage, maxDimension: CGFloat = 512) -> Data? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.85)
    }

    /// Saves and returns the child's id, or nil on failure.
    func save(childId: String?, model: AppModel) async -> String? {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let id: String
            if let childId {
                id = try await model.api.updateChild(id: childId, name: name.trimmingCharacters(in: .whitespaces), age: age).child.id
            } else {
                id = try await model.api.createChild(name: name.trimmingCharacters(in: .whitespaces), age: age, profile: nil).id
            }
            if photoItem != nil, let photoData {
                _ = try await model.api.uploadPhoto(childId: id, data: photoData, contentType: "image/jpeg")
            }
            await model.refreshDashboard()
            errorMessage = nil
            return id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

/// 04 Add Child (also edits an existing child)
struct AddChildView: View {
    let childId: String?

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = AddChildViewModel()

    private var isEditing: Bool { childId != nil }

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            if !isEditing {
                OnboardingProgressIndicator(step: .childDevice)
            }
            ScreenHeader(
                title: isEditing ? "Edit child" : "Tell us about your child",
                subtitle: "We'll personalize the setup for your family."
            )

            photoPicker

            VStack(spacing: EGuardSpacing.sm) {
                EGuardTextField(
                    label: "Child's name",
                    placeholder: "Mia",
                    text: $viewModel.name,
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
                        Picker("Age", selection: $viewModel.age) {
                            ForEach(AddChildViewModel.ageRange, id: \.self) { age in
                                Text(age == 0 ? "Under 1" : "\(age) years old").tag(age)
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

            InlineError(message: viewModel.errorMessage)

            EGuardCard {
                Label {
                    Text("You'll pair \(viewModel.name.isEmpty ? "your child" : viewModel.name)'s device with a code in a moment. Protections are saved now and applied as soon as a device is paired.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(EGuardColors.primary)
                }
            }
        } actions: {
            Button(viewModel.isSubmitting ? "Saving…" : (isEditing ? "Save" : "Continue")) {
                Task {
                    guard let id = await viewModel.save(childId: childId, model: model) else { return }
                    if isEditing {
                        router.pop()
                    } else {
                        router.push(.protectionProfile(childId: id))
                    }
                }
            }
            .buttonStyle(.eGuardPrimary)
            .disabled(!viewModel.canContinue)
            .accessibilityIdentifier("child.continue")
        }
        .brandNavigationTitle()
        .task { await viewModel.load(childId: childId, model: model) }
        .task(id: viewModel.photoItem) { await viewModel.loadPhoto() }
    }

    /// A plain button presents the system picker, so no remote view sits in the layout.
    private var photoPicker: some View {
        @Bindable var viewModel = viewModel
        return Button {
            viewModel.isShowingPhotoPicker = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(name: viewModel.name.trimmingCharacters(in: .whitespaces), imageData: viewModel.photoData, size: 108)
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
        .accessibilityLabel(viewModel.photoData == nil ? "Add a photo" : "Change photo")
        .accessibilityIdentifier("child.photo")
        .photosPicker(isPresented: $viewModel.isShowingPhotoPicker, selection: $viewModel.photoItem, matching: .images)
    }
}

#Preview {
    NavigationStack {
        AddChildView(childId: nil)
    }
    .environment(AppModel.mock(signedIn: true))
    .environment(AppRouter())
}
