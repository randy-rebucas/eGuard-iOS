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
    @State private var kind: CodeKind = .device
    @State private var browserLabel = ""

    /// Phone-app codes and browser-extension codes are different and never interchangeable.
    private enum CodeKind: String, CaseIterable, Hashable {
        case device, browser
        var title: String { self == .device ? "Phone or tablet" : "Browser extension" }
    }

    var body: some View {
        NavigationStack {
            EGuardScreen {
                ScreenHeader(
                    title: kind == .device ? "Pair your child's device" : "Add a browser",
                    subtitle: kind == .device
                        ? "Install eGuard on the child's device, open it, choose \"This is my child's device\" and enter this code."
                        : "Install the eGuard browser extension on the child's computer and enter this code on its setup page."
                )

                PillSegmentedControl(options: CodeKind.allCases, selection: $kind) { $0.title }

                if kind == .browser, state.value?.isBrowserCode != true {
                    EGuardTextField(label: "Computer or browser name", placeholder: "Mia's MacBook", text: $browserLabel, symbolName: "laptopcomputer", autocapitalization: .words)
                    Button("Create browser code") { Task { await requestCode() } }
                        .buttonStyle(.eGuardSecondary)
                        .disabled(browserLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                switch state {
                case .loading where kind == .browser:
                    EmptyView()
                case .loading:
                    LoadingCard(message: "Creating a code…")
                case .failed(let message):
                    ErrorCard(message: message) { Task { await requestCode() } }
                    if message.contains("Verify") || message.contains("verify") {
                        VerifyEmailBanner()
                    }
                case .loaded(let code) where code.isBrowserCode == (kind == .browser):
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
                    } else if kind == .device {
                        HStack(spacing: EGuardSpacing.xs) {
                            ProgressView()
                            Text("Waiting for the device…")
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                        }
                    } else {
                        Text("Connected browsers appear on the Devices tab. They count toward your plan's device slots.")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                case .loaded:
                    EmptyView()
                }

                if kind == .device {
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
                        Divider()
                        EGuardNavRow(title: "This phone or tablet", subtitle: "Hand this device down: Settings › Set up this device for a child", symbolName: "arrow.triangle.swap", tint: EGuardColors.tilePurple) {
                            router.push(.setUpChildDevice)
                            dismiss()
                        }
                    }
                }

                if kind == .device, let mock = model.api as? MockEGuardAPI {
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
        .onChange(of: kind) { _, newKind in
            // Switching kinds asks for the matching code; a browser code needs a label first.
            if newKind == .device { Task { await requestCode() } } else { state = .loading }
        }
    }

    private func spaced(_ code: String) -> String {
        let characters = Array(code)
        guard characters.count == 8 else { return code }
        return String(characters[0..<4]) + " " + String(characters[4..<8])
    }

    private func requestCode() async {
        state = .loading
        let label = browserLabel.trimmingCharacters(in: .whitespaces)
        state = await load {
            kind == .browser
                ? try await model.api.browserPairingCode(childId: childId, deviceLabel: label)
                : try await model.api.pairingCode(childId: childId)
        }
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
