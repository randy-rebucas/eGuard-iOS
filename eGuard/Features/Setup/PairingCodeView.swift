import SwiftUI

/// "Set up supervision": shows the 8-character pairing code and waits for the child's device to appear.
struct PairingCodeView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<PairingCode> = .loading
    @State private var isPaired = false
    /// When the shown code stops working, on this phone's clock, from `expiresInSeconds` when it arrived.
    @State private var deadline: Date?
    @State private var kind: CodeKind = .device
    @State private var browserLabel = ""
    /// The device code, kept while the parent looks at the browser tab so coming back doesn't replace it.
    @State private var deviceCode: (code: PairingCode, deadline: Date)?
    /// The devices the child had when the sheet opened: a new id is the one that just paired.
    @State private var knownDevices: Set<String>?
    @State private var emailUnverified = false
    /// A browser code is on its way: "Create browser code" ignores taps (each tap would make a code).
    @State private var isCreatingBrowserCode = false

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
                    Button(isCreatingBrowserCode ? "Creating…" : "Create browser code") { Task { await requestCode() } }
                        .buttonStyle(.eGuardSecondary)
                        .disabled(browserLabel.trimmingCharacters(in: .whitespaces).isEmpty || isCreatingBrowserCode)
                }

                switch state {
                case .loading where kind == .browser:
                    EmptyView()
                case .loading:
                    LoadingCard(message: "Creating a code…")
                case .failed(let message):
                    ErrorCard(message: message) { Task { await requestCode() } }
                    if emailUnverified {
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
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let left = secondsLeft(at: context.date)
                            Text(left > 0 ? "Valid for \(left / 60) min \(left % 60) s · single use" : "This code expired.")
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if !isPaired {
                        // Re-evaluated every second, so the button appears the moment the code expires
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if secondsLeft(at: context.date) == 0 {
                                Button("Get a new code") { Task { await requestCode() } }
                                    .buttonStyle(.eGuardSecondary)
                                    .accessibilityIdentifier("pairing.newCode")
                            }
                        }
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
                        EGuardNavRow(title: "Android", subtitle: "The eGuard app; no Family Link needed", symbolName: "smartphone", tint: EGuardColors.success) {
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

                #if DEBUG
                if kind == .device, let mock = model.api as? MockEGuardAPI {
                    Button("Simulate device pairing (test server)") {
                        mock.simulatePairing(childId: childId)
                    }
                    .buttonStyle(.eGuardSecondary)
                    .accessibilityIdentifier("pairing.simulate")
                }
                #endif
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
            // A browser code needs a label first. Back on the phone tab, the code already made still works (a new one
            // would replace it, and count toward the 20 an hour), so it's shown again while it's valid.
            if newKind == .device {
                if let kept = deviceCode, kept.deadline > .now {
                    state = .loaded(kept.code)
                    deadline = kept.deadline
                } else {
                    Task { await requestCode() }
                }
            } else {
                state = .loading
            }
        }
    }

    private func spaced(_ code: String) -> String {
        let characters = Array(code)
        guard characters.count == 8 else { return code }
        return String(characters[0..<4]) + " " + String(characters[4..<8])
    }

    private func secondsLeft(at date: Date) -> Int {
        guard let deadline else { return 0 }
        return max(0, Int(deadline.timeIntervalSince(date).rounded(.up)))
    }

    private func requestCode() async {
        let browser = kind == .browser
        if browser {
            guard !isCreatingBrowserCode else { return }
            isCreatingBrowserCode = true
        }
        defer { if browser { isCreatingBrowserCode = false } }
        state = .loading
        emailUnverified = false
        let label = browserLabel.trimmingCharacters(in: .whitespaces)
        do {
            let code = browser
                ? try await model.api.browserPairingCode(childId: childId, deviceLabel: label)
                : try await model.api.pairingCode(childId: childId)
            let end = code.expiresInSeconds.map { Date.now.addingTimeInterval(TimeInterval($0)) } ?? code.expiresAt
            deadline = end
            if !browser { deviceCode = (code, end) }
            state = .loaded(code)
        } catch {
            emailUnverified = (error as? APIError)?.code == "email_unverified"
            state = .failed(error.localizedDescription)
        }
    }

    /// Polls the child while a phone code is valid, until a device that wasn't there before appears.
    private func pollForDevice() async {
        while !Task.isCancelled && !isPaired {
            // The first look (before sleeping) records the devices the child already has
            if knownDevices != nil { try? await Task.sleep(for: BatchPoller.interval) }
            // Nothing can pair with an expired code (or none yet): wait for "Get a new code"
            if knownDevices != nil, !(deviceCode.map { $0.deadline > .now } ?? false) {
                continue
            }
            do {
                let ids = Set(try await model.api.child(id: childId).devices.map(\.id))
                guard let known = knownDevices else { knownDevices = ids; continue }
                if !ids.subtracting(known).isEmpty {
                    isPaired = true
                    await model.refreshDashboard()
                }
            } catch let error as APIError where error.status == 404 {
                // The child was removed (another parent, or the web): nothing left to pair
                state = .failed(error.localizedDescription)
                return
            } catch {
                if knownDevices == nil { try? await Task.sleep(for: BatchPoller.interval) }
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

#if DEBUG
#Preview {
    PairingCodeView(childId: "child_1")
        .environment(AppModel.preview())
        .environment(AppRouter())
}
#endif
