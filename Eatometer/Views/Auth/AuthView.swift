import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @Environment(\.colorScheme) private var colorScheme

    private var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? "Eatometer"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Image("LaunchAppIcon")
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

    /// Custom-styled Apple button: the mock-up asks for a white capsule with
    /// the label on the left and the Apple glyph + chevron on the right, while
    /// the real `SignInWithAppleButton` stays underneath to keep native
    /// behaviour (it is drawn behind via `.destinationOver`, but still hit-tests).
    private var appleSignInButton: some View {
        ZStack {
            appleButtonLabel

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
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
                    authService.loginWithAppleNative(credential: credential)
                case .failure(let error):
                    if (error as? ASAuthorizationError)?.code != .canceled {
                        authService.authenticationError = error.localizedDescription
                    }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .whiteOutline)
            .blendMode(.destinationOver)
        }
        .frame(height: 64)
        .clipShape(Capsule(style: .continuous))
        .disabled(authService.isSigningIn)
        .opacity(authService.isSigningIn ? 0.6 : 1)
    }

    private var appleButtonLabel: some View {
        HStack(spacing: 12) {
            Text("auth.continue_with_apple")
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "apple.logo")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.primary)

            EOChevron()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EOTheme.Palette.card, in: Capsule(style: .continuous))
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
