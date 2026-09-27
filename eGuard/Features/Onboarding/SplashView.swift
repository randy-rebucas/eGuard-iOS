import SwiftUI

/// 00 Splash. Shown briefly at launch while the model loads.
struct SplashView: View {
    @State private var isVisible = false

    var body: some View {
        ZStack {
            // The brand artwork: a soft sky-blue wash with white arcs in the lower right.
            Image("SplashBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            EGuardSplashLogo()
                .scaleEffect(isVisible ? 1 : 0.85)
                .opacity(isVisible ? 1 : 0)
        }
        .background(EGuardColors.heroGradient.ignoresSafeArea())
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
