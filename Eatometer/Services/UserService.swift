import Combine
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import SwiftProtobuf

struct EatometerFriendProfile: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let avatarEmoji: String
    let avatarMonogramStyle: String
    let avatarBackgroundStyle: String
    let caloriesToday: Int
    let waterTrackingEnabled: Bool
    let waterTodayMilliliters: Int
    let waterGoalMilliliters: Int
    let foodLoggingStreakDays: Int
    let mealsLoggedToday: Int

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Пользователь" : trimmed
    }

    // UI aliases for old friend cards while their layout is retained.
    var username: String { displayName }
    var firstName: String { displayName }
    var lastName: String { "" }

    var avatarSource: String {
        displayName
    }

    var appearance: ProfileAppearance {
        ProfileAppearance(
            emoji: avatarEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : avatarEmoji,
            monogramStyle: ProfileAppearance.MonogramStyle(rawValue: avatarMonogramStyle) ?? .classic,
            backgroundStyle: ProfileAppearance.BackgroundStyle(rawValue: avatarBackgroundStyle) ?? .cyan
        )
    }

    init(proto: User_FriendProfile) {
        id = proto.userID
        name = proto.name
        avatarEmoji = proto.avatarEmoji
        avatarMonogramStyle = proto.avatarMonogramStyle
        avatarBackgroundStyle = proto.avatarBackgroundStyle
        caloriesToday = Int(proto.caloriesToday)
        waterTrackingEnabled = proto.waterTrackingEnabled
        waterTodayMilliliters = Int(proto.waterTodayMilliliters)
        waterGoalMilliliters = Int(proto.waterGoalMilliliters)
        foodLoggingStreakDays = Int(proto.foodLoggingStreakDays)
        mealsLoggedToday = Int(proto.mealsLoggedToday)
    }
}

extension User_User {
    /// Transitional view aliases; persisted/public identity remains name + email only.
    var username: String { name }
    var firstName: String { name }
    var lastName: String { "" }
}

struct EatometerFriendship: Identifiable, Hashable {
    let id: String
    let profile: EatometerFriendProfile
    let status: User_FriendshipStatus
    let direction: User_FriendshipDirection
    let requestedByUserID: String
    let requestedAt: Date?
    let respondedAt: Date?

    init(proto: User_Friendship) {
        profile = EatometerFriendProfile(proto: proto.profile)
        id = profile.id
        status = proto.status
        direction = proto.direction
        requestedByUserID = proto.requestedByUserID
        requestedAt = proto.hasRequestedAt ? proto.requestedAt.date : nil
        respondedAt = proto.hasRespondedAt ? proto.respondedAt.date : nil
    }
}

/// A snapshotted friend activity event, persisted locally so the events feed
/// accumulates history instead of resetting when daily metrics roll over.
/// `kind` is a stable key ("meals", "calories", "water", "waterGoal", "streak").
struct StoredFriendEvent: Identifiable, Codable, Hashable {
    let id: String
    let profile: EatometerFriendProfile
    let kind: String
    let value: Int
    let recordedAt: Date
}

@MainActor
final class UserService: ObservableObject {
    @Published var currentUser: User_User?
    @Published var currentUserID: String?
    @Published var profileAppearance: ProfileAppearance = .default
    @Published var showProfile: Bool = false
    @Published private(set) var friends: [EatometerFriendship] = []
    @Published private(set) var incomingFriendRequests: [EatometerFriendship] = []
    @Published private(set) var outgoingFriendRequests: [EatometerFriendship] = []
    @Published private(set) var declinedFriendRequests: [EatometerFriendship] = []
    @Published private(set) var friendSearchResults: [EatometerFriendProfile] = []
    @Published private(set) var isLoadingFriendships = false
    @Published private(set) var friendsErrorMessage: String?
    /// Persisted, accumulating history of friend activity events. Unlike the
    /// live friend metrics (which reset each day), these are snapshotted per
    /// friend/kind/day and kept so the events feed builds up over time.
    @Published private(set) var friendActivityEvents: [StoredFriendEvent] = []

    private let authService: FoodAuthService
    private let appSettings = AppSettings.shared
    private let userServerHost: String
    private let userServerPort: Int
    private let userUseTLS: Bool
    private let cachedUserKey = "Eatometer.cachedUser.current"
    private let friendEventsStorageKey = "Eatometer.friendActivityEvents.v1"
    private let maxStoredFriendEvents = 300

    init(authService: FoodAuthService) {
        self.authService = authService
        let userConfig = ConfigLoader.loadUserAPIConfig()
        self.userServerHost = userConfig.host
        self.userServerPort = userConfig.port
        self.userUseTLS = userConfig.useTLS
        loadCachedProfile()
        loadStoredFriendEvents()
    }

