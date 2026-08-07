import Foundation
@preconcurrency import UserNotifications
import Combine
import UIKit

struct AppNotificationInboxItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    let newsText: String?
    let receivedAt: Date
    let notificationType: String?
    let deepLink: String?
    let targetScreen: String?
    let habitID: String?
    let mealID: String?
    let mealSlotID: String?
    var isRead: Bool

    var hasNavigationTarget: Bool {
        destinationURL != nil
    }

    var destinationURL: URL? {
        let type = notificationType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let screen = targetScreen?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if type == "water_log_reminder" || screen == "today" {
            return URL(string: "eatometer://water")
        }

        if let url = enrichedDeepLinkURL() {
            return url
        }

        switch screen {
        case "diary":
            return diaryDestinationURL
        case "water":
            return URL(string: "eatometer://water")
        case "habits", "habit":
            return habitsDestinationURL
        default:
            return nil
        }
    }

    private var diaryDestinationURL: URL? {
        var components = URLComponents(string: "eatometer://diary")
        var queryItems: [URLQueryItem] = []

        if let mealID,
           !mealID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "meal_id", value: mealID))
        }

        if let mealSlotID,
           !mealSlotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "meal_slot_id", value: mealSlotID))
        }

        if !queryItems.contains(where: { $0.name == "open" }) {
            queryItems.append(URLQueryItem(name: "open", value: "meals"))
        }

        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url
    }

    private var habitsDestinationURL: URL? {
        var components = URLComponents(string: "eatometer://habits")
        if let habitID,
           !habitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components?.queryItems = [URLQueryItem(name: "habit_id", value: habitID)]
        }
        return components?.url
    }

    private func enrichedDeepLinkURL() -> URL? {
        guard let deepLink,
              !deepLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: deepLink) else {
            return nil
        }

        guard let habitID,
              !habitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let host = components.host?.lowercased() ?? ""
        let route = path.isEmpty ? host : path
        guard ["habit", "habits"].contains(route) else { return url }

        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "habit_id" || $0.name == "habitID" || $0.name == "habitId" }) {
            queryItems.append(URLQueryItem(name: "habit_id", value: habitID))
            components.queryItems = queryItems
        }

        return components.url ?? url
    }

    init(id: String, title: String, body: String, newsText: String?, receivedAt: Date, notificationType: String?, deepLink: String?, targetScreen: String?, habitID: String?, mealID: String?, mealSlotID: String?, isRead: Bool) {
        self.id = id
        self.title = title
        self.body = body
        self.newsText = newsText
        self.receivedAt = receivedAt
        self.notificationType = notificationType
        self.deepLink = deepLink
        self.targetScreen = targetScreen
        self.habitID = habitID
        self.mealID = mealID
        self.mealSlotID = mealSlotID
        self.isRead = isRead
    }

    init(notification: UNNotification, isRead: Bool) {
        let content = notification.request.content
        let userInfo = content.userInfo
        self.init(
            id: notification.request.identifier,
            title: content.title,
            body: content.body,
            newsText: Self.payloadString(forKeys: ["news_text", "newsText", "newsTextBody"], in: userInfo),
            receivedAt: notification.date,
            notificationType: Self.payloadString(forKeys: ["type", "notification_type", "notificationType"], in: userInfo),
            deepLink: userInfo["deep_link"] as? String,
            targetScreen: userInfo["target_screen"] as? String,
            habitID: Self.payloadString(forKeys: ["habit_id", "habitID", "habitId"], in: userInfo),
            mealID: Self.payloadString(forKeys: ["meal_id", "mealID", "mealId"], in: userInfo),
            mealSlotID: Self.payloadString(forKeys: ["meal_slot_id", "mealSlotID", "mealSlotId"], in: userInfo),
            isRead: isRead
        )
    }

    private static func payloadString(forKeys keys: [String], in userInfo: [AnyHashable: Any]) -> String? {
        for key in keys {
            if let value = userInfo[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }
}

@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var badgeSetting: UNNotificationSetting = .notSupported
    @Published private(set) var inboxItems: [AppNotificationInboxItem] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var pendingDeepLinkURL: URL?

    private struct RegisterRequest: Encodable {
        let token: String
        let environment: String
        let bundle_id: String
        let app_version: String
    }

    private struct UnregisterRequest: Encodable {
        let token: String
    }

    private let storedDeviceTokenKey = "apns_device_token"
    private let hasRequestedPermissionKey = "apns_permission_requested"
    private let inboxStorageKey = "push_notification_inbox"
    private let maxInboxItemCount = 100

    override init() {
        super.init()
        restoreInbox()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func consumePendingDeepLinkURL(_ url: URL) {
        guard pendingDeepLinkURL == url else { return }
        pendingDeepLinkURL = nil
    }

    func activate(authService: FoodAuthService) async {
        configure()

        let settings = await currentNotificationSettings()
        applyNotificationSettings(settings)
        await refreshInbox()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            registerForRemoteNotifications()
            await syncStoredTokenIfPossible(authService: authService)
        case .notDetermined:
            if !UserDefaults.standard.bool(forKey: hasRequestedPermissionKey) {
                await requestAuthorization(authService: authService)
            }
        case .denied:
            break
        @unknown default:
            break
        }
    }

    func requestAuthorization(authService: FoodAuthService) async {
        configure()
        UserDefaults.standard.set(true, forKey: hasRequestedPermissionKey)

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshNotificationSettings()
            guard granted else { return }
            registerForRemoteNotifications()
            await syncStoredTokenIfPossible(authService: authService)
        } catch {
            print("Push authorization failed: \(error)")
        }
    }

    func requestLocalAuthorizationIfNeeded() async {
        configure()
        let settings = await currentNotificationSettings()
        applyNotificationSettings(settings)
        guard settings.authorizationStatus == .notDetermined else { return }

        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshNotificationSettings()
        } catch {
            print("Local notification authorization failed: \(error)")
        }
    }

    func refreshNotificationSettings() async {
        let settings = await currentNotificationSettings()
        applyNotificationSettings(settings)
    }

    func refreshInbox() async {
        let deliveredNotifications = await currentDeliveredNotifications()
        mergeDeliveredNotifications(deliveredNotifications)
    }

    func markNotificationAsRead(id: String) {
        guard let index = inboxItems.firstIndex(where: { $0.id == id }), !inboxItems[index].isRead else {
            return
        }

        inboxItems[index].isRead = true
        finalizeInboxUpdate(removingDeliveredNotificationIDs: [id])
    }

    func markAllNotificationsAsRead() {
        let unreadIDs = inboxItems.filter { !$0.isRead }.map(\.id)
        guard !unreadIDs.isEmpty else { return }

        for index in inboxItems.indices {
            inboxItems[index].isRead = true
        }
        finalizeInboxUpdate(removingDeliveredNotificationIDs: unreadIDs)
    }

    func deleteInboxItems(atOffsets offsets: IndexSet) {
        let validOffsets = offsets.filter { inboxItems.indices.contains($0) }.sorted(by: >)
        guard !validOffsets.isEmpty else { return }

        let removedIDs = validOffsets.map { inboxItems[$0].id }
        for offset in validOffsets {
            inboxItems.remove(at: offset)
        }

        finalizeInboxUpdate(removingDeliveredNotificationIDs: removedIDs)
    }

    func deleteAllInboxItems() {
        guard !inboxItems.isEmpty else { return }

        let removedIDs = inboxItems.map(\.id)
        inboxItems.removeAll()
        finalizeInboxUpdate(removingDeliveredNotificationIDs: removedIDs)
    }

    func openInboxItem(_ item: AppNotificationInboxItem) {
        markNotificationAsRead(id: item.id)

        if let url = item.destinationURL {
            publishDeepLink(url)
        }
    }

    func didRegisterRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: storedDeviceTokenKey)

        Task { @MainActor in
            await syncStoredTokenIfPossible(authService: FoodAuthService.shared)
        }
    }

    func didFailToRegisterRemoteNotifications(error: Error) {
        print("APNS registration failed: \(error)")
    }

    func syncStoredTokenIfPossible(authService: FoodAuthService) async {
        guard authService.isAuthenticated else { return }
        guard let token = currentDeviceToken() else { return }

        do {
            try await registerToken(token: token, authService: authService)
        } catch {
            print("Push token sync failed: \(error)")
        }
    }

    func unregisterCurrentDevice(authService: FoodAuthService) async {
        guard let token = currentDeviceToken() else { return }

        do {
            try await unregisterToken(token: token, authService: authService)
        } catch {
            print("Push token unregister failed: \(error)")
        }
    }

    func clearLocalNotificationsForLogout() {
        inboxItems.removeAll()
        unreadCount = 0
        UserDefaults.standard.removeObject(forKey: inboxStorageKey)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        applyBadgeCount(0)
    }

    // MARK: - Private

    private func registerToken(token: String, authService: FoodAuthService) async throws {
        let cfg = ConfigLoader.loadOAuthConfig()
        guard let url = URL(string: "\(cfg.serverBaseURL)/push/register") else {
            throw URLError(.badURL)
        }
        guard let accessToken = authService.getAccessToken() else {
            throw URLError(.userAuthenticationRequired)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RegisterRequest(
            token: token,
            environment: pushEnvironment,
            bundle_id: Bundle.main.bundleIdentifier ?? "com.goeatometer.Eatometer",
            app_version: appVersion
        ))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func unregisterToken(token: String, authService: FoodAuthService) async throws {
        let cfg = ConfigLoader.loadOAuthConfig()
        guard let url = URL(string: "\(cfg.serverBaseURL)/push/unregister") else {
            throw URLError(.badURL)
        }
        guard let accessToken = authService.getAccessToken() else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(UnregisterRequest(token: token))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func registerForRemoteNotifications() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func currentNotificationSettings() async -> UNNotificationSettings {
        await UNUserNotificationCenter.current().notificationSettings()
    }

    private func currentDeliveredNotifications() async -> [UNNotification] {
        await UNUserNotificationCenter.current().deliveredNotifications()
    }

    private func applyNotificationSettings(_ settings: UNNotificationSettings) {
        authorizationStatus = settings.authorizationStatus
        badgeSetting = settings.badgeSetting
    }

    private func restoreInbox() {
        guard let data = UserDefaults.standard.data(forKey: inboxStorageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([AppNotificationInboxItem].self, from: data) else { return }
        inboxItems = decoded.sorted { $0.receivedAt > $1.receivedAt }
        unreadCount = inboxItems.filter { !$0.isRead }.count
        applyBadgeCount(unreadCount)
    }

    private func mergeDeliveredNotifications(_ notifications: [UNNotification]) {
        var mergedByID = Dictionary(uniqueKeysWithValues: inboxItems.map { ($0.id, $0) })
        for notification in notifications {
            let newItem = AppNotificationInboxItem(notification: notification, isRead: false)
            if let existing = mergedByID[newItem.id] {
                var updated = newItem
                updated.isRead = existing.isRead
                mergedByID[newItem.id] = updated
            } else {
                mergedByID[newItem.id] = newItem
            }
        }

        inboxItems = Array(mergedByID.values)
            .sorted { $0.receivedAt > $1.receivedAt }
        if inboxItems.count > maxInboxItemCount {
            inboxItems = Array(inboxItems.prefix(maxInboxItemCount))
        }
        finalizeInboxUpdate()
    }

    private func ingestNotification(_ notification: UNNotification, isRead: Bool) {
        let newItem = AppNotificationInboxItem(notification: notification, isRead: isRead)
        if let index = inboxItems.firstIndex(where: { $0.id == newItem.id }) {
            var existing = inboxItems[index]
            existing = AppNotificationInboxItem(
                id: newItem.id,
                title: newItem.title,
                body: newItem.body,
                newsText: newItem.newsText,
                receivedAt: newItem.receivedAt,
                notificationType: newItem.notificationType,
                deepLink: newItem.deepLink,
                targetScreen: newItem.targetScreen,
                habitID: newItem.habitID,
                mealID: newItem.mealID,
                mealSlotID: newItem.mealSlotID,
                isRead: existing.isRead || isRead
            )
            inboxItems[index] = existing
        } else {
            inboxItems.insert(newItem, at: 0)
        }

        inboxItems.sort { $0.receivedAt > $1.receivedAt }
        if inboxItems.count > maxInboxItemCount {
            inboxItems = Array(inboxItems.prefix(maxInboxItemCount))
        }
        finalizeInboxUpdate(removingDeliveredNotificationIDs: isRead ? [newItem.id] : [])
    }

    private func publishDeepLink(_ url: URL) {
        pendingDeepLinkURL = url
        NotificationCenter.default.post(name: .pushNotificationDeepLink, object: url)
    }

    private func finalizeInboxUpdate(removingDeliveredNotificationIDs ids: [String] = []) {
        unreadCount = inboxItems.filter { !$0.isRead }.count
        if let data = try? JSONEncoder().encode(inboxItems) {
            UserDefaults.standard.set(data, forKey: inboxStorageKey)
        }

        if !ids.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }

        applyBadgeCount(unreadCount)
    }

    private func applyBadgeCount(_ count: Int) {
        let safeCount = max(0, count)
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(safeCount) { error in
                if let error {
                    print("Failed to set badge count: \(error)")
                }
            }
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = safeCount
            }
        }
    }

    private func currentDeviceToken() -> String? {
        UserDefaults.standard.string(forKey: storedDeviceTokenKey)
    }

    private var pushEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return shortVersion.isEmpty ? build : "\(shortVersion) (\(build))"
    }
}

extension PushNotificationService: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        ingestNotification(notification, isRead: false)
        return [.banner, .badge, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        ingestNotification(response.notification, isRead: true)
        let item = AppNotificationInboxItem(notification: response.notification, isRead: true)
        if let url = item.destinationURL {
            publishDeepLink(url)
        }
    }
}

extension Notification.Name {
    static let pushNotificationDeepLink = Notification.Name("pushNotificationDeepLink")
}
