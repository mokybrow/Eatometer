import SwiftUI

/// Brief in-app splash shown on cold start. The system launch screen is static
/// and can't reflect runtime state, so this overlay displays the app icon the
/// user actually selected (Lemon / Orange / Egg) while the session bootstraps,
/// then fades into the app.
struct LaunchSplashView: View {
    private let icon = AppIconOption.current
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.appPageBackground
                .ignoresSafeArea()

            Image(icon.previewImageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: 12)
                .scaleEffect(appeared ? 1 : 0.86)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.74)) {
                appeared = true
            }
        }
    }
}
