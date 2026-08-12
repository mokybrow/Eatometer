import SwiftUI
import UIKit

@main
struct EatometerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appSettings: AppSettings
    @StateObject private var authService: FoodAuthService
    @StateObject private var userService: UserService
    @StateObject private var diaryService: FoodDiaryService
    @StateObject private var catalogService: FoodCatalogService
    @StateObject private var habitsService: HabitsService
    @StateObject private var deepLinkRouter: DeepLinkRouter
    @StateObject private var supporterService: SupporterService
    @State private var isBooting = true

    init() {
        Self.configureSystemAlertAppearance()

        let settings = AppSettings.shared
        let auth = FoodAuthService.shared
        let catalog = FoodCatalogService(authService: auth)
        let diary = FoodDiaryService(authService: auth, catalogService: catalog)
        let habits = HabitsService(authService: auth)
        let deepLinkRouter = DeepLinkRouter()
        let user = UserService(authService: auth)
        _appSettings = StateObject(wrappedValue: settings)
        _authService = StateObject(wrappedValue: auth)
        _userService = StateObject(wrappedValue: user)
        _catalogService = StateObject(wrappedValue: catalog)
        _diaryService = StateObject(wrappedValue: diary)
        _habitsService = StateObject(wrappedValue: habits)
        _deepLinkRouter = StateObject(wrappedValue: deepLinkRouter)
        _supporterService = StateObject(wrappedValue: SupporterService(userService: user))

        PushNotificationService.shared.configure()
        PhoneWatchConnectivityManager.shared.configure(diaryService: diary, catalogService: catalog)
    }

    private static func configureSystemAlertAppearance() {
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = .label
    }

    private var mainWindowScene: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(appSettings)
                    .environmentObject(authService)
                    .environmentObject(userService)
                    .environmentObject(diaryService)
                    .environmentObject(catalogService)
                    .environmentObject(habitsService)
                    .environmentObject(deepLinkRouter)
                    .environmentObject(supporterService)
                    .tint(.appAccent)

                if isBooting {
                    LaunchSplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
                .task {
                    let start = Date()
                    _ = await authService.bootstrapStoredSessionIfNeeded()
                    // Keep the splash up for a short minimum so it reads as
                    // intentional rather than a flash, then reveal the app.
                    let elapsed = Date().timeIntervalSince(start)
                    if elapsed < 0.8 {
                        try? await Task.sleep(nanoseconds: UInt64((0.8 - elapsed) * 1_000_000_000))
                    }
                    withAnimation(.easeOut(duration: 0.4)) {
                        isBooting = false
                    }
                    await catalogService.refreshMessagesPickerSnapshot(force: true)
                    await PushNotificationService.shared.activate(authService: authService)
                    await supporterService.bootstrap()
                }
                .onOpenURL { url in
                    deepLinkRouter.receive(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    deepLinkRouter.receive(url)
                }
        }
    }

    var body: some Scene {
        mainWindowScene
    }
}
