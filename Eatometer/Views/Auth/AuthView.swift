import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @Environment(\.colorScheme) private var colorScheme
    @State private var appleNonce = ""

    private var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? "Eatometer"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                // The icon the reader actually chose, not a fixed asset.
                //
                // "LaunchAppIcon" named nothing — no such imageset has ever
                // been in the catalog — so this drew an empty box and logged a
                // miss on every launch. The icon is switchable, so a hard-coded
                // one would have been wrong even if it had existed:
                // `AppIconOption.current` is what `LaunchSplashView` and the
                // share card already use.
                Image(AppIconOption.current.previewImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .shadow(color: .black.opacity(0.09), radius: 18, y: 9)

                Text("auth.have_a_nice_day")
                    .font(EOTheme.Typography.screenTitle)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                appleSignInButton

                if authService.isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                }

                if let message = authService.authenticationError {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                legalText
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, EOTheme.Metrics.screenInset)
        .padding(.vertical, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .eoPageBackground()
        .tint(.appAccent)
    }

    /// Apple's own button, drawn by Apple.
    ///
    /// It used to be a custom white capsule — label on the left, Apple glyph and
    /// a chevron on the right — with the real `SignInWithAppleButton` hidden
    /// underneath in `.destinationOver` blend mode purely to catch the tap.
    ///
    /// That is not a styling preference. Sign in with Apple is one of the few
    /// controls whose appearance Apple specifies rather than suggests: the
    /// title, the mark, its proportions and the spacing around it are fixed,
    /// and an app that redraws them is rejected under App Review 4.8. The
    /// native button also localises its own title, sizes its glyph for
    /// Dynamic Type, and renders correctly under increased contrast — three
    /// things the replica did not do.
    private var appleSignInButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
            guard let nonce = FoodAuthService.makeAppleNonce() else {
                authService.authenticationError = NSLocalizedString("auth.apple.nonce_error", comment: "Could not create Apple nonce")
                return
            }
            appleNonce = nonce
            request.nonce = FoodAuthService.appleNonceHash(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    authService.authenticationError = NSLocalizedString(
                        "auth.apple.invalid_response",
                        comment: "Apple ID response could not be read"
                    )
                    return
                }
                authService.loginWithAppleNative(credential: credential, nonce: appleNonce)
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    authService.authenticationError = error.localizedDescription
                }
            }
        }
        // Black on light, white on dark: the pairing Apple documents, and the
        // one that keeps the mark legible against this screen's background.
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        // 50 is Apple's recommended height; the replica's 64 stretched the
        // artwork it was standing in for.
        .frame(height: 50)
        // Corner radius by clipping, because SwiftUI exposes no modifier for
        // it — `cornerRadius` belongs to the UIKit button and is not bridged.
        // Only the corners are affected: the button paints its own background
        // out to the edges, and the mark keeps the clear space around it.
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .disabled(authService.isSigningIn)
        .opacity(authService.isSigningIn ? 0.6 : 1)
    }

    private var legalText: some View {
        let markdown = LegalContent.markdown(for: .auth)
        let attributed = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        return Text(attributed)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, EOTheme.Metrics.cardInset)
    }
}

#Preview {
    AuthView()
        .environmentObject(FoodAuthService.shared)
}
