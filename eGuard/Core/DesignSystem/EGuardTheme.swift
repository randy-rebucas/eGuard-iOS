import SwiftUI

/// Brand colors. The raw values are the design tokens shared with Android.
enum EGuardColors {
    static let primary = Color(hex: 0x2F6FED)
    static let primaryPressed = Color(hex: 0x255ACB)
    static let primarySoft = Color(hex: 0x2F6FED).opacity(0.12)
    static let primaryLight = Color(hex: 0xDCE8FF)
    static let accent = Color(hex: 0x14B8A6)
    static let success = Color(hex: 0x2E9E5B)
    static let warning = Color(hex: 0xE0A100)
    static let danger = Color(hex: 0xD64545)
    static let neutral = Color(hex: 0x8A94A6)

    /// Tints used for the rounded icon tiles that lead every list row.
    static let tilePurple = Color(hex: 0x7C5CE6)
    static let tileOrange = Color(hex: 0xF08A24)
    static let tilePink = Color(hex: 0xE2508A)
    static let tileTeal = Color(hex: 0x14B8A6)
    static let tileYellow = Color(hex: 0xE0A100)
    static let tileGray = Color(hex: 0x6B7280)

    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let surfaceRaised = Color(.tertiarySystemGroupedBackground)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let divider = Color(.separator)

    /// The soft sky-blue wash behind the splash, welcome, and dashboard headers.
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xEAF2FF), Color(hex: 0xF7FAFF), Color(.systemGroupedBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x4C8DFF), Color(hex: 0x2F6FED)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Text styles. All of them scale with Dynamic Type.
enum EGuardTypography {
    static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let screenTitle = Font.system(.title2, design: .rounded, weight: .bold)
    static let title = Font.system(.title2, design: .rounded, weight: .semibold)
    static let title3 = Font.system(.title3, design: .rounded, weight: .semibold)
    static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout)
    static let label = Font.system(.subheadline, weight: .medium)
    static let caption = Font.system(.caption)
    static let overline = Font.system(.caption, weight: .semibold)
    static let metric = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let brand = Font.system(.title, design: .rounded, weight: .bold)
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
    static let tileRadius: CGFloat = 10

    static var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    }

    static var button: RoundedRectangle {
        RoundedRectangle(cornerRadius: buttonRadius, style: .continuous)
    }

    static var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
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
        case .notConfigured: EGuardColors.warning
        }
    }

    static func symbol(for status: HealthStatus) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .actionRequired: "exclamationmark.circle.fill"
        case .unsupported: "minus.circle.fill"
        case .notConfigured: "exclamationmark.circle.fill"
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

    /// The tile tint used for a protection feature throughout the app.
    static func tint(for feature: ProtectionFeature) -> Color {
        switch feature {
        case .downtime: EGuardColors.tilePurple
        case .gaming: EGuardColors.tileOrange
        case .socialApps: EGuardColors.tilePink
        case .webContent: EGuardColors.danger
        case .appInstallation: EGuardColors.primary
        case .appRestrictions: EGuardColors.tileTeal
        case .purchases: EGuardColors.tileYellow
        case .explicitContent: EGuardColors.danger
        case .deviceActivity: EGuardColors.primary
        case .screenTimePasscode: EGuardColors.tileGray
        }
    }

    static func tint(for profile: ProtectionProfile) -> Color {
        switch profile {
        case .balanced: EGuardColors.tileYellow
        case .protected: EGuardColors.success
        case .custom: EGuardColors.tileGray
        }
    }

    /// Plain-language grade for a health score, e.g. "Good Protection".
    static func grade(passed: Int, total: Int) -> String {
        guard total > 0 else { return "Not configured" }
        let ratio = Double(passed) / Double(total)
        if ratio >= 1 { return "Full Protection" }
        if ratio >= 0.7 { return "Good Protection" }
        if ratio >= 0.4 { return "Partial Protection" }
        return "Needs Attention"
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