    func clearCachedProfile() {
        UserDefaults.standard.removeObject(forKey: cachedUserKey)
        UserDefaults.standard.removeObject(forKey: "userEmail")
        currentUser = nil
        currentUserID = nil
        profileAppearance = .default
        friends = []
        incomingFriendRequests = []
        outgoingFriendRequests = []
        declinedFriendRequests = []
        friendSearchResults = []
        friendsErrorMessage = nil
        friendActivityEvents = []
        UserDefaults.standard.removeObject(forKey: friendEventsStorageKey)
        appSettings.setScope(userID: nil)
        appSettings.resetToDefaults()
    }

    @discardableResult
    func fetchCurrentUser() async -> Bool {
        guard authService.isAuthenticated else { return false }

        do {
            let user = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    let request = User_GetCurrentUserRequest()
                    return try await client.getCurrentUser(request, metadata: metadata)
                }
            }

            applyCurrentUser(user)
            return true
        } catch {
            print("UserService.fetchCurrentUser failed: \(error)")

            if shouldInvalidateSession(after: error) {
                authService.logout()
                clearCachedProfile()
                return false
            }

            return true
        }
    }

    func setProfileAppearance(_ appearance: ProfileAppearance) {
        profileAppearance = appearance
        ProfileAppearanceStore.save(appearance, userID: currentUserID)
        Task { await syncUserSettingsToServer() }
    }

    func syncUserSettingsToServer() async {
        do {
            _ = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    var request = User_UpdateUserSettingsRequest()
                    request.avatarEmoji = profileAppearance.emoji ?? ""
                    request.avatarMonogramStyle = profileAppearance.monogramStyle.rawValue
                    request.avatarBackgroundStyle = profileAppearance.backgroundStyle.rawValue
                    return try await client.updateUserSettings(request, metadata: metadata)
                }
            }
        } catch {
            print("UserService.syncUserSettingsToServer failed: \(error)")
        }
    }

    func changeNickname(newNickname: String) async -> (Bool, Bool, String?) {
        let result = await updateName(newNickname)
        return (result.0, false, result.1)
    }

    func updateName(_ name: String) async -> (Bool, String?) {
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    var request = User_UpdateNameRequest()
                    request.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return try await client.updateName(request, metadata: metadata)
                }
            }
            if response.success {
                if response.hasUser { applyCurrentUser(response.user) }
                else { await fetchCurrentUser() }
            }
            return (response.success, response.error.isEmpty ? nil : response.error)
        } catch {
            return (false, String(describing: error))
        }
    }

    func setProfileName(firstName: String, lastName: String) async -> (Bool, String?) {
        await updateName([firstName, lastName].filter { !$0.isEmpty }.joined(separator: " "))
    }

    func setBirthdate(_ date: Date) async -> (Bool, String?) {
        (false, "Дата рождения хранится только в профиле здоровья Eatometer")
    }

    func setSex(_ sex: User_UserSex) async -> (Bool, String?) {
        (false, "Пол хранится только в профиле здоровья Eatometer")
    }

    func setSupporterStatus(
        active: Bool,
        tier: String,
        productID: String,
        originalTransactionID: String,
        expiresAt: Date?,
        appID: String
    ) async -> (Bool, String?) {
        do {
            let requestedAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
            var resolvedAppID = authService.currentAppID()

            if !requestedAppID.isEmpty,
               let currentAppID = resolvedAppID,
               currentAppID != requestedAppID,
               await authService.refreshAccessToken() {
                resolvedAppID = authService.currentAppID()
            }

            var request = User_SetSupporterStatusRequest()
            request.active = active
            request.tier = tier
            request.productID = productID
            request.originalTransactionID = originalTransactionID
            if let expiresAt {
                request.expiresAt = Google_Protobuf_Timestamp(date: expiresAt)
            }
            let appIDForRequest = resolvedAppID ?? requestedAppID
            request.appID = appIDForRequest
            let response = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    try await client.setSupporterStatus(request, metadata: metadata)
                }
            }
            if response.success {
                if response.hasUser {
                    applyCurrentUser(response.user)
                } else {
                    await fetchCurrentUser()
                }
            }
            return (response.success, response.error.isEmpty ? nil : response.error)
        } catch {
            return (false, String(describing: error))
        }
    }

    func deleteAccount(delayDays: Int32 = 0) async -> (Bool, String?) {
        do {
            var request = User_DeleteAccountRequest()
            request.delayDays = delayDays
            let response = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    try await client.deleteAccount(request, metadata: metadata)
                }
            }
            return (response.success, response.error.isEmpty ? nil : response.error)
        } catch {
            return (false, String(describing: error))
        }
    }

    func exportUserData() async -> [String: Data]? {
        do {
            return try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    let request = User_GetCurrentUserRequest()
                    return try await client.exportUserData(request, metadata: metadata) { response in
                        var buckets: [String: Data] = [:]
                        for try await chunk in response.messages {
                            let key = chunk.filename.isEmpty ? "user-export.bin" : chunk.filename
                            var data = buckets[key] ?? Data()
                            data.append(chunk.chunk)
                            buckets[key] = data
                        }
                        return buckets
                    }
                }
            }
        } catch {
            print("UserService.exportUserData failed: \(error)")
            return nil
        }
    }

    func refreshFriendships() async {
        guard authService.isAuthenticated else { return }
        isLoadingFriendships = true
        friendsErrorMessage = nil
        defer { isLoadingFriendships = false }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    try await client.listFriendships(User_ListFriendshipsRequest(), metadata: metadata)
                }
            }
            friends = response.friends.map(EatometerFriendship.init)
            incomingFriendRequests = response.incomingRequests.map(EatometerFriendship.init)
            outgoingFriendRequests = response.outgoingRequests.map(EatometerFriendship.init)
            declinedFriendRequests = response.declinedRequests.map(EatometerFriendship.init)
            recordFriendActivityEvents()
        } catch {
            friendsErrorMessage = String(describing: error)
        }
    }

    // MARK: - Friend activity events (local history)

    private func recordFriendActivityEvents(now: Date = Date()) {
        let day = friendEventDayKey(for: now)
        var byID = Dictionary(friendActivityEvents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for friendship in friends {
            let profile = friendship.profile

            func upsert(_ kind: String, _ value: Int) {
                let id = "\(profile.id)-\(kind)-\(day)"
                byID[id] = StoredFriendEvent(id: id, profile: profile, kind: kind, value: value, recordedAt: now)
            }

            if profile.foodLoggingStreakDays >= 3 {
                upsert("streak", profile.foodLoggingStreakDays)
            }
            if profile.mealsLoggedToday > 0 {
                upsert("meals", profile.mealsLoggedToday)
            }
            if profile.caloriesToday > 0 {
                upsert("calories", profile.caloriesToday)
            }
            if profile.waterTrackingEnabled, profile.waterTodayMilliliters > 0 {
                if profile.waterGoalMilliliters > 0, profile.waterTodayMilliliters >= profile.waterGoalMilliliters {
                    upsert("waterGoal", profile.waterTodayMilliliters)
                } else {
                    upsert("water", profile.waterTodayMilliliters)
                }
            }
        }

        var merged = Array(byID.values).sorted { $0.recordedAt > $1.recordedAt }
        if merged.count > maxStoredFriendEvents {
            merged = Array(merged.prefix(maxStoredFriendEvents))
        }
        friendActivityEvents = merged
        persistStoredFriendEvents()
    }

    private func friendEventDayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func persistStoredFriendEvents() {
        guard let data = try? JSONEncoder().encode(friendActivityEvents) else { return }
        UserDefaults.standard.set(data, forKey: friendEventsStorageKey)
    }

    private func loadStoredFriendEvents() {
        guard let data = UserDefaults.standard.data(forKey: friendEventsStorageKey),
              let decoded = try? JSONDecoder().decode([StoredFriendEvent].self, from: data) else { return }
        friendActivityEvents = decoded.sorted { $0.recordedAt > $1.recordedAt }
    }

    func searchFriends(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authService.isAuthenticated, !trimmedQuery.isEmpty else {
            friendSearchResults = []
            return
        }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    var request = User_SearchUsersRequest()
                    request.query = trimmedQuery
                    request.limit = 20
                    return try await client.searchUsers(request, metadata: metadata)
                }
            }
            friendSearchResults = response.users.map(EatometerFriendProfile.init)
        } catch {
            friendsErrorMessage = String(describing: error)
        }
    }

    @discardableResult
    func sendFriendRequest(to targetUserID: String) async -> Bool {
        do {
            _ = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    var request = User_SendFriendRequestRequest()
                    request.targetUserID = targetUserID
                    return try await client.sendFriendRequest(request, metadata: metadata)
                }
            }
            await refreshFriendships()
            return true
        } catch {
            friendsErrorMessage = String(describing: error)
            await refreshFriendships()
            return false
        }
    }

    @discardableResult
    func respondFriendRequest(requesterUserID: String, accept: Bool) async -> Bool {
        do {
            _ = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    var request = User_RespondFriendRequestRequest()
                    request.requesterUserID = requesterUserID
                    request.accept = accept
                    return try await client.respondFriendRequest(request, metadata: metadata)
                }
            }
            await refreshFriendships()
            return true
        } catch {
            friendsErrorMessage = String(describing: error)
            await refreshFriendships()
            return false
        }
    }

    @discardableResult
    func dismissDeclinedFriendRequest(requesterUserID: String) async -> Bool {
        do {
            _ = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    var request = User_DismissDeclinedFriendRequestRequest()
                    request.requesterUserID = requesterUserID
                    return try await client.dismissDeclinedFriendRequest(request, metadata: metadata)
                }
            }
            await refreshFriendships()
            return true
        } catch {
            friendsErrorMessage = String(describing: error)
            await refreshFriendships()
            return false
        }
    }

    @discardableResult
    func removeFriend(friendUserID: String) async -> Bool {
        do {
            _ = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    var request = User_RemoveFriendRequest()
                    request.friendUserID = friendUserID
                    return try await client.removeFriend(request, metadata: metadata)
                }
            }
            await refreshFriendships()
            return true
        } catch {
            friendsErrorMessage = String(describing: error)
            await refreshFriendships()
            return false
        }
    }

    private func withUserClient<T>(
        _ body: (User_UserService.Client<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T where T: Sendable {
        try await GRPCCore.withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: userServerHost, port: userServerPort),
                transportSecurity: userUseTLS ? .tls : .plaintext
            )
        ) { client in
            let userClient = User_UserService.Client(wrapping: client)
            return try await body(userClient)
        }
    }

    private func withAuthenticatedMetadata<T: Sendable>(_ operation: (Metadata) async throws -> T) async throws -> T {
        return try await authService.withAuthorizedMetadata(operation)
    }

    private func applySettingsFromServer(_ settings: User_UserSettings) {
        let appearance = ProfileAppearance(
            emoji: settings.avatarEmoji.isEmpty ? nil : settings.avatarEmoji,
            monogramStyle: ProfileAppearance.MonogramStyle(rawValue: settings.avatarMonogramStyle) ?? .classic,
            backgroundStyle: ProfileAppearance.BackgroundStyle(rawValue: settings.avatarBackgroundStyle) ?? .cyan
        )
        profileAppearance = appearance
        ProfileAppearanceStore.save(appearance, userID: currentUserID)
    }

    private func applyCurrentUser(_ user: User_User) {
        currentUser = user
        authService.updateCurrentUsername(user.name)
        UserDefaults.standard.set(user.email, forKey: "userEmail")

        if let userID = extractUserID(from: user) {
            currentUserID = userID
        }

        appSettings.setScope(userID: currentUserID)

        if currentUserID != nil {
            profileAppearance = ProfileAppearanceStore.load(userID: currentUserID)
        }

        if user.hasSettings {
            applySettingsFromServer(user.settings)
        }

        saveCachedProfile(user)
    }

    private func loadCachedProfile() {
        guard let dict = UserDefaults.standard.dictionary(forKey: cachedUserKey) else { return }
        var user = User_User()
        user.name = dict["name"] as? String ?? ""
        user.email = dict["email"] as? String ?? ""
        user.emailConfirmed = dict["emailConfirmed"] as? Bool ?? false
        currentUser = user.name.isEmpty && user.email.isEmpty ? nil : user
        currentUserID = dict["userID"] as? String
        profileAppearance = ProfileAppearanceStore.load(userID: currentUserID)
        appSettings.setScope(userID: currentUserID)
    }

    private func saveCachedProfile(_ user: User_User) {
        let dict: [String: Any] = [
            "name": user.name,
            "email": user.email,
            "emailConfirmed": user.emailConfirmed,
            "userID": currentUserID ?? ""
        ]
        UserDefaults.standard.set(dict, forKey: cachedUserKey)
    }

    private func shouldInvalidateSession(after error: Error) -> Bool {
        if let rpcError = error as? RPCError {
            switch rpcError.code {
            case .unauthenticated, .notFound:
                return true
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.code == 401 {
            return true
        }

        if nsError.domain == NSURLErrorDomain,
           nsError.code == URLError.userAuthenticationRequired.rawValue {
            return true
        }

        let lowered = String(describing: error).lowercased()
        return lowered.contains("unauthenticated")
            || lowered.contains("user not found")
            || lowered.contains("account not found")
            || lowered.contains("current user not found")
    }

    private func extractUserID(from user: User_User) -> String? {
        guard let json = try? user.jsonString(),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return (object["id"] as? String)
            ?? (object["user_id"] as? String)
            ?? (object["userId"] as? String)
    }

    private func extractBirthdate(from user: User_User) -> Date? {
        guard let json = try? user.jsonString(),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let value = object["birthdate"] as? String {
            let iso = ISO8601DateFormatter()
            if let date = iso.date(from: value) {
                return date
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: value)
        }
        if let value = object["birthdate"] as? Double {
            return Date(timeIntervalSince1970: value)
        }
        return nil
    }
}
