import SwiftUI

/// 00 Splash. Shown briefly at launch while the model loads.
struct SplashView: View {
    @State private var isVisible = false

    var body: some View {
        ZStack {
            EGuardColors.heroGradient
                .ignoresSafeArea()

            // Soft concentric arcs echo the mockup's background.
            Circle()
                .stroke(EGuardColors.primary.opacity(0.08), lineWidth: 60)
                .frame(width: 520, height: 520)
                .offset(x: -180, y: 320)
            Circle()
                .stroke(EGuardColors.primary.opacity(0.06), lineWidth: 40)
                .frame(width: 420, height: 420)
                .offset(x: 200, y: -300)

            EGuardSplashLogo()
                .scaleEffect(isVisible ? 1 : 0.85)
                .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.25)) {
                isVisible = true
            }
        }
        .accessibilityIdentifier("splash")
    }
}

#Preview {
    SplashView()
}
