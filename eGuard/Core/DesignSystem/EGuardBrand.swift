import SwiftUI

/// The eGuard mark: a blue shield with a faceted hexagon inside.
struct EGuardLogoMark: View {
    var size: CGFloat = 64
    var tint: Color = EGuardColors.primary

    var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(tint)
            Image(systemName: "shield.fill")
                .font(.system(size: size * 0.78, weight: .regular))
                .foregroundStyle(.white)
                .offset(y: -size * 0.01)
            Image(systemName: "hexagon.fill")
                .font(.system(size: size * 0.38, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: 0x6FA3FF), tint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .offset(y: -size * 0.03)
        }
        .frame(width: size, height: size * 1.1)
        .accessibilityHidden(true)
    }
}

/// The mark followed by the "eGuard" wordmark. Used in navigation bars and headers.
struct EGuardWordmark: View {
    var markSize: CGFloat = 26
    var showsTagline = false

    var body: some View {
        HStack(spacing: EGuardSpacing.xs) {
            EGuardLogoMark(size: markSize)
            VStack(alignment: .leading, spacing: 0) {
                Text("eGuard")
                    .font(.system(size: markSize * 0.8, weight: .bold, design: .rounded))
                    .foregroundStyle(EGuardColors.primary)
                if showsTagline {
                    Text("Digital Safety for Brighter Tomorrows")
                        .font(.system(size: max(markSize * 0.28, 8), weight: .medium))
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("eGuard")
    }
}

/// Large stacked logo used on the splash screen.
struct EGuardSplashLogo: View {
    var body: some View {
        VStack(spacing: EGuardSpacing.sm) {
            EGuardLogoMark(size: 110)
            Text("eGuard")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(EGuardColors.primary)
            Text("Digital Safety\nfor Brighter Tomorrows")
                .font(EGuardTypography.label)
                .foregroundStyle(EGuardColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("eGuard. Digital Safety for Brighter Tomorrows.")
    }
}

/// Decorative family illustration used where the mockup shows a photo.
/// A gradient card with people symbols stands in for artwork the project does not ship.
struct FamilyIllustration: View {
    var height: CGFloat = 220

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: EGuardShapes.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xBFD6FF), Color(hex: 0xE3EEFF)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(.white.opacity(0.45))
                .frame(width: height * 0.9)
                .offset(x: height * 0.35, y: height * 0.3)
            HStack(alignment: .bottom, spacing: -height * 0.08) {
                Image(systemName: "figure.stand")
                    .font(.system(size: height * 0.42))
                Image(systemName: "figure.and.child.holdinghands")
                    .font(.system(size: height * 0.5))
                Image(systemName: "figure.stand.dress")
                    .font(.system(size: height * 0.4))
            }
            .foregroundStyle(EGuardColors.primary.opacity(0.85))
            .offset(y: height * 0.08)
            Image(systemName: "ipad.landscape")
                .font(.system(size: height * 0.16, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: height * 0.1, y: height * 0.3)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: EGuardShapes.cardRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Sets the eGuard mark as the navigation bar title, as on every onboarding screen.
struct BrandNavigationTitle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    EGuardWordmark(markSize: 22)
                }
            }
    }
}

extension View {
    func brandNavigationTitle() -> some View {
        modifier(BrandNavigationTitle())
    }
}

#Preview {
    VStack(spacing: 32) {
        EGuardSplashLogo()
        EGuardWordmark(markSize: 32, showsTagline: true)
        FamilyIllustration()
            .padding()
    }
}
