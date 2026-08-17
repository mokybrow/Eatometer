import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureShortcutItems(for: application)
        return true
    }

    /// Attaches a scene delegate, which SwiftUI does not provide.
    ///
    /// This is the only reason the method is here. Quick actions are delivered
    /// to `UIWindowSceneDelegate`, and without a class named here there is no
    /// such delegate for the system to deliver them to.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        configureShortcutItems(for: application)

        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        configureShortcutItems(for: application)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushNotificationService.shared.didRegisterRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushNotificationService.shared.didFailToRegisterRemoteNotifications(error: error)
        }
    }

    private func configureShortcutItems(for application: UIApplication) {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: AppShortcutAction.addWater.rawValue,
                localizedTitle: NSLocalizedString("water.add_title", comment: "Quick action for adding water"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "drop.fill")
            ),
            UIApplicationShortcutItem(
                type: AppShortcutAction.newRecipe.rawValue,
                localizedTitle: NSLocalizedString("recipe.editor.new", comment: "Quick action for new recipe"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "book.closed")
            ),
        ]
    }
}
