import SwiftUI

/// "Set up supervision": shows the 8-character pairing code and waits for the child's device to appear.
struct PairingCodeView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<PairingCode> = .loading
    @State private var isPaired = false
    @State private var secondsLeft = 15 * 60

    var body: some View {
        NavigationStack {
            EGuardScreen {
                ScreenHeader(
                    title: "Pair your child's device",
                    subtitle: "Install eGuard on the child's device, open it, and enter this code."
                )

                switch state {
                case .loading:
                    LoadingCard(message: "Creating a code…")
                case .failed(let message):
                    ErrorCard(message: message) { Task { await requestCode() } }
                    if message.contains("Verify") || message.contains("verify") {
                        VerifyEmailBanner()
                    }
                case .loaded(let code):
                    EGuardCard {
                        Text(spaced(code.code))
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .foregroundStyle(EGuardColors.primary)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Pairing code \(code.code.map(String.init).joined(separator: " "))")
                            .accessibilityIdentifier("pairing.code")
                        Text(secondsLeft > 0 ? "Valid for \(secondsLeft / 60) min \(secondsLeft % 60) s · single use" : "This code expired. Create a new one.")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }

                    if isPaired {
                        EGuardCard {
                            Label("\(code.childName)'s device is paired", systemImage: "checkmark.circle.fill")
                                .font(EGuardTypography.headline)
                                .foregroundStyle(EGuardColors.success)
                            Text("A first full check is running. You can close this sheet.")
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                        }
                        .accessibilityIdentifier("pairing.paired")
                    } else {
                        HStack(spacing: EGuardSpacing.xs) {
                            ProgressView()
                            Text("Waiting for the device…")
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                        }
                    }
                }

                EGuardCard {
                    SectionHeader(title: "On the child's device")
                    EGuardNavRow(title: "iPhone or iPad", subtitle: "Family Sharing and Screen Time", symbolName: "iphone") {
                        router.push(.helpArticle(slug: "ios-family-sharing"))
                        dismiss()
                    }
                    Divider()
                    EGuardNavRow(title: "Android", subtitle: "Family Link and device admin", symbolName: "smartphone", tint: EGuardColors.success) {
                        router.push(.helpArticle(slug: "android-family-link"))
                        dismiss()
                    }
                }

                if let mock = model.api as? MockEGuardAPI {
                    Button("Simulate device pairing (test server)") {
                        mock.simulatePairing(childId: childId)
                    }
                    .buttonStyle(.eGuardSecondary)
                    .accessibilityIdentifier("pairing.simulate")
                }
            } actions: {
                Button(isPaired ? "Done" : "Close") { dismiss() }
                    .buttonStyle(isPaired ? AnyButtonStyle(.eGuardPrimary) : AnyButtonStyle(.eGuardSecondary))
                    .accessibilityIdentifier("pairing.close")
            }
            .navigationTitle("Set up supervision")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await requestCode() }
        .task { await pollForDevice() }
    }

    private func spaced(_ code: String) -> String {
        let characters = Array(code)
        guard characters.count == 8 else { return code }
        return String(characters[0..<4]) + " " + String(characters[4..<8])
    }

    private func requestCode() async {
        state = .loading
        state = await load { try await model.api.pairingCode(childId: childId) }
        if let code = state.value {
            secondsLeft = max(0, Int(code.expiresAt.timeIntervalSinceNow))
        }
    }

    /// Polls the child until a device appears, and counts the code down.
    private func pollForDevice() async {
        while !Task.isCancelled && !isPaired {
            try? await Task.sleep(for: BatchPoller.interval)
            secondsLeft = max(0, secondsLeft - 1)
            if let detail = try? await model.api.child(id: childId), !detail.devices.isEmpty {
                isPaired = true
                await model.refreshDashboard()
            }
        }
    }
}

/// Type-erases a button style so a button can switch styles without duplicating itself.
struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}

#Preview {
    PairingCodeView(childId: "child_1")
        .environment(AppModel.preview())
        .environment(AppRouter())
}
