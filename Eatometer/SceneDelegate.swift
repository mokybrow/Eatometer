import UIKit

/// Where Home-screen quick actions actually arrive.
///
/// They were being waited for in `AppDelegate`, and neither hook there is ever
/// called by an app that uses scenes — which every SwiftUI app does.
/// `application(_:performActionFor:)` is the pre-scene delivery point, and the
/// `shortcutItem` on `UIScene.ConnectionOptions` reaches the *scene* delegate,
/// not the application one. So "Add water" and "New recipe" were dispatched
/// into a handler nothing would ever call, and tapping either did nothing at
/// all — no error, no screen, no trace.
///
/// SwiftUI does not install a scene delegate of its own, so this is attached
/// through `UISceneConfiguration.delegateClass` in `AppDelegate`.
@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// A cold launch: the app was not running, and the action came in with the
    /// scene itself.
    ///
    /// Published rather than held: `DeepLinkRouter` keeps it until the app is
    /// far enough along to act on it, which on a cold start is well after this.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let shortcutItem = connectionOptions.shortcutItem,
              let action = AppShortcutAction(rawValue: shortcutItem.type) else { return }
        DeepLinkRouter.shared.pendingShortcutAction = action
    }

    /// A warm launch: the app was already running when the action was chosen.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let action = AppShortcutAction(rawValue: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        DeepLinkRouter.shared.pendingShortcutAction = action
        completionHandler(true)
    }
}
