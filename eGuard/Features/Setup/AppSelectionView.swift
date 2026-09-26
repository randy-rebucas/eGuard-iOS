import FamilyControls
import SwiftUI

/// Wraps Apple's Family Activity Picker with eGuard's friendly labels.
/// The picker shows app names and icons itself; eGuard never sees or shows bundle identifiers.
struct AppSelectionView: View {
    let purpose: SelectionPurpose

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: EGuardSpacing.xs) {
                    Text(purpose.instruction)
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                    Text(ActivitySelectionCodec.snapshot(from: selection).summary)
                        .font(EGuardTypography.label)
                        .accessibilityIdentifier("selection.summary")
                }
                .padding(.horizontal, EGuardSpacing.md)
                .padding(.vertical, EGuardSpacing.sm)

                if model.authorizationStatus.isAuthorized && !model.environment.isSimulator {
                    FamilyActivityPicker(selection: $selection)
                } else {
                    unavailableNotice
                }
            }
            .background(EGuardColors.background)
            .navigationTitle(purpose.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.updateSelection(ActivitySelectionCodec.snapshot(from: selection), for: purpose)
                        dismiss()
                    }
                    .accessibilityIdentifier("selection.done")
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                if let existing = ActivitySelectionCodec.selection(from: model.selections[purpose]) {
                    selection = existing
                }
            }
        }
    }

    private var unavailableNotice: some View {
        VStack(spacing: EGuardSpacing.md) {
            EGuardIllustration(symbolName: "square.grid.2x2", tint: EGuardColors.neutral)
            Text(model.authorizationStatus.isAuthorized
                 ? "Apple's app picker is only available on a real device."
                 : "Grant Family Controls authorization to choose apps.")
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(EGuardSpacing.lg)
    }
}

#Preview {
    AppSelectionView(purpose: .gaming)
        .environment(AppModel.mock(authorizationStatus: .approved))
}
