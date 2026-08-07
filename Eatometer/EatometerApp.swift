import SwiftUI
import CoreHaptics
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
    @State private var hasPlayedLaunchHaptics = false
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
                .onAppear {
                    playLaunchHapticsIfNeeded()
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

    private func playLaunchHapticsIfNeeded() {
        guard !hasPlayedLaunchHaptics else { return }
        hasPlayedLaunchHaptics = true
        AppLaunchHaptics.shared.playIfEnabled(appSettings.launchHapticsEnabled)
    }
}

@MainActor
private final class AppLaunchHaptics {
    static let shared = AppLaunchHaptics()

    private var engine: CHHapticEngine?

    private init() {}

    func playIfEnabled(_ isEnabled: Bool) {
        guard isEnabled else { return }

        Task {
            await playHeartbeatPattern()
        }
    }

    private func playHeartbeatPattern() async {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            await playFallbackHeartbeatPattern()
            return
        }

        do {
            let engine = try prepareEngine()
            let pattern = try CHHapticPattern(events: heartbeatEvents, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            await playFallbackHeartbeatPattern()
        }
    }

    private func prepareEngine() throws -> CHHapticEngine {
        if engine == nil {
            let newEngine = try CHHapticEngine()
            newEngine.isAutoShutdownEnabled = true
            newEngine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.engine = nil
                }
            }
            newEngine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.engine = nil
                }
            }
            engine = newEngine
        }

        let engine = engine!
        try engine.start()
        return engine
    }

    private var heartbeatEvents: [CHHapticEvent] {
        [
            transientEvent(intensity: 0.96, sharpness: 0.30, at: 0.00),
            transientEvent(intensity: 0.82, sharpness: 0.18, at: 0.26),
        ]
    }

    private func transientEvent(intensity: Float, sharpness: Float, at relativeTime: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: relativeTime
        )
    }

    private func playFallbackHeartbeatPattern() async {
        let medium = UIImpactFeedbackGenerator(style: .medium)
        let soft = UIImpactFeedbackGenerator(style: .soft)

        medium.prepare()
        medium.impactOccurred(intensity: 1.00)
        try? await Task.sleep(nanoseconds: 260_000_000)

        soft.prepare()
        soft.impactOccurred(intensity: 0.86)
    }
}
