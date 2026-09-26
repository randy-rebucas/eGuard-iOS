import SwiftUI

// MARK: - Cards

/// The eGuard card used for every feature, summary, and status block.
struct EGuardCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EGuardSpacing.md)
        .background(EGuardColors.surface, in: EGuardShapes.card)
    }
}

// MARK: - Buttons

struct EGuardPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // A nested view is needed so the environment is installed before `isEnabled` is read.
        PrimaryButtonBody(configuration: configuration)
    }

    private struct PrimaryButtonBody: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .font(EGuardTypography.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .background(
                    (configuration.isPressed ? EGuardColors.primaryPressed : EGuardColors.primary)
                        .opacity(isEnabled ? 1 : 0.4),
                    in: EGuardShapes.button
                )
                .contentShape(EGuardShapes.button)
        }
    }
}

struct EGuardSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EGuardTypography.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(EGuardColors.primary)
            .background(
                EGuardColors.primarySoft.opacity(configuration.isPressed ? 0.6 : 1),
                in: EGuardShapes.button
            )
            .contentShape(EGuardShapes.button)
    }
}

struct EGuardTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EGuardTypography.label)
            .foregroundStyle(EGuardColors.primary.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(minHeight: 44)
    }
}

extension ButtonStyle where Self == EGuardPrimaryButtonStyle {
    static var eGuardPrimary: EGuardPrimaryButtonStyle { EGuardPrimaryButtonStyle() }
}

extension ButtonStyle where Self == EGuardSecondaryButtonStyle {
    static var eGuardSecondary: EGuardSecondaryButtonStyle { EGuardSecondaryButtonStyle() }
}

extension ButtonStyle where Self == EGuardTextButtonStyle {
    static var eGuardText: EGuardTextButtonStyle { EGuardTextButtonStyle() }
}

// MARK: - Status

/// A colored dot followed by a label, e.g. "● Protected".
struct StatusIndicator: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: EGuardSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(text)
                .font(EGuardTypography.label)
                .foregroundStyle(EGuardColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct HealthStatusBadge: View {
    let status: HealthStatus

    var body: some View {
        Label(status.title, systemImage: EGuardTheme.symbol(for: status))
            .font(EGuardTypography.overline)
            .foregroundStyle(EGuardTheme.color(for: status))
            .padding(.horizontal, EGuardSpacing.xs)
            .padding(.vertical, EGuardSpacing.xxs)
            .background(
                EGuardTheme.color(for: status).opacity(0.12),
                in: RoundedRectangle(cornerRadius: EGuardShapes.chipRadius, style: .continuous)
            )
    }
}

struct ModeBadge: View {
    let mode: ConfigurationMode

    var body: some View {
        Text(mode.title)
            .font(EGuardTypography.overline)
            .foregroundStyle(EGuardTheme.color(for: mode))
            .padding(.horizontal, EGuardSpacing.xs)
            .padding(.vertical, EGuardSpacing.xxs)
            .background(
                EGuardTheme.color(for: mode).opacity(0.12),
                in: RoundedRectangle(cornerRadius: EGuardShapes.chipRadius, style: .continuous)
            )
    }
}

// MARK: - Layout helpers

/// Step indicator shown on every onboarding screen: "Step 2 of 7" plus segment bars.
struct OnboardingProgressIndicator: View {
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.xs) {
            Text("Step \(step.rawValue) of \(OnboardingStep.count)")
                .font(EGuardTypography.overline)
                .foregroundStyle(EGuardColors.textSecondary)
            HStack(spacing: EGuardSpacing.xxs) {
                ForEach(OnboardingStep.allCases) { candidate in
                    Capsule()
                        .fill(candidate.rawValue <= step.rawValue ? EGuardColors.primary : EGuardColors.divider)
                        .frame(height: 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue) of \(OnboardingStep.count), \(step.title)")
        .accessibilityIdentifier("onboarding.progress.\(step.rawValue)")
    }
}

/// Screen title block with the shared information hierarchy.
struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.xs) {
            Text(title)
                .font(EGuardTypography.display)
                .foregroundStyle(EGuardColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(EGuardTypography.body)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A large SF Symbol in a tinted circle, used as the shared illustration style.
struct EGuardIllustration: View {
    let symbolName: String
    var tint: Color = EGuardColors.primary
    var size: CGFloat = 96

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A radio-style option row used for profiles and other single choices.
struct SelectableOptionRow: View {
    let title: String
    let subtitle: String
    var symbolName: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: EGuardSpacing.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? EGuardColors.primary : EGuardColors.neutral)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: EGuardSpacing.xxs) {
                    HStack(spacing: EGuardSpacing.xs) {
                        if let symbolName {
                            Image(systemName: symbolName)
                                .foregroundStyle(EGuardColors.primary)
                        }
                        Text(title)
                            .font(EGuardTypography.headline)
                            .foregroundStyle(EGuardColors.textPrimary)
                    }
                    Text(subtitle)
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(EGuardSpacing.md)
            .background(EGuardColors.surface, in: EGuardShapes.card)
            .overlay(
                EGuardShapes.card.strokeBorder(isSelected ? EGuardColors.primary : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Label on the left, value on the right.
struct EGuardValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(EGuardTypography.body)
                .foregroundStyle(EGuardColors.textSecondary)
            Spacer()
            Text(value)
                .font(EGuardTypography.label)
                .foregroundStyle(EGuardColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Scrollable content with actions pinned above the home indicator.
struct EGuardScreen<Content: View, Actions: View>: View {
    private let content: Content
    private let actions: Actions

    init(@ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
                content
            }
            .padding(.horizontal, EGuardSpacing.md)
            .padding(.top, EGuardSpacing.md)
            .padding(.bottom, EGuardSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(EGuardColors.background)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: EGuardSpacing.xs) {
                actions
            }
            .padding(.horizontal, EGuardSpacing.md)
            .padding(.vertical, EGuardSpacing.sm)
            .background(.bar)
        }
    }
}

/// Banner shown while offline so stored information is never presented as live.
struct OfflineBanner: View {
    let lastVerified: Date?

    var body: some View {
        HStack(spacing: EGuardSpacing.xs) {
            Image(systemName: "wifi.slash")
            VStack(alignment: .leading, spacing: 2) {
                Text("You're offline")
                    .font(EGuardTypography.label)
                Text(lastVerified.map { "Showing results from \($0.verifiedDescription())." }
                    ?? "Showing saved information.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EGuardSpacing.sm)
        .background(EGuardColors.warning.opacity(0.15), in: EGuardShapes.card)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline.banner")
    }
}
