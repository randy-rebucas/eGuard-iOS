import SwiftUI

/// Where an API-backed screen is in its load cycle.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// Runs an API call and maps the result or error into a `LoadState`.
func load<Value>(_ operation: () async throws -> Value) async -> LoadState<Value> {
    do {
        return .loaded(try await operation())
    } catch {
        return .failed(error.localizedDescription)
    }
}

/// A centered spinner used while a screen loads.
struct LoadingCard: View {
    var message = "Loading…"

    var body: some View {
        EGuardCard {
            HStack(spacing: EGuardSpacing.sm) {
                ProgressView()
                Text(message)
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("loading")
    }
}

/// A parent-friendly error with a retry button.
struct ErrorCard: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        EGuardCard {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.danger)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.eGuardSecondary)
            }
        }
        .accessibilityIdentifier("error")
    }
}

/// A one-line inline error under a form.
struct InlineError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.danger)
                .accessibilityIdentifier("inlineError")
        }
    }
}

/// Banner shown while the parent's email is unverified.
struct VerifyEmailBanner: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?

    var body: some View {
        if let user = model.user, !user.isEmailVerified {
            EGuardCard {
                Label("Verify your email", systemImage: "envelope.badge.fill")
                    .font(EGuardTypography.headline)
                    .foregroundStyle(EGuardColors.warning)
                Text(message ?? "We sent a link to \(user.email). Verify it before pairing a child's device.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
                Button("Resend link") {
                    Task {
                        do {
                            let result = try await model.api.resendVerification()
                            message = result.sent ? "A new link is on its way to \(result.email ?? user.email)." : "Your email is already verified."
                            await model.refreshUser()
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.eGuardSecondary)
            }
        }
    }
}

/// A child's avatar that loads the server photo with the bearer token when there is one.
struct ChildAvatar: View {
    @Environment(AppModel.self) private var model
    let child: ChildSummary
    var size: CGFloat = 56
    @State private var data: Data?

    var body: some View {
        AvatarView(name: child.name, imageData: data, size: size, tint: Color(hue: Double(child.hue) / 360, saturation: 0.7, brightness: 0.55))
            .task(id: child.photoUrl) {
                guard let url = child.photoUrl else { data = nil; return }
                data = await model.photo(for: child.id, url: url)
            }
    }
}

extension AppModel {
    /// Fetches and caches a child's photo bytes, keyed by the versioned URL.
    func photo(for childId: String, url: String) async -> Data? {
        if let cached = photoCache[url] { return cached }
        guard let data = try? await api.photo(childId: childId, url: url) else { return nil }
        photoCache[url] = data
        return data
    }
}
