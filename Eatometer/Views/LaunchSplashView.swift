import SwiftUI

/// Brief in-app splash shown on cold start. The system launch screen is static
/// and can't reflect runtime state, so this overlay displays the app icon the
/// user actually selected (Lemon / Orange / Egg) while the session bootstraps,
/// then fades into the app.
struct LaunchSplashView: View {
    private let icon = AppIconOption.current

    /// The icon, still and centred.
    ///
    /// It used to spring in from 86% and fade up. The screen is on for under a
    /// second and exists to cover a cold start, so an entrance animation only
    /// competes with the app arriving behind it — and on a warm launch it played
    /// over content that was already ready.
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
        }
    }
}
