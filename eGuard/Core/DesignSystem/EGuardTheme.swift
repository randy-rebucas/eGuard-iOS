import SwiftUI

/// Brand colors. The raw values are the design tokens shared with Android.
enum EGuardColors {
    static let primary = Color(hex: 0x2F6FED)
    static let primaryPressed = Color(hex: 0x255ACB)
    static let primarySoft = Color(hex: 0x2F6FED).opacity(0.12)
    static let accent = Color(hex: 0x14B8A6)
    static let success = Color(hex: 0x2E9E5B)
    static let warning = Color(hex: 0xE0A100)
    static let danger = Color(hex: 0xD64545)
    static let neutral = Color(hex: 0x8A94A6)

    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let surfaceRaised = Color(.tertiarySystemGroupedBackground)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let divider = Color(.separator)
}

/// Text styles. All of them scale with Dynamic Type.
enum EGuardTypography {
    static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let title = Font.system(.title2, design: .rounded, weight: .semibold)
    static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout)
    static let label = Font.system(.subheadline, weight: .medium)
    static let caption = Font.system(.caption)
    static let overline = Font.system(.caption, weight: .semibold)
    static let metric = Font.system(.largeTitle, design: .rounded, weight: .bold)
}

/// Spacing scale in points.
enum EGuardSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

/// Corner radii and shapes.
enum EGuardShapes {
    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 12
    static let chipRadius: CGFloat = 8

    static var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    }

    static var button: RoundedRectangle {
        RoundedRectangle(cornerRadius: buttonRadius, style: .continuous)
    }
}

/// Semantic mappings used across screens.
enum EGuardTheme {
    static func color(for status: HealthStatus) -> Color {
        switch status {
        case .pass: EGuardColors.success
        case .warning: EGuardColors.warning
        case .actionRequired: EGuardColors.danger
        case .unsupported: EGuardColors.neutral
        case .notConfigured: EGuardColors.neutral
        }
    }

    static func symbol(for status: HealthStatus) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .actionRequired: "exclamationmark.circle.fill"
        case .unsupported: "minus.circle.fill"
        case .notConfigured: "circle.dashed"
        }
    }

    static func color(for state: ProtectionState) -> Color {
        switch state {
        case .active: EGuardColors.success
        case .needsAttention: EGuardColors.warning
        case .notConfigured: EGuardColors.neutral
        }
    }

    static func color(for state: FeatureConfigurationState) -> Color {
        switch state {
        case .configured, .confirmedByParent: EGuardColors.success
        case .awaitingReturn: EGuardColors.warning
        case .failed: EGuardColors.danger
        case .notConfigured: EGuardColors.primary
        case .skipped: EGuardColors.neutral
        }
    }

    static func color(for mode: ConfigurationMode) -> Color {
        switch mode {
        case .automatic: EGuardColors.primary
        case .guided: EGuardColors.accent
        case .verificationOnly: EGuardColors.warning
        case .unsupported: EGuardColors.neutral
        }
    }
}

extension Color {
    /// Creates an opaque color from a 24-bit hex token such as `0x2F6FED`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
