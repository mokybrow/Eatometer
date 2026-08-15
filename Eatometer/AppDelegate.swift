import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var launchShortcutAction: AppShortcutAction?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureShortcutItems(for: application)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        configureShortcutItems(for: application)

        if let shortcutItem = options.shortcutItem {
            launchShortcutAction = shortcutAction(from: shortcutItem)
        }

        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        configureShortcutItems(for: application)

        guard let launchShortcutAction else { return }
        DeepLinkRouter.shared.pendingShortcutAction = launchShortcutAction
        self.launchShortcutAction = nil
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        configureShortcutItems(for: application)

        guard let action = shortcutAction(from: shortcutItem) else {
            completionHandler(false)
            return
        }

        DeepLinkRouter.shared.pendingShortcutAction = action
        completionHandler(true)
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

    private func shortcutAction(from shortcutItem: UIApplicationShortcutItem) -> AppShortcutAction? {
        AppShortcutAction(rawValue: shortcutItem.type)
    }
}
