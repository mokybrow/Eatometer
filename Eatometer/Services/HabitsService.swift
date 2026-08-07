import Combine
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import SwiftProtobuf
import WidgetKit

@MainActor
final class HabitsService: ObservableObject {
    @Published private(set) var habits: [Habit] = []
    @Published private(set) var checkInsByAttempt: [UUID: [HabitCheckIn]] = [:]
    @Published private(set) var attemptsByHabit: [UUID: [HabitAttempt]] = [:]
    @Published private(set) var historyRevision: Int = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastErrorMessage: String?

    private let authService: FoodAuthService?
    private let serverHost: String
    private let serverPort: Int
    private let useTLS: Bool
    private var attemptsLoadedAtByHabit: [UUID: Date] = [:]
    private var checkInsLoadedAtByAttempt: [UUID: Date] = [:]
    private var appliedCacheScopeID: String
    private var preloadTask: Task<Void, Never>?

    private static let sharedAppGroupID = "group.com.goeatometer.Eatometer.shared"
    private static let habitWidgetSnapshotKey = "Eatometer.widget.habits.snapshot"
    private static let pendingHabitCheckInsKey = "Eatometer.widget.pendingHabitCheckIns"
    private static let habitWidgetKind = "EatometerHabitWidget"
    private static let habitCacheKeyPrefix = "Eatometer.habits.cache."
    private static let cachedHistoryFreshness: TimeInterval = 120

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: sharedAppGroupID)
    }

    private struct WidgetHabitSnapshot: Codable {
        var habits: [WidgetHabitSummary]
        var updatedAt: Date
    }

    private struct WidgetHabitSummary: Codable {
        let id: String
        let name: String
        let icon: String
        let colorHex: String
        let kind: String
        let trackingMode: String
        let targetDays: Int?
        let attemptID: String?
        let attemptStartedAt: Date?
        let attemptEndedAt: Date?
        var checkInCount: Int
        var checkedDayKeys: [String]
    }

    private struct PendingWidgetHabitCheckIn: Codable {
        let id: String
        let scopeUserID: String
        let habitID: String
        let attemptID: String
        let dayKey: String
        let createdAt: Date
    }

    private struct HabitCacheSnapshot: Codable {
        var habits: [Habit]
        var attemptsByHabit: [UUID: [HabitAttempt]]
        var checkInsByAttempt: [UUID: [HabitCheckIn]]
        var attemptsLoadedAtByHabit: [UUID: Date]
        var checkInsLoadedAtByAttempt: [UUID: Date]
        var updatedAt: Date
    }

    init() {
        self.authService = nil
        self.serverHost = ""
        self.serverPort = 0
        self.useTLS = false
        self.appliedCacheScopeID = "preview"
    }

    init(authService: FoodAuthService) {
        let config = ConfigLoader.loadFoodAPIConfig()
        self.authService = authService
        self.serverHost = config.host
        self.serverPort = config.port
        self.useTLS = config.useTLS
        self.appliedCacheScopeID = Self.normalizeCacheScope(authService.currentUsername)
        applyHabitCacheSnapshot(Self.loadHabitCacheSnapshot(scopeID: self.appliedCacheScopeID), resetWhenMissing: false)
    }

    // MARK: - Loading

    func restoreCachedHabitsIfAvailable() {
        applyCachedHabitSnapshotIfNeeded()
        persistHabitWidgetSnapshot()
    }

    func clear() {
        preloadTask?.cancel()
        preloadTask = nil
        habits = []
        checkInsByAttempt = [:]
        attemptsByHabit = [:]
        attemptsLoadedAtByHabit = [:]
        checkInsLoadedAtByAttempt = [:]
        historyRevision += 1
        lastErrorMessage = nil
    }

    func preloadHabitsForCurrentSession() async {
        restoreCachedHabitsIfAvailable()

        if let preloadTask {
            await preloadTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncHabitsFromServer(includeHistory: true, currentAttemptCheckInsOnly: true)
        }
        preloadTask = task
        await task.value
        preloadTask = nil
    }

    func loadHabits(includeArchived: Bool = false) async {
        guard authService != nil else { return }
        applyCachedHabitSnapshotIfNeeded()
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ListHabitsRequest()
                request.includeArchived = includeArchived
                return try await self.withFoodClient { client in
                    try await client.listHabits(request, metadata: metadata)
                }
            }
            let mapped = response.habits.compactMap(Habit.init(grpc:))
            self.habits = mapped.sorted { $0.createdAt < $1.createdAt }
            HabitLocalNotificationScheduler.shared.refreshReminders(for: self.habits)
            persistHabitWidgetSnapshot()
            persistHabitCacheSnapshot()
            self.lastErrorMessage = nil
        } catch {
            storeLastError(error)
        }
    }

    func syncHabitsFromServer(
        includeArchived: Bool = false,
        includeHistory: Bool = true,
        currentAttemptCheckInsOnly: Bool = false
    ) async {
        await loadHabits(includeArchived: includeArchived)
        guard includeHistory else { return }

        let snapshot = habits
        if currentAttemptCheckInsOnly {
            var didLoadCheckIns = false
            for habit in snapshot {
                guard let attemptID = habit.currentAttempt?.id else { continue }
                guard !hasFreshCheckIns(attemptID: attemptID, maxAge: Self.cachedHistoryFreshness) else { continue }
                await loadCheckIns(attemptID: attemptID, persistSnapshots: false, bumpRevision: false)
                didLoadCheckIns = true
                await Task.yield()
            }
            if didLoadCheckIns {
                historyRevision += 1
                persistHabitWidgetSnapshot()
                persistHabitCacheSnapshot()
            }
            return
        }

        for habit in snapshot {
            await loadAttempts(habitID: habit.id)
            await Task.yield()
        }
    }

    @discardableResult
    func createHabit(
        name: String,
        description: String,
        kind: HabitKind,
        icon: String,
        colorHex: String,
        dailyTarget: Int,
        unitLabel: String,
        clientSettings: HabitClientSettings = .default
    ) async -> Habit? {
        guard authService != nil else { return nil }
        let normalizedSettings = clientSettings.normalized
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_CreateHabitRequest()
                request.name = name
                request.description_p = description
                request.kind = kind.grpcValue
                request.icon = icon
                request.colorHex = colorHex
                request.dailyTarget = Int32(dailyTarget)
                request.unitLabel = unitLabel
                request.trackingMode = normalizedSettings.trackingMode.grpcValue
                request.targetDays = Int32(normalizedSettings.targetDays ?? 0)
                request.manualReminderEnabled = normalizedSettings.isReminderEnabled
                request.milestoneNotificationsEnabled = true
                return try await self.withFoodClient { client in
                    try await client.createHabit(request, metadata: metadata)
                }
            }
            guard let habit = Habit(grpc: response.habit) else { return nil }
            habits.append(habit)
            habits.sort { $0.createdAt < $1.createdAt }
            HabitLocalNotificationScheduler.shared.refreshReminders(for: habits)
            persistHabitWidgetSnapshot()
            persistHabitCacheSnapshot()
            lastErrorMessage = nil
            return habit
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func createHabit(from template: HabitTemplate) async -> Habit? {
        let unit = template.unitLabelKey.map { NSLocalizedString($0, comment: "") } ?? ""
        return await createHabit(
            name: NSLocalizedString(template.nameKey, comment: ""),
            description: NSLocalizedString(template.descriptionKey, comment: ""),
            kind: template.kind,
            icon: template.icon,
            colorHex: template.colorHex,
            dailyTarget: template.dailyTarget,
            unitLabel: unit,
            clientSettings: HabitClientSettings(trackingMode: .automatic, targetDays: nil, isReminderEnabled: false)
        )
    }

    @discardableResult
    func updateHabit(
        id: UUID,
        name: String,
        description: String,
        kind: HabitKind,
        icon: String,
        colorHex: String,
        dailyTarget: Int,
        unitLabel: String,
        archived: Bool,
        clientSettings: HabitClientSettings
    ) async -> Habit? {
        guard authService != nil else { return nil }
        let normalizedSettings = clientSettings.normalized
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_UpdateHabitRequest()
                request.id = id.uuidString
                request.name = name
                request.description_p = description
                request.kind = kind.grpcValue
                request.icon = icon
                request.colorHex = colorHex
                request.dailyTarget = Int32(dailyTarget)
                request.unitLabel = unitLabel
                request.archived = archived
                request.trackingMode = normalizedSettings.trackingMode.grpcValue
                request.targetDays = Int32(normalizedSettings.targetDays ?? 0)
                request.manualReminderEnabled = normalizedSettings.isReminderEnabled
                request.milestoneNotificationsEnabled = true
                return try await self.withFoodClient { client in
                    try await client.updateHabit(request, metadata: metadata)
                }
            }
            guard var habit = Habit(grpc: response.habit) else { return nil }
            habit.trackingMode = normalizedSettings.trackingMode
            habit.targetDays = normalizedSettings.targetDays
            habit.manualReminderEnabled = normalizedSettings.isReminderEnabled
            replace(habit: habit)
            HabitLocalNotificationScheduler.shared.refreshReminders(for: habits)
            persistHabitWidgetSnapshot()
            persistHabitCacheSnapshot()
            lastErrorMessage = nil
            return habit
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func deleteHabit(id: UUID) async -> Bool {
        guard authService != nil else { return false }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_DeleteHabitRequest()
                request.id = id.uuidString
                return try await self.withFoodClient { client in
                    try await client.deleteHabit(request, metadata: metadata)
                }
            }
            if response.success {
                habits.removeAll { $0.id == id }
                attemptsByHabit.removeValue(forKey: id)
                attemptsLoadedAtByHabit.removeValue(forKey: id)
                historyRevision += 1
                HabitLocalNotificationScheduler.shared.cancelReminder(for: id)
                persistHabitWidgetSnapshot()
                persistHabitCacheSnapshot()
            }
            lastErrorMessage = nil
            return response.success
        } catch {
            storeLastError(error)
            return false
        }
    }

    @discardableResult
    func resetProgress(habitID: UUID, reason: String = "") async -> Habit? {
        guard authService != nil else { return nil }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ResetHabitProgressRequest()
                request.id = habitID.uuidString
                request.reason = reason
                return try await self.withFoodClient { client in
                    try await client.resetHabitProgress(request, metadata: metadata)
                }
            }
            guard let habit = Habit(grpc: response.habit) else { return nil }
            replace(habit: habit)
            HabitLocalNotificationScheduler.shared.refreshReminders(for: habits)
            persistHabitWidgetSnapshot()
            persistHabitCacheSnapshot()
            lastErrorMessage = nil
            await refreshHabitStateFromServer(habitID: habitID)
            return habit
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func toggleCheckIn(habit: Habit, day: Date) async -> Bool {
        guard let attempt = habit.currentAttempt else { return false }
        let dayKey = habitDayKey(for: day)
        let normalizedDay = DateFormatter.habitDay.date(from: dayKey) ?? day
        let existing = checkInsByAttempt[attempt.id]?.first { sameDay($0.day, normalizedDay) }
        if existing != nil {
            return await removeCheckIn(habit: habit, day: normalizedDay)
        } else {
            return await addCheckIn(habit: habit, day: normalizedDay) != nil
        }
    }

    @discardableResult
    func addCheckIn(habit: Habit, day: Date, value: Int = 1, note: String = "") async -> HabitCheckIn? {
        guard authService != nil, let attempt = habit.currentAttempt else { return nil }
        let dayKey = habitDayKey(for: day)
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_CheckInHabitRequest()
                request.habitID = habit.id.uuidString
                request.day = dayKey
                request.value = Int32(max(1, value))
                request.note = note
                request.checkedAt = Google_Protobuf_Timestamp(date: Date())
                return try await self.withFoodClient { client in
                    try await client.checkInHabit(request, metadata: metadata)
                }
            }
            guard let checkIn = HabitCheckIn(grpc: response.checkIn) else { return nil }
            mergeCheckIn(checkIn, attemptID: attempt.id)
            persistHabitCacheSnapshot()
            await refreshHabitStateFromServer(habitID: habit.id)
            lastErrorMessage = nil
            return checkIn
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func removeCheckIn(habit: Habit, day: Date) async -> Bool {
        guard authService != nil, habit.currentAttempt != nil else { return false }
        let dayKey = habitDayKey(for: day)
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_DeleteHabitCheckInRequest()
                request.habitID = habit.id.uuidString
                request.day = dayKey
                return try await self.withFoodClient { client in
                    try await client.deleteHabitCheckIn(request, metadata: metadata)
                }
            }
            if response.success {
                await refreshHabitStateFromServer(habitID: habit.id)
            }
            lastErrorMessage = nil
            return response.success
        } catch {
            storeLastError(error)
            return false
        }
    }

    func loadAttempts(habitID: UUID, includeCheckIns: Bool = false) async {
        guard authService != nil else { return }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ListHabitAttemptsRequest()
                request.habitID = habitID.uuidString
                return try await self.withFoodClient { client in
                    try await client.listHabitAttempts(request, metadata: metadata)
                }
            }
            let mapped = response.attempts.compactMap(HabitAttempt.init(grpc:))
            let previousAttemptIDs = Set((attemptsByHabit[habitID] ?? []).map(\.id))
            attemptsByHabit[habitID] = mapped.sorted { $0.startedAt > $1.startedAt }
            attemptsLoadedAtByHabit[habitID] = Date()
            historyRevision += 1
            let currentAttemptIDs = Set(mapped.map(\.id))
            for removedID in previousAttemptIDs.subtracting(currentAttemptIDs) {
                checkInsByAttempt.removeValue(forKey: removedID)
                checkInsLoadedAtByAttempt.removeValue(forKey: removedID)
            }

            if includeCheckIns {
                for attempt in mapped {
                    await loadCheckIns(attemptID: attempt.id, persistSnapshots: false, bumpRevision: false)
                    await Task.yield()
                }
            }
            persistHabitWidgetSnapshot()
            persistHabitCacheSnapshot()
            lastErrorMessage = nil
        } catch {
            storeLastError(error)
        }
    }

    func loadCheckIns(attemptID: UUID, persistSnapshots: Bool = true, bumpRevision: Bool = true) async {
        guard authService != nil else { return }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ListHabitCheckInsRequest()
                request.attemptID = attemptID.uuidString
                return try await self.withFoodClient { client in
                    try await client.listHabitCheckIns(request, metadata: metadata)
                }
            }
            let mapped = response.checkIns.compactMap(HabitCheckIn.init(grpc:))
            checkInsByAttempt[attemptID] = mapped.sorted { $0.day < $1.day }
            checkInsLoadedAtByAttempt[attemptID] = Date()
            if bumpRevision {
                historyRevision += 1
            }
            if persistSnapshots {
                persistHabitWidgetSnapshot()
                persistHabitCacheSnapshot()
            }
            lastErrorMessage = nil
        } catch {
            storeLastError(error)
        }
    }

    func loadAttemptsIfNeeded(habitID: UUID, maxAge: TimeInterval? = nil) async {
        let resolvedMaxAge = maxAge ?? Self.cachedHistoryFreshness
        if let loadedAt = attemptsLoadedAtByHabit[habitID],
           Date().timeIntervalSince(loadedAt) < resolvedMaxAge {
            return
        }
        await loadAttempts(habitID: habitID, includeCheckIns: false)
    }

    func loadCheckInsIfNeeded(attemptID: UUID, maxAge: TimeInterval? = nil) async {
        let resolvedMaxAge = maxAge ?? Self.cachedHistoryFreshness
        if hasFreshCheckIns(attemptID: attemptID, maxAge: resolvedMaxAge) {
            return
        }
        await loadCheckIns(attemptID: attemptID)
    }

    // MARK: - Helpers

    private func hasFreshCheckIns(attemptID: UUID, maxAge: TimeInterval) -> Bool {
        guard let loadedAt = checkInsLoadedAtByAttempt[attemptID] else { return false }
        return Date().timeIntervalSince(loadedAt) < maxAge
    }

    func checkIns(forAttempt attemptID: UUID) -> [HabitCheckIn] {
        checkInsByAttempt[attemptID] ?? []
    }

    func attempts(forHabit habitID: UUID) -> [HabitAttempt] {
        attemptsByHabit[habitID] ?? []
    }

    func processPendingWidgetHabitCheckIns() async {
        guard let defaults = Self.sharedDefaults,
              let data = defaults.data(forKey: Self.pendingHabitCheckInsKey),
              !data.isEmpty,
              let pending = try? JSONDecoder().decode([PendingWidgetHabitCheckIn].self, from: data) else {
            return
        }

        var remaining: [PendingWidgetHabitCheckIn] = []
        for item in pending {
            guard let habitID = UUID(uuidString: item.habitID),
                  let attemptID = UUID(uuidString: item.attemptID) else {
                continue
            }

            guard let habit = habits.first(where: { $0.id == habitID }) else {
                remaining.append(item)
                continue
            }

            guard
                  habit.trackingMode == .manual,
                  habit.currentAttempt?.id == attemptID else {
                continue
            }

            let day = Self.date(fromHabitDayKey: item.dayKey) ?? Date()
            let alreadyChecked = checkInsByAttempt[attemptID]?.contains { checkIn in
                habitDayKey(for: checkIn.day) == item.dayKey
            } ?? false
            if alreadyChecked {
                continue
            }

            if await addCheckIn(habit: habit, day: day) == nil {
                remaining.append(item)
            }
        }

        if remaining.isEmpty {
            defaults.removeObject(forKey: Self.pendingHabitCheckInsKey)
        } else if let encoded = try? JSONEncoder().encode(remaining) {
            defaults.set(encoded, forKey: Self.pendingHabitCheckInsKey)
        }
        persistHabitWidgetSnapshot()
    }

    func currentStreak(habit: Habit, on referenceDate: Date = Date()) -> Int {
        guard let attempt = habit.currentAttempt else { return 0 }
        let checkIns = checkInsByAttempt[attempt.id] ?? []
        guard !checkIns.isEmpty else { return 0 }
        let cal = Calendar.current
        let attemptStartDay = cal.startOfDay(for: attempt.startedAt)
        let referenceDay = cal.startOfDay(for: referenceDate)
        let anchorDay: Date
        if cal.isDateInToday(referenceDay) {
            anchorDay = cal.date(byAdding: .day, value: -1, to: referenceDay) ?? referenceDay
        } else {
            anchorDay = referenceDay
        }

        guard anchorDay >= attemptStartDay else { return 0 }

        var streak = 0
        var cursor = anchorDay
        let daySet = Set(checkIns.map { cal.startOfDay(for: $0.day) })
        while daySet.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    private func mergeCheckIn(_ checkIn: HabitCheckIn, attemptID: UUID) {
        var list = checkInsByAttempt[attemptID] ?? []
        list.removeAll { sameDay($0.day, checkIn.day) }
        list.append(checkIn)
        list.sort { $0.day < $1.day }
        checkInsByAttempt[attemptID] = list
        historyRevision += 1
    }

    private func sameDay(_ a: Date, _ b: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: a) == calendar.startOfDay(for: b)
    }

    private func habitDayKey(for day: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return DateFormatter.habitDay.string(from: day)
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func date(fromHabitDayKey dayKey: String) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return components.date
    }

    private func replace(habit: Habit) {
        if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[idx] = habit
        } else {
            habits.append(habit)
            habits.sort { $0.createdAt < $1.createdAt }
        }
    }

    private func refreshHabitStateFromServer(habitID: UUID) async {
        await loadHabits()
        await loadAttempts(habitID: habitID)
    }

    private var cacheScopeID: String {
        Self.normalizeCacheScope(authService?.currentUsername)
    }

    private func applyCachedHabitSnapshotIfNeeded() {
        let scopeID = cacheScopeID
        let didChangeScope = scopeID != appliedCacheScopeID
        guard didChangeScope || habits.isEmpty else { return }

        appliedCacheScopeID = scopeID
        applyHabitCacheSnapshot(Self.loadHabitCacheSnapshot(scopeID: scopeID), resetWhenMissing: didChangeScope)
    }

    private func applyHabitCacheSnapshot(_ snapshot: HabitCacheSnapshot?, resetWhenMissing: Bool) {
        guard let snapshot else {
            if resetWhenMissing {
                habits = []
                attemptsByHabit = [:]
                checkInsByAttempt = [:]
                attemptsLoadedAtByHabit = [:]
                checkInsLoadedAtByAttempt = [:]
            }
            return
        }

        habits = snapshot.habits.sorted { $0.createdAt < $1.createdAt }
        attemptsByHabit = snapshot.attemptsByHabit
        checkInsByAttempt = snapshot.checkInsByAttempt
        attemptsLoadedAtByHabit = snapshot.attemptsLoadedAtByHabit
        checkInsLoadedAtByAttempt = snapshot.checkInsLoadedAtByAttempt
        historyRevision += 1
    }

    private func persistHabitCacheSnapshot() {
        let snapshot = HabitCacheSnapshot(
            habits: habits,
            attemptsByHabit: attemptsByHabit,
            checkInsByAttempt: checkInsByAttempt,
            attemptsLoadedAtByHabit: attemptsLoadedAtByHabit,
            checkInsLoadedAtByAttempt: checkInsLoadedAtByAttempt,
            updatedAt: Date()
        )
        CachedJSONStore.save(snapshot, key: Self.habitCacheKeyPrefix + cacheScopeID)
    }

    private static func loadHabitCacheSnapshot(scopeID: String) -> HabitCacheSnapshot? {
        CachedJSONStore.load(HabitCacheSnapshot.self, key: habitCacheKeyPrefix + scopeID)
    }

    private static func normalizeCacheScope(_ rawValue: String?) -> String {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "anon" : trimmed.lowercased()
    }

    private func persistHabitWidgetSnapshot() {
        guard let defaults = Self.sharedDefaults else { return }
        let snapshot = WidgetHabitSnapshot(
            habits: habits
                .filter { !$0.isArchived }
                .map(makeWidgetHabitSummary(from:)),
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let previousData = defaults.data(forKey: Self.habitWidgetSnapshotKey)
        guard previousData != data else { return }
        defaults.set(data, forKey: Self.habitWidgetSnapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.habitWidgetKind)
    }

    private func makeWidgetHabitSummary(from habit: Habit) -> WidgetHabitSummary {
        let attempt = habit.currentAttempt
        let checkedDayKeys: [String]
        if let attempt {
            checkedDayKeys = (checkInsByAttempt[attempt.id] ?? []).map { habitDayKey(for: $0.day) }
        } else {
            checkedDayKeys = []
        }

        return WidgetHabitSummary(
            id: habit.id.uuidString,
            name: habit.name,
            icon: habit.icon,
            colorHex: habit.colorHex,
            kind: habit.kind.rawValue,
            trackingMode: habit.trackingMode.rawValue,
            targetDays: habit.targetDays,
            attemptID: attempt?.id.uuidString,
            attemptStartedAt: attempt?.startedAt,
            attemptEndedAt: attempt?.endedAt,
            checkInCount: checkedDayKeys.count,
            checkedDayKeys: checkedDayKeys
        )
    }

    private func storeLastError(_ error: Error) {
        lastErrorMessage = (error as NSError).localizedDescription
    }

    // MARK: - gRPC plumbing

    private func withFoodClient<T>(
        _ body: (Food_FoodService.Client<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T where T: Sendable {
        try await GRPCCore.withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: serverHost, port: serverPort),
                transportSecurity: useTLS ? .tls : .plaintext
            )
        ) { client in
            let foodClient = Food_FoodService.Client(wrapping: client)
            return try await body(foodClient)
        }
    }

    private func withAuthenticatedMetadata<T: Sendable>(_ operation: (Metadata) async throws -> T) async throws -> T {
        guard let authService else {
            throw NSError(domain: "HabitsService", code: 401, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("food.service.auth_failed", comment: "")])
        }
        return try await authService.withAuthorizedMetadata(operation)
    }
}
