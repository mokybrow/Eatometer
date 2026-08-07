import AuthenticationServices
import UIKit

final class AuthenticationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding, ASAuthorizationControllerPresentationContextProviding {
    static let shared = AuthenticationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        keyWindowAnchor
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        keyWindowAnchor
    }

    private var keyWindowAnchor: ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let keyWindow = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        if let firstScene = scenes.first {
            return UIWindow(windowScene: firstScene)
        }

        fatalError("No UIWindowScene found to present authentication session.")
    }
}
