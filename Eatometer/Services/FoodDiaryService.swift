import Combine
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import SwiftProtobuf
import WidgetKit

@MainActor
final class FoodDiaryService: ObservableObject {
    private static let legacyManualNutritionItemName = "Ручной ввод КБЖУ"
    private static let manualNutritionNotePrefix = "eatometer.manualNutrition|"
    private static let mealCategoryNotePrefix = "eatometer.mealCategory|"

    @Published private(set) var meals: [MealEntry]
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?
    private(set) var lastSharedMealImportAlreadyExists = false
    @Published private(set) var dailyGoal: DailyNutritionGoal
    @Published private(set) var dietPlan: DietPlanOption
    @Published private(set) var mealCategories: [MealCategory]
    @Published private(set) var dailyHistory: [Date: NutritionSummary]

    private let authService: FoodAuthService?
    private weak var catalogService: FoodCatalogService?
    private let appSettings: AppSettings
    private let serverHost: String
    private let serverPort: Int
    private let useTLS: Bool
    private var scopeUserID: String
    private var cacheScopeID: String
    private var mealCacheSnapshot: DiaryCacheSnapshot?
    private var hasLoadedMealCacheSnapshot: Bool
    private var activeDay: Date
    private var mealsLoadGeneration: Int
    private var historyLoadGeneration: Int
    private var hasLoadedRemoteNutritionSettings: Bool
    private var cachedFoodSettings: User_EatometerSettings?
    private var dailyGoalOverrides: [String: DailyNutritionGoal]
    private var mealCategoryAssignments: [String: String]
    private var localNutritionSettingsUpdatedAt: Date
    private var nutritionSettingsLoadTask: Task<Void, Never>?
    private var mealSharePayloads: [UUID: FoodSharePayload] = [:]
    private var mealShareTasks: [UUID: Task<FoodSharePayload?, Never>] = [:]
    @Published private(set) var cheatMealDays: Set<String>
    @Published private(set) var shouldShowCalorieOnboarding = false
    /// A soft prompt (not the full onboarding) asking the user to review their
    /// calorie target after their weight changed. Drives a review sheet.
    @Published var shouldShowCaloriePlanReview = false
    @Published private(set) var hasResolvedCalorieOnboardingState = false
    @Published private(set) var mealRemindersEnabled = false
    @Published private(set) var usefulNotificationsEnabled = false
    @Published private(set) var habitNotificationsEnabled = true
    @Published private(set) var waterLoggingRemindersEnabled = true
    @Published private(set) var healthSyncEnabled = false
    @Published private(set) var waterIntakeByDay: [String: Int] = [:]
    @Published private(set) var dailyWaterGoalMilliliters: Int = 2000

    private static let dailyGoalKeyPrefix = "Eatometer.diary.goal."
    private static let dietPlanKeyPrefix = "Eatometer.diary.dietPlan."
    private static let dailyGoalOverrideKeyPrefix = "Eatometer.diary.goalOverride."
    private static let mealCategoriesKeyPrefix = "Eatometer.diary.mealCategories."
    private static let mealCategoryAssignmentsKeyPrefix = "Eatometer.diary.mealAssignments."
    private static let cheatMealDaysKeyPrefix = "Eatometer.diary.cheatMealDays."
    private static let waterIntakeKeyPrefix = "Eatometer.diary.waterIntake."
    private static let waterGoalKeyPrefix = "Eatometer.diary.waterGoal."
    private static let widgetTodaySnapshotKey = "Eatometer.widget.today.snapshot"
    private static let widgetScopeUserIDKey = "Eatometer.widget.scopeUserID"
    private static let sharedAppGroupID = "group.com.goeatometer.Eatometer.shared"
    private static let calorieOnboardingCompletedKeyPrefix = "Eatometer.diary.calorieOnboardingCompleted."

    // Kept as a single switch for UI tests. Production trusts the server-side
    // Eatometer settings flag and uses the scoped local value only as an
    // offline fallback, so onboarding remains completed across devices.
    static let isCalorieOnboardingPersistenceDisabled = false
    private static let nutritionSettingsUpdatedAtKeyPrefix = "Eatometer.diary.nutritionUpdatedAt."
    private static let importedMealShareCodesKeyPrefix = "Eatometer.diary.importedMealShareCodes."
    private static let mealCacheKeyPrefix = "Eatometer.diary.mealCache."
    private static let nutritionStatisticsCacheKeyPrefix = "Eatometer.diary.nutritionStatistics."
    private static let waterWidgetKind = "EatometerWidget"
    private static let quickMealWidgetKind = "EatometerQuickMealWidget"
    private static let nutritionWidgetKind = "EatometerNutritionWidget"
    private static let statsWidgetKind = "EatometerStatsWidget"
    private static let maxCachedMealDays = 45
    private static let maxCachedHistoryDays = 120
    private static let batchedMealRangeLimit = 700

    private static var localizedManualNutritionItemName: String {
        NSLocalizedString("addmeal.item.manual_title", comment: "Manual nutrition item title")
    }

    private static func isManualNutritionName(_ rawValue: String) -> Bool {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return false }
        return trimmedValue == legacyManualNutritionItemName || trimmedValue == localizedManualNutritionItemName
    }

    private static func normalizedManualNutritionName(_ rawValue: String) -> String {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return localizedManualNutritionItemName }
        let resolved = isManualNutritionName(trimmedValue) ? localizedManualNutritionItemName : trimmedValue
        // The note packs the name and four numbers into one string separated by
        // bars, and the reader identifies the payload by counting fields. A name
        // carrying a bar of its own would push the count past five and the whole
        // entry would read back as nutrition-less.
        return resolved.replacingOccurrences(of: "|", with: " ")
    }

    private struct DiaryCacheSnapshot: Codable {
        var mealsByDay: [String: [MealEntry]]
        var dailyHistoryByDay: [String: NutritionSummary]
    }

    private struct WidgetTodayMealSummary: Codable {
        let id: String
        let title: String
        let categoryID: String
        let categoryTitle: String
        let calories: Int
        let scheduledAt: Date
    }

    private struct WidgetTodayMealItemSummary: Codable {
        let id: String
        let mealID: String
        let itemID: String?
        let title: String
        let subtitle: String?
        let categoryID: String
        let categoryTitle: String
        let calories: Int
        let scheduledAt: Date
    }

    private struct WidgetMealCategorySummary: Codable {
        let id: String
        let title: String
        let symbolName: String
        /// What this meal is meant to be, in calories.
        ///
        /// Resolved here rather than in the widget: the share is a percentage
        /// of a daily goal, and the widget has no business knowing how the two
        /// combine — it draws a ring against a target and needs the target.
        let targetCalories: Int
        /// Eaten so far today, so the ring has something to fill.
        let calories: Int
    }

    private struct WidgetQuickAddItem: Codable {
        let id: String
        let title: String
        let subtitle: String
        let calories: Int
    }

    private struct WidgetTodaySnapshot: Codable {
        let dayKey: String
        let calories: Int
        let protein: Int
        let fat: Int
        let carbs: Int
        let isWaterTrackingEnabled: Bool
        let caloriesGoal: Int
        let proteinGoal: Int
        let fatGoal: Int
        let carbsGoal: Int
        let waterIntakeMilliliters: Int
        let waterGoalMilliliters: Int
        let waterStepMilliliters: Int
        let loggingStreakDays: Int
        let meals: [WidgetTodayMealSummary]
        let mealItems: [WidgetTodayMealItemSummary]
        let mealCategories: [WidgetMealCategorySummary]
        let products: [WidgetQuickAddItem]
        let recipes: [WidgetQuickAddItem]
        let mealTemplates: [WidgetQuickAddItem]
        let updatedAt: Date
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: sharedAppGroupID)
    }

    private struct HistoryFetchPlan {
        let primaryStart: Date
        let primaryEnd: Date
        let supplementalDay: Date?
    }

    private func localizedAchievementTitle(for kind: NutritionAchievementKind, fallback: String) -> String {
        kind.localizedTitle(fallback: fallback)
    }

    private func localizedAchievementDescription(for kind: NutritionAchievementKind, fallback: String) -> String {
        kind.localizedDescription(fallback: fallback)
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let message = String(describing: error).lowercased()
        if Task.isCancelled {
            return true
        }

        if message.contains("client stopped") ||
            message.contains("can't make more rpcs") ||
            message.contains("cant make more rpcs") ||
            message.contains("cancelled") {
            return true
        }

        let nsError = error as NSError
        if nsError.code == 401 ||
           message.contains("не удалось авторизовать") ||
           message.contains("unauthenticated") {
            return true
        }

        return false
    }

    private func storeLastError(_ error: Error) {
        guard !isCancellationError(error) else {
            lastErrorMessage = nil
            return
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !Self.isTechnicalErrorMessage(description) {
            lastErrorMessage = description
            return
        }

        lastErrorMessage = Self.genericUserFacingErrorMessage
    }

    private static var genericUserFacingErrorMessage: String {
        NSLocalizedString(
            "food.service.generic_error",
            tableName: nil,
            bundle: .main,
            value: "Something went wrong. Try again.",
            comment: "Generic food service error"
        )
    }

    private static func isTechnicalErrorMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("tcp")
            || lowercased.contains("http/2")
            || lowercased.contains("socket")
            || lowercased.contains("grpc")
            || lowercased.contains("unavailable")
            || lowercased.contains("deadline")
            || lowercased.contains("connection")
            || lowercased.contains("errno")
    }

    init() {
        self.authService = nil
        self.catalogService = nil
        self.appSettings = AppSettings.shared
        self.appSettings.setRemoteSyncHandler(nil)
        self.serverHost = ""
        self.serverPort = 0
        self.useTLS = false
        self.scopeUserID = "preview"
        self.cacheScopeID = "preview"
        self.mealCacheSnapshot = nil
        self.hasLoadedMealCacheSnapshot = true
        self.activeDay = Calendar.current.startOfDay(for: .now)
        self.mealsLoadGeneration = 0
        self.historyLoadGeneration = 0
        self.hasLoadedRemoteNutritionSettings = true
        self.cachedFoodSettings = nil
        self.dailyGoal = FoodDiaryService.loadDailyGoal(scopeUserID: "preview")
        self.dietPlan = FoodDiaryService.loadDietPlan(scopeUserID: "preview")
        self.dailyGoalOverrides = FoodDiaryService.loadGoalOverrides(scopeUserID: "preview")
        self.mealCategories = FoodDiaryService.loadMealCategories(scopeUserID: "preview")
        self.mealCategoryAssignments = [:]
        self.localNutritionSettingsUpdatedAt = FoodDiaryService.loadNutritionSettingsUpdatedAt(scopeUserID: "preview")
        self.cheatMealDays = FoodDiaryService.loadCheatMealDays(scopeUserID: "preview")
        self.waterIntakeByDay = ["2025-01-01": 1200]
        self.dailyWaterGoalMilliliters = 2000
        self.meals = FoodDiaryService.previewMeals(for: .now).sorted(by: { $0.scheduledAt < $1.scheduledAt })
        self.dailyHistory = FoodDiaryService.previewHistory(centeredOn: .now)
        self.hasResolvedCalorieOnboardingState = true
        persistWidgetTodaySnapshot()
    }

    init(authService: FoodAuthService, catalogService: FoodCatalogService) {
        let config = ConfigLoader.loadFoodAPIConfig()
        let activeDay = Calendar.current.startOfDay(for: .now)
        let cacheScopeID = FoodDiaryService.normalizeCacheScope(authService.currentUsername)
        let cacheSnapshot = FoodDiaryService.loadMealCacheSnapshot(scopeID: cacheScopeID)
        self.authService = authService
        self.catalogService = catalogService
        self.appSettings = AppSettings.shared
        self.serverHost = config.host
        self.serverPort = config.port
        self.useTLS = config.useTLS
        self.scopeUserID = FoodDiaryService.normalizeScope(authService.currentUsername)
        self.cacheScopeID = cacheScopeID
        self.mealCacheSnapshot = cacheSnapshot
        self.hasLoadedMealCacheSnapshot = true
        self.activeDay = activeDay
        self.mealsLoadGeneration = 0
        self.historyLoadGeneration = 0
        self.hasLoadedRemoteNutritionSettings = false
        self.cachedFoodSettings = nil
        self.dailyGoal = FoodDiaryService.loadDailyGoal(scopeUserID: self.scopeUserID)
        self.dietPlan = FoodDiaryService.loadDietPlan(scopeUserID: self.scopeUserID)
        self.dailyGoalOverrides = FoodDiaryService.loadGoalOverrides(scopeUserID: self.scopeUserID)
        self.mealCategories = FoodDiaryService.loadMealCategories(scopeUserID: self.scopeUserID)
        self.mealCategoryAssignments = FoodDiaryService.loadMealCategoryAssignments(scopeUserID: self.scopeUserID)
        self.localNutritionSettingsUpdatedAt = FoodDiaryService.loadNutritionSettingsUpdatedAt(scopeUserID: self.scopeUserID)
        self.cheatMealDays = FoodDiaryService.loadCheatMealDays(scopeUserID: self.scopeUserID)
        self.waterIntakeByDay = FoodDiaryService.loadWaterIntake(scopeUserID: self.scopeUserID)
        self.dailyWaterGoalMilliliters = FoodDiaryService.loadWaterGoal(scopeUserID: self.scopeUserID)
        self.meals = FoodDiaryService.cachedMeals(for: activeDay, from: cacheSnapshot)
        self.dailyHistory = FoodDiaryService.cachedDailyHistory(from: cacheSnapshot)
        restoreCachedCalorieOnboardingState()
        self.appSettings.setRemoteSyncHandler { [weak self] in
            await self?.pushAppSettingsToRemote()
        }
        persistWidgetTodaySnapshot()
    }

    var totalCalories: Int {
        meals.reduce(0) { $0 + $1.calories }
    }

    var totalProtein: Int {
        meals.reduce(0) { $0 + $1.protein }
    }

    var totalFat: Int {
        meals.reduce(0) { $0 + $1.fat }
    }

    var totalCarbs: Int {
        meals.reduce(0) { $0 + $1.carbs }
    }

    var groupedMeals: [(category: MealCategory, entries: [MealEntry])] {
        visibleMealCategories.compactMap { category in
            let entries = meals.filter { $0.mealCategoryID == category.id }
            guard !entries.isEmpty else { return nil }
            return (category, entries)
        }
    }

    var visibleMealCategories: [MealCategory] {
        let mealCategoryIDsWithEntries = Set(meals.map(\.mealCategoryID))
        var categories = mealCategories
        for uncategorizedID in mealCategoryIDsWithEntries where !categories.contains(where: { $0.id == uncategorizedID }) {
            categories.append(fallbackCategory(for: uncategorizedID, sortOrder: categories.count))
        }
        return categories
            .filter { $0.isEnabled || mealCategoryIDsWithEntries.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.title < rhs.title
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    func setScope(userID: String?) {
        let normalizedScope = FoodDiaryService.normalizeScope(userID)
        let didChangeScope = normalizedScope != scopeUserID

        if didChangeScope {
            nutritionSettingsLoadTask?.cancel()
            nutritionSettingsLoadTask = nil
            scopeUserID = normalizedScope
            dailyGoal = FoodDiaryService.loadDailyGoal(scopeUserID: normalizedScope)
            dietPlan = FoodDiaryService.loadDietPlan(scopeUserID: normalizedScope)
            dailyGoalOverrides = FoodDiaryService.loadGoalOverrides(scopeUserID: normalizedScope)
            mealCategories = FoodDiaryService.loadMealCategories(scopeUserID: normalizedScope)
            mealCategoryAssignments = FoodDiaryService.loadMealCategoryAssignments(scopeUserID: normalizedScope)
            localNutritionSettingsUpdatedAt = FoodDiaryService.loadNutritionSettingsUpdatedAt(scopeUserID: normalizedScope)
            cheatMealDays = FoodDiaryService.loadCheatMealDays(scopeUserID: normalizedScope)
            waterIntakeByDay = FoodDiaryService.loadWaterIntake(scopeUserID: normalizedScope)
            dailyWaterGoalMilliliters = FoodDiaryService.loadWaterGoal(scopeUserID: normalizedScope)
            hasLoadedRemoteNutritionSettings = authService == nil
            cachedFoodSettings = nil
            restoreCachedCalorieOnboardingState()
        }

        let resolvedCacheScope = FoodDiaryService.normalizeCacheScope(authService?.currentUsername)
        let didChangeCacheScope = resolvedCacheScope != cacheScopeID
        if didChangeCacheScope {
            cacheScopeID = resolvedCacheScope
            mealCacheSnapshot = nil
            hasLoadedMealCacheSnapshot = false
            resetMealShareCache()
        }

        if authService == nil {
            meals = FoodDiaryService.previewMeals(for: activeDay).sorted(by: { $0.scheduledAt < $1.scheduledAt })
            registerHistory(for: activeDay, meals: meals)
            dailyHistory = FoodDiaryService.previewHistory(centeredOn: activeDay, selectedDayMeals: meals)
            persistWidgetTodaySnapshot()
            return
        }

        if didChangeScope || didChangeCacheScope || meals.isEmpty || dailyHistory.isEmpty {
            restoreCachedMealsIfAvailable(resetWhenMissing: didChangeScope || didChangeCacheScope)
        }

        persistWidgetTodaySnapshot()
    }

    func goal(for day: Date) -> DailyNutritionGoal {
        dailyGoalOverrides[dayKey(for: day)] ?? dailyGoal
    }

    func hasGoalOverride(for day: Date) -> Bool {
        dailyGoalOverrides[dayKey(for: day)] != nil
    }

    func isCheatMealDay(_ day: Date) -> Bool {
        cheatMealDays.contains(dayKey(for: day))
    }

    func setCheatMealDay(_ isMarked: Bool, for day: Date) {
        let key = dayKey(for: day)
        var updatedCheatMealDays = cheatMealDays
        if isMarked {
            updatedCheatMealDays.insert(key)
        } else {
            updatedCheatMealDays.remove(key)
        }
        cheatMealDays = updatedCheatMealDays
        persistCheatMealDays()
        markLocalNutritionSettingsUpdatedNow()
        Task {
            await pushNutritionSettingsToRemote()
        }
    }

    // MARK: - Water Tracking

    func waterIntake(for day: Date) -> Int {
        waterIntakeByDay[dayKey(for: day)] ?? 0
    }

    func addWater(_ milliliters: Int, for day: Date) {
        let key = dayKey(for: day)
        let current = waterIntakeByDay[key] ?? 0
        let newTotal = max(0, current + milliliters)
        waterIntakeByDay[key] = newTotal
        persistWaterIntake()
        scheduleWaterIntakeSync(total: newTotal, delta: newTotal - current, for: day)
        if newTotal != current {
            Task { await syncWaterToHealthIfEnabled(for: day) }
        }
    }

    func setWaterIntake(_ milliliters: Int, for day: Date) {
        let key = dayKey(for: day)
        let clamped = max(0, milliliters)
        let previous = waterIntakeByDay[key] ?? 0
        waterIntakeByDay[key] = clamped
        persistWaterIntake()
        scheduleWaterIntakeSync(total: clamped, delta: nil, for: day)

        // Reconciled rather than topped up: the sheet can take water back off
        // the day, and an additive mirror had no way to express that.
        if clamped != previous {
            Task { await syncWaterToHealthIfEnabled(for: day) }
        }
    }

    func setDailyWaterGoal(_ milliliters: Int) {
        dailyWaterGoalMilliliters = max(0, milliliters)
        persistWaterGoal()
        HabitLocalNotificationScheduler.shared.refreshWaterReminders(isWaterTrackingEnabled: dailyWaterGoalMilliliters > 0)
        markLocalNutritionSettingsUpdatedNow()
        Task {
            await pushNutritionSettingsToRemote()
        }
    }

    /// The goal and the step, saved together in one round trip.
    ///
    /// They are edited on one screen behind one Save button, and the step lives
    /// in `AppSettings` while the goal lives here — saving them separately would
    /// mean two pushes of the same settings object, the second one racing the
    /// first and carrying whichever half of the change it happened to read.
    func setWaterPlan(goalMilliliters: Int, stepMilliliters: Int) {
        appSettings.setWaterWidgetStepMilliliters(stepMilliliters)
        dailyWaterGoalMilliliters = max(0, goalMilliliters)
        persistWaterGoal()
        persistWidgetTodaySnapshot()
        HabitLocalNotificationScheduler.shared.refreshWaterReminders(isWaterTrackingEnabled: dailyWaterGoalMilliliters > 0)
        markLocalNutritionSettingsUpdatedNow()
        Task {
            await pushNutritionSettingsToRemote()
        }
    }

    func refreshWaterStateFromSharedStorage() {
        let restoredWaterIntake = FoodDiaryService.loadWaterIntake(scopeUserID: scopeUserID)
        let restoredWaterGoal = FoodDiaryService.loadWaterGoal(scopeUserID: scopeUserID)

        guard restoredWaterIntake != waterIntakeByDay || restoredWaterGoal != dailyWaterGoalMilliliters else {
            return
        }

        let changedWaterEntries = restoredWaterIntake.filter { waterIntakeByDay[$0.key] != $0.value }
        let didChangeWaterGoal = restoredWaterGoal != dailyWaterGoalMilliliters
        waterIntakeByDay = restoredWaterIntake
        dailyWaterGoalMilliliters = restoredWaterGoal
        if didChangeWaterGoal {
            HabitLocalNotificationScheduler.shared.refreshWaterReminders(isWaterTrackingEnabled: dailyWaterGoalMilliliters > 0)
        }
        persistWidgetTodaySnapshot()
        for (day, total) in changedWaterEntries {
            scheduleWaterIntakeSync(total: total, delta: nil, dayKey: day)
        }
        if didChangeWaterGoal {
            markLocalNutritionSettingsUpdatedNow()
            Task {
                await pushNutritionSettingsToRemote()
            }
        }
    }

    func refreshWatchSnapshot() {
        persistWidgetTodaySnapshot()
    }

    func refreshActiveDayFromServer() async {
        guard authService != nil else { return }

        nutritionSettingsLoadTask?.cancel()
        nutritionSettingsLoadTask = nil
        hasLoadedRemoteNutritionSettings = false
        cachedFoodSettings = nil
        await loadMeals(for: activeDay)
    }

    func setDailyGoalOverride(_ goal: DailyNutritionGoal, for day: Date) {
        objectWillChange.send()
        let sanitized = goal.sanitized
        dailyGoalOverrides[dayKey(for: day)] = sanitized
        persistGoalOverrides()
        markLocalNutritionSettingsUpdatedNow()
        Task {
            await pushNutritionSettingsToRemote()
        }
    }

    func clearDailyGoalOverride(for day: Date) {
        objectWillChange.send()
        dailyGoalOverrides.removeValue(forKey: dayKey(for: day))
        persistGoalOverrides()
        markLocalNutritionSettingsUpdatedNow()
        Task {
            await pushNutritionSettingsToRemote()
        }
    }

    func setMealCategories(_ categories: [MealCategory]) {
        let normalized = FoodDiaryService.normalizeMealCategories(categories)
        mealCategories = normalized
        persistMealCategories()
        markLocalNutritionSettingsUpdatedNow()
        Task {
            await pushNutritionSettingsToRemote()
        }
    }

    func category(for id: String) -> MealCategory {
        if let category = visibleMealCategories.first(where: { $0.id == id }) {
            return category
        }
        return fallbackCategory(for: id, sortOrder: visibleMealCategories.count)
    }

    func latestMeal(in categoryID: String, on day: Date = .now) -> MealEntry? {
        let trimmedCategoryID = categoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCategoryID.isEmpty else { return nil }

        let resolvedCategoryID = category(for: trimmedCategoryID).id
        return storedMeals(for: day)
            .filter { normalizedCategoryID(for: $0) == resolvedCategoryID }
            .sorted(by: { $0.scheduledAt > $1.scheduledAt })
            .first
    }

    func meals(on day: Date) -> [MealEntry] {
        storedMeals(for: day)
    }

    func nutritionSummary(on day: Date) -> NutritionSummary {
        let start = Calendar.current.startOfDay(for: day)
        if Calendar.current.isDate(activeDay, inSameDayAs: start) {
            return Self.nutritionSummary(from: mealsOnDay(start))
        }
        if let cachedSummary = dailyHistory[start] {
            return cachedSummary
        }
        return Self.nutritionSummary(from: storedMeals(for: start))
    }

    func loadMealHistory(from startDay: Date, through endDay: Date) async {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDay)
        let normalizedEnd = calendar.startOfDay(for: endDay)
        guard normalizedStart <= normalizedEnd else { return }

        if authService == nil {
            for day in daysInRange(from: normalizedStart, through: normalizedEnd) {
                dailyHistory[day] = Self.nutritionSummary(from: Self.previewMeals(for: day))
            }
            return
        }

        refreshCacheScopeFromAuth()
        if dailyHistory.isEmpty {
            restoreCachedMealsIfAvailable(resetWhenMissing: false)
        }

        do {
            let mealsByDay = try await fetchMealsGroupedByDay(from: normalizedStart, through: normalizedEnd)
            mergeFetchedMealsHistory(mealsByDay, from: normalizedStart, through: normalizedEnd)
            await loadRemoteWaterIntake(from: normalizedStart, through: normalizedEnd)
            lastErrorMessage = nil
        } catch {
            if isCancellationError(error) {
                return
            }
            storeLastError(error)
        }
    }

    func meal(id: UUID, on day: Date) -> MealEntry? {
        storedMeals(for: day).first(where: { $0.id == id })
    }

    func mealGoal(for category: MealCategory, on day: Date) -> NutritionSummary {
        let resolvedGoal = goal(for: day)
        let share = max(0, Double(category.goalSharePercent)) / 100.0
        return NutritionSummary(
            calories: Int((Double(resolvedGoal.calories) * share).rounded()),
            protein: Int((Double(goalProteinGrams(for: day)) * share).rounded()),
            fat: Int((Double(goalFatGrams(for: day)) * share).rounded()),
            carbs: Int((Double(goalCarbsGrams(for: day)) * share).rounded())
        )
    }

    func historyPointsForWeek(containing day: Date, upTo maxDay: Date = .now) -> [DiaryHistoryPoint] {
        let weekStart = startOfWeek(for: day)
        guard let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) else { return [] }

        return daysInRange(from: weekStart, through: weekEnd).map { currentDay in
            let dayStart = Calendar.current.startOfDay(for: currentDay)
            let summary = dailyHistory[dayStart] ?? .zero
            let goalForDay = goal(for: dayStart)
            return DiaryHistoryPoint(
                day: dayStart,
                calories: summary.calories,
                goal: goalForDay.calories,
                hasCheatMeal: isCheatMealDay(dayStart),
                isOverride: hasGoalOverride(for: dayStart)
            )
        }
    }

    func loadHistoryForWeek(containing day: Date) async {
        let resolvedDay = Calendar.current.startOfDay(for: day)
        historyLoadGeneration += 1
        let generation = historyLoadGeneration

        if authService == nil {
            dailyHistory = FoodDiaryService.previewHistory(centeredOn: resolvedDay)
            return
        }

        refreshCacheScopeFromAuth()
        if dailyHistory.isEmpty {
            restoreCachedMealsIfAvailable(resetWhenMissing: false)
        }

        startRemoteNutritionSettingsLoadIfNeeded()

        do {
            let fetchPlan = historyFetchPlan(for: resolvedDay)
            let historyMealsByDay = try await fetchMealsGroupedByDay(from: fetchPlan.primaryStart, through: fetchPlan.primaryEnd)
            guard generation == historyLoadGeneration else { return }
            mergeFetchedMealsHistory(historyMealsByDay, from: fetchPlan.primaryStart, through: fetchPlan.primaryEnd)
            await loadRemoteWaterIntake(from: fetchPlan.primaryStart, through: fetchPlan.primaryEnd)

            if let supplementalDay = fetchPlan.supplementalDay {
                do {
                    let supplementalMealsByDay = try await fetchMealsGroupedByDay(from: supplementalDay, through: supplementalDay)
                    guard generation == historyLoadGeneration else { return }
                    mergeFetchedMealsHistory(supplementalMealsByDay, from: supplementalDay, through: supplementalDay)
                    await loadRemoteWaterIntake(from: supplementalDay, through: supplementalDay)
                } catch {
                    if isCancellationError(error) {
                        return
                    }
                }
            }

            lastErrorMessage = nil
        } catch {
            guard generation == historyLoadGeneration else { return }
            if isCancellationError(error) {
                return
            }
            storeLastError(error)
        }
    }

    func cachedNutritionStatistics(period: NutritionStatsPeriod, anchor: Date) -> NutritionStatisticsSnapshot? {
        let resolvedAnchor = Calendar.current.startOfDay(for: anchor)

        if authService == nil {
            return adjustedNutritionStatisticsSnapshot(previewNutritionStatistics(period: period, anchor: resolvedAnchor))
        }

        if let cachedSnapshot = Self.loadNutritionStatisticsCache(
            scopeID: cacheScopeID,
            period: period,
            anchor: resolvedAnchor
        ) {
            return adjustedNutritionStatisticsSnapshot(cachedSnapshot)
        }

        return localNutritionStatisticsSnapshot(period: period, anchor: resolvedAnchor)
            .map(adjustedNutritionStatisticsSnapshot)
    }

    func warmUpNutritionStatistics(anchor: Date = .now) async {
        let resolvedAnchor = Calendar.current.startOfDay(for: anchor)
        let previousAnchor = Calendar.current.date(byAdding: .day, value: -7, to: resolvedAnchor)
            ?? resolvedAnchor

        async let currentSnapshot: NutritionStatisticsSnapshot? = loadNutritionStatistics(period: .week, anchor: resolvedAnchor)
        async let previousSnapshot: NutritionStatisticsSnapshot? = loadNutritionStatistics(period: .week, anchor: previousAnchor)
        _ = await (currentSnapshot, previousSnapshot)
    }

    func loadNutritionStatistics(period: NutritionStatsPeriod, anchor: Date) async -> NutritionStatisticsSnapshot? {
        let resolvedAnchor = Calendar.current.startOfDay(for: anchor)

        if authService == nil {
            return adjustedNutritionStatisticsSnapshot(previewNutritionStatistics(period: period, anchor: resolvedAnchor))
        }

        await ensureRemoteNutritionSettingsLoaded()

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetNutritionStatisticsRequest()
                request.period = grpcStatisticsPeriod(from: period)
                request.anchorAt = Google_Protobuf_Timestamp(date: resolvedAnchor)
                request.timezoneOffsetMinutes = Int32(TimeZone.current.secondsFromGMT(for: resolvedAnchor) / 60)
                return try await withFoodClient { client in
                    try await client.getNutritionStatistics(request, metadata: metadata)
                }
            }
            let snapshot = adjustedNutritionStatisticsSnapshot(mapNutritionStatistics(response))
            saveNutritionStatisticsCache(snapshot, period: period, anchor: resolvedAnchor)
            lastErrorMessage = nil
            return snapshot
        } catch {
            storeLastError(error)
            return cachedNutritionStatistics(period: period, anchor: resolvedAnchor)
        }
    }

    func loadNutritionAchievements(anchor: Date) async -> NutritionAchievementsSnapshot? {
        let resolvedAnchor = Calendar.current.startOfDay(for: anchor)

        if authService == nil {
            return previewNutritionAchievements(anchor: resolvedAnchor)
        }

        await ensureRemoteNutritionSettingsLoaded()

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetNutritionAchievementsRequest()
                request.anchorAt = Google_Protobuf_Timestamp(date: resolvedAnchor)
                request.timezoneOffsetMinutes = Int32(TimeZone.current.secondsFromGMT(for: resolvedAnchor) / 60)
                return try await withFoodClient { client in
                    try await client.getNutritionAchievements(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return mapNutritionAchievements(response)
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func loadMeals(for day: Date = .now) async {
        let resolvedDay = Calendar.current.startOfDay(for: day)
        mealsLoadGeneration += 1
        let generation = mealsLoadGeneration
        activeDay = resolvedDay

        if authService == nil {
            guard generation == mealsLoadGeneration else { return }
            meals = FoodDiaryService.previewMeals(for: resolvedDay).sorted(by: { $0.scheduledAt < $1.scheduledAt })
            registerHistory(for: resolvedDay, meals: meals)
            dailyHistory = FoodDiaryService.previewHistory(centeredOn: resolvedDay, selectedDayMeals: meals)
            return
        }

        refreshCacheScopeFromAuth()
        restoreCachedMeals(for: resolvedDay)

        isLoading = true
        defer { isLoading = false }

        do {
            startRemoteNutritionSettingsLoadIfNeeded()
            let fetchPlan = historyFetchPlan(for: resolvedDay)
            let historyMealsByDay = try await fetchMealsGroupedByDay(from: fetchPlan.primaryStart, through: fetchPlan.primaryEnd)
            guard generation == mealsLoadGeneration, activeDay == resolvedDay else { return }
            meals = historyMealsByDay[resolvedDay] ?? []
            mergeFetchedMealsHistory(historyMealsByDay, from: fetchPlan.primaryStart, through: fetchPlan.primaryEnd)
            await loadRemoteWaterIntake(from: fetchPlan.primaryStart, through: fetchPlan.primaryEnd)

            if let supplementalDay = fetchPlan.supplementalDay {
                do {
                    let supplementalMealsByDay = try await fetchMealsGroupedByDay(from: supplementalDay, through: supplementalDay)
                    guard generation == mealsLoadGeneration, activeDay == resolvedDay else { return }
                    mergeFetchedMealsHistory(supplementalMealsByDay, from: supplementalDay, through: supplementalDay)
                    await loadRemoteWaterIntake(from: supplementalDay, through: supplementalDay)
                } catch {
                    if isCancellationError(error) {
                        return
                    }
                }
            }

            lastErrorMessage = nil
        } catch {
            guard generation == mealsLoadGeneration else { return }
            if authService?.isAuthenticated == false {
                meals = []
            }
            storeLastError(error)
        }
    }

    func saveMeal(_ meal: MealEntry) async -> Bool {
        let assignedCategoryID = normalizedCategoryID(for: meal)
        // Read before the write, so a meal moved to another date can be taken
        // off the day it came from.
        let previousDay = storedMealRecord(id: meal.id)?.day
        guard authService != nil else {
            var updatedMeal = meal
            updatedMeal.mealCategoryID = assignedCategoryID
            replaceMeal(with: updatedMeal)
            persistMealCategoryAssignment(mealID: updatedMeal.id, categoryID: assignedCategoryID)
            registerHistory(
                for: Calendar.current.startOfDay(for: updatedMeal.scheduledAt),
                meals: mergedMealsForHistoryUpdate(with: updatedMeal)
            )
            detachMeal(id: updatedMeal.id, movedFrom: previousDay, to: updatedMeal.scheduledAt)
            return true
        }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_LogMealRequest()
                var payload = Food_Meal()
                payload.id = meal.id.uuidString
                payload.title = meal.title.trimmingCharacters(in: .whitespacesAndNewlines)
                payload.note = serializedMealNote(for: meal)
                payload.eatenAt = Google_Protobuf_Timestamp(date: meal.scheduledAt)
                payload.items = try await materializeItems(from: meal.items, metadata: metadata)
                payload.totals = nutritionFacts(from: meal.nutrition)
                request.meal = payload

                return try await withFoodClient { client in
                    try await client.logMeal(request, metadata: metadata)
                }
            }

            await prefetchMissingCatalogItems(from: [response.meal])
            var entry = hydratedMealEntry(mapMeal(response.meal), fallback: meal)
            entry.mealCategoryID = assignedCategoryID
            replaceMeal(with: entry)
            persistMealCategoryAssignment(mealID: entry.id, categoryID: assignedCategoryID)
            registerHistory(
                for: Calendar.current.startOfDay(for: entry.scheduledAt),
                meals: mergedMealsForHistoryUpdate(with: entry)
            )
            detachMeal(id: entry.id, movedFrom: previousDay, to: entry.scheduledAt)
            lastErrorMessage = nil
            return true
        } catch {
            storeLastError(error)
            return false
        }
    }

    func loadMealDetails(id: UUID, fallback: MealEntry? = nil) async -> MealEntry? {
        let localFallback = fallback ?? mealForNavigation(id: id)
        guard authService != nil else { return localFallback }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetMealRequest()
                request.mealID = id.uuidString
                return try await withFoodClient { client in
                    try await client.getMeal(request, metadata: metadata)
                }
            }

            await prefetchMissingCatalogItems(from: [response.meal])
            var entry = hydratedMealEntry(mapMeal(response.meal), fallback: localFallback)
            if let localFallback {
                entry.mealCategoryID = normalizedCategoryID(for: localFallback)
            }
            replaceMeal(with: entry)
            persistMealCategoryAssignment(mealID: entry.id, categoryID: normalizedCategoryID(for: entry))
            registerHistory(
                for: Calendar.current.startOfDay(for: entry.scheduledAt),
                meals: mergedMealsForHistoryUpdate(with: entry)
            )
            lastErrorMessage = nil
            return entry
        } catch {
            if !isCancellationError(error) {
                storeLastError(error)
            }
            return localFallback
        }
    }

    private func resetMealShareCache() {
        mealShareTasks.values.forEach { $0.cancel() }
        mealShareTasks = [:]
        mealSharePayloads = [:]
    }

    private func refreshCacheScopeFromAuth() {
        let resolvedCacheScope = FoodDiaryService.normalizeCacheScope(authService?.currentUsername)
        guard resolvedCacheScope != cacheScopeID else { return }
        cacheScopeID = resolvedCacheScope
        mealCacheSnapshot = nil
        hasLoadedMealCacheSnapshot = false
        resetMealShareCache()
    }

    func shareMeal(id: UUID) async -> FoodSharePayload? {
        if let payload = mealSharePayloads[id] {
            return payload
        }
        if let task = mealShareTasks[id] {
            return await task.value
        }

        let scopeID = cacheScopeID
        let task: Task<FoodSharePayload?, Never> = Task { [weak self] in
            guard let self else { return nil }
            let payload = await self.fetchMealSharePayload(id: id)
            guard !Task.isCancelled, self.cacheScopeID == scopeID else { return payload }
            if let payload {
                self.mealSharePayloads[id] = payload
            }
            self.mealShareTasks[id] = nil
            return payload
        }
        mealShareTasks[id] = task
        return await task.value
    }

    private func fetchMealSharePayload(id: UUID) async -> FoodSharePayload? {
        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ShareMealRequest()
                request.mealID = id.uuidString
                return try await withFoodClient { client in
                    try await client.shareMeal(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return FoodSharePayload(
                title: meal(id: id)?.title ?? NSLocalizedString("meal.custom_default", comment: "Default meal title"),
                shareCode: response.shareCode,
                shareURL: response.shareURL
            )
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func deleteMeal(id: UUID) async -> Bool {
        let mealRecord = storedMealRecord(id: id)

        guard authService != nil else {
            guard let mealRecord else { return false }
            applyMealDeletion(id: id, on: mealRecord.day)
            mealSharePayloads.removeValue(forKey: id)
            mealShareTasks[id]?.cancel()
            mealShareTasks.removeValue(forKey: id)
            lastErrorMessage = nil
            return true
        }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_DeleteMealRequest()
                request.mealID = id.uuidString
                return try await withFoodClient { client in
                    try await client.deleteMeal(request, metadata: metadata)
                }
            }
            if response.success {
                applyMealDeletion(id: id, on: mealRecord?.day)
                mealSharePayloads.removeValue(forKey: id)
                mealShareTasks[id]?.cancel()
                mealShareTasks.removeValue(forKey: id)
            }
            lastErrorMessage = nil
            return response.success
        } catch {
            storeLastError(error)
            return false
        }
    }

    func previewSharedMeal(code: String) async -> MealEntry? {
        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetSharedMealRequest()
                request.shareCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                return try await withFoodClient { client in
                    try await client.getSharedMeal(request, metadata: metadata)
                }
            }
            await prefetchMissingCatalogItems(from: [response.meal])
            lastErrorMessage = nil
            return mapMeal(response.meal)
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func importSharedMeal(code: String, scheduledAt: Date? = nil, mealCategoryID: String? = nil) async -> MealEntry? {
        guard authService != nil else { return nil }
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        lastSharedMealImportAlreadyExists = false

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_SaveSharedMealRequest()
                request.shareCode = normalizedCode
                return try await withFoodClient { client in
                    try await client.saveSharedMeal(request, metadata: metadata)
                }
            }
            await prefetchMissingCatalogItems(from: [response.meal])
            var entry = mapMeal(response.meal)
            if requiresLinkedItemHydration(entry) {
                let preview = await previewSharedMeal(code: normalizedCode)
                entry = hydratedMealEntry(entry, fallback: preview)
            }
            let targetScheduledAt = scheduledAt ?? entry.scheduledAt
            if let mealCategoryID {
                entry.mealCategoryID = mealCategoryID
            }
            let assignedCategoryID = normalizedCategoryID(for: entry)

            if abs(entry.scheduledAt.timeIntervalSince(targetScheduledAt)) > 0.5 {
                entry.scheduledAt = targetScheduledAt
                entry.mealCategoryID = assignedCategoryID
                let isSaved = await saveMeal(entry)
                guard isSaved else { return nil }
                lastErrorMessage = nil
                return meal(id: entry.id) ?? entry
            }

            entry.scheduledAt = targetScheduledAt
            entry.mealCategoryID = assignedCategoryID
            replaceMeal(with: entry)
            persistMealCategoryAssignment(mealID: entry.id, categoryID: assignedCategoryID)
            registerHistory(
                for: Calendar.current.startOfDay(for: entry.scheduledAt),
                meals: mergedMealsForHistoryUpdate(with: entry)
            )
            markSharedMealImported(code: normalizedCode)
            lastErrorMessage = nil
            return entry
        } catch let error as RPCError {
            if error.code == .alreadyExists {
                lastSharedMealImportAlreadyExists = true
                markSharedMealImported(code: normalizedCode)
                lastErrorMessage = NSLocalizedString(
                    "meal.import.already_exists",
                    tableName: nil,
                    bundle: .main,
                    value: "You already have this meal.",
                    comment: "Shared meal already imported"
                )
            } else {
                storeLastError(error)
            }
            return nil
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func isKnownImportedSharedMeal(code: String, preview: MealEntry?) -> Bool {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if knownImportedMealShareCodes().contains(normalizedCode) {
            return true
        }

        guard let preview else { return false }
        return meal(id: preview.id) != nil || storedMealRecord(id: preview.id) != nil
    }

    func meal(id: UUID) -> MealEntry? {
        meals.first(where: { $0.id == id })
    }

    func mealForNavigation(id: UUID) -> MealEntry? {
        meal(id: id) ?? storedMealRecord(id: id)?.meal
    }

    @discardableResult
    func removeMealItem(mealID: UUID, itemID: UUID, on day: Date = .now) async -> Bool {
        guard var meal = meal(id: mealID, on: day) ?? storedMealRecord(id: mealID)?.meal else {
            return false
        }

        let originalCount = meal.items.count
        meal.items.removeAll(where: { $0.id == itemID })
        guard meal.items.count != originalCount else { return false }

        meal.nutrition = .zero
        if meal.items.isEmpty {
            return await deleteMeal(id: mealID)
        }

        return await saveMeal(meal)
    }

    func clear() {
        nutritionSettingsLoadTask?.cancel()
        nutritionSettingsLoadTask = nil
        cachedFoodSettings = nil
        mealCacheSnapshot = nil
        hasLoadedMealCacheSnapshot = false
        meals = []
        lastErrorMessage = nil
        shouldShowCalorieOnboarding = false
        hasResolvedCalorieOnboardingState = false
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func setDailyGoal(_ goal: DailyNutritionGoal) {
        let sanitized = goal.sanitized
        dailyGoal = sanitized
        persistDailyGoal()
        markLocalNutritionSettingsUpdatedNow()
        Task {
            await pushNutritionSettingsToRemote()
        }
    }

    func applyOnboardingNutritionSetup(goal: DailyNutritionGoal, mealCategories categories: [MealCategory]) async {
        let sanitizedGoal = goal.sanitized
        let normalizedCategories = FoodDiaryService.normalizeMealCategories(categories.isEmpty ? MealCategory.default : categories)
        dailyGoal = sanitizedGoal
        mealCategories = normalizedCategories
        persistDailyGoal()
        persistMealCategories()
        markLocalNutritionSettingsUpdatedNow()
        await pushNutritionSettingsToRemote()
    }

    func setDietPlan(_ plan: DietPlanOption) {
        dietPlan = plan
        dailyGoal = plan.applying(to: dailyGoal)
        persistDietPlan()
        persistDailyGoal()
        markLocalNutritionSettingsUpdatedNow()
        Task {
            await pushNutritionSettingsToRemote()
        }
    }

    var goalProteinGrams: Int {
        goalProteinGrams(for: activeDay)
    }

    var goalFatGrams: Int {
        goalFatGrams(for: activeDay)
    }

    var goalCarbsGrams: Int {
        goalCarbsGrams(for: activeDay)
    }

    func goalProteinGrams(for day: Date) -> Int {
        let resolvedGoal = goal(for: day)
        return Int((Double(resolvedGoal.calories) * Double(resolvedGoal.proteinPercent) / 100.0 / 4.0).rounded())
    }

    func goalFatGrams(for day: Date) -> Int {
        let resolvedGoal = goal(for: day)
        return Int((Double(resolvedGoal.calories) * Double(resolvedGoal.fatPercent) / 100.0 / 9.0).rounded())
    }

    func goalCarbsGrams(for day: Date) -> Int {
        let resolvedGoal = goal(for: day)
        return Int((Double(resolvedGoal.calories) * Double(resolvedGoal.carbsPercent) / 100.0 / 4.0).rounded())
    }

    private func replaceMeal(with meal: MealEntry) {
        let mealDay = Calendar.current.startOfDay(for: meal.scheduledAt)
        let activeDay = Calendar.current.startOfDay(for: activeDay)

        if let index = meals.firstIndex(where: { $0.id == meal.id }) {
            if activeDay == mealDay {
                meals[index] = meal
            } else {
                meals.remove(at: index)
            }
        } else if activeDay == mealDay {
            meals.append(meal)
        }
        meals.sort(by: { $0.scheduledAt < $1.scheduledAt })
    }

    /// Takes a meal off the day it used to be on.
    ///
    /// Saving writes the day the meal is now on. Moving one to another date left
    /// the old day still holding it: invisible while the reader is looking at
    /// today, but wrong in the history, in the totals, and — since the day is
    /// what gets mirrored — in Health.
    private func detachMeal(id: UUID, movedFrom previousDay: Date?, to newDay: Date) {
        let calendar = Calendar.current
        guard let previousDay, !calendar.isDate(previousDay, inSameDayAs: newDay) else { return }

        // Only rewrite a day the meal is actually filed under. `storedMealRecord`
        // derives the day from the meal's own timestamp, while this reads the
        // bucket by key; when the two disagree — a timezone change since the
        // cache was written, say — rewriting would zero a day that still has
        // meals in it and leave the stale one where it was.
        let stored = storedMeals(for: previousDay)
        guard stored.contains(where: { $0.id == id }) else { return }

        let remaining = stored
            .filter { $0.id != id }
            .sorted(by: { $0.scheduledAt < $1.scheduledAt })

        if calendar.isDate(activeDay, inSameDayAs: previousDay) {
            meals = remaining
        }
        registerHistory(for: previousDay, meals: remaining)
        // Mirrored here rather than at the one call site that knew about moves,
        // so a meal moved by an import or an item removal also leaves the old
        // day's calories behind in Health.
        Task { await syncNutritionToHealthIfEnabled(for: previousDay) }
    }

    private func mergedMealsForHistoryUpdate(with meal: MealEntry) -> [MealEntry] {
        let day = Calendar.current.startOfDay(for: meal.scheduledAt)
        var dayMeals: [MealEntry]

        if Calendar.current.isDate(activeDay, inSameDayAs: day) {
            dayMeals = mealsOnDay(day)
        } else {
            dayMeals = Self.cachedMeals(for: day, from: loadedMealCacheSnapshot())
        }

        if let index = dayMeals.firstIndex(where: { $0.id == meal.id }) {
            dayMeals[index] = meal
        } else {
            dayMeals.append(meal)
        }

        return dayMeals.sorted(by: { $0.scheduledAt < $1.scheduledAt })
    }

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
            throw NSError(domain: "FoodDiaryService", code: 401, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("food.service.auth_failed", comment: "Food service authorization failed")])
        }

        do {
            return try await authService.withAuthorizedMetadata(operation)
        } catch {
            if authService.shouldRetryAuthorizedRequest(after: error) {
                storeLastError(NSError(domain: "FoodDiaryService", code: 401, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("food.service.auth_refresh_failed", comment: "Food service token refresh failed")]))
            }
            throw error
        }
    }

    private func withUserClient<T>(
        _ body: (User_UserService.Client<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T where T: Sendable {
        guard let authService else {
            throw NSError(domain: "FoodDiaryService", code: 401, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("food.service.auth_failed", comment: "Food service authorization failed")])
        }

        return try await authService.withUserClient(body)
    }

    func updateEatometerProfile(
        heightCentimeters: Int,
        weightKilograms: Int,
        ageYears: Int,
        biologicalSex: EatometerBiologicalSex,
        activityLevel: String,
        goal: String,
        sourceUpdatedAt: Date = Date()
    ) async {
        guard authService != nil else { return }

        do {
            var request = User_UpdateEatometerHealthProfileRequest()
            request.heightCentimeters = Double(heightCentimeters)
            request.weightKilograms = Double(weightKilograms)
            request.ageYears = Int32(ageYears)
            request.sex = userSex(from: biologicalSex)
            request.activityLevel = activityLevel
            request.goal = goal
            request.sourceUpdatedAt = Google_Protobuf_Timestamp(date: sourceUpdatedAt)

            _ = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    try await client.updateEatometerHealthProfile(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
        } catch {
            if isCancellationError(error) {
                return
            }
            storeLastError(error)
        }
    }

    private func userSex(from value: EatometerBiologicalSex) -> User_UserSex {
        switch value {
        case .male:
            return .male
        case .female:
            return .female
        case .other:
            return .preferNotToSay
        case .notSet:
            return .unspecified
        }
    }

    private func ensureRemoteNutritionSettingsLoaded() async {
        guard authService != nil else { return }
        guard !hasLoadedRemoteNutritionSettings else { return }

        if let nutritionSettingsLoadTask {
            await nutritionSettingsLoadTask.value
            return
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.loadRemoteNutritionSettingsIfNeeded()
        }
        nutritionSettingsLoadTask = task
        await task.value
    }

    private func startRemoteNutritionSettingsLoadIfNeeded() {
        guard authService != nil else { return }
        guard !hasLoadedRemoteNutritionSettings else { return }
        guard nutritionSettingsLoadTask == nil else { return }

        nutritionSettingsLoadTask = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.loadRemoteNutritionSettingsIfNeeded()
        }
    }

    private func loadRemoteNutritionSettingsIfNeeded() async {
        defer { nutritionSettingsLoadTask = nil }
        guard authService != nil else { return }
        guard !hasLoadedRemoteNutritionSettings else { return }

        do {
            let settings = try await fetchFoodSettings()
            let remoteUpdatedAt = nutritionSettingsUpdatedAt(from: settings)
            if let remoteUpdatedAt,
               remoteUpdatedAt >= localNutritionSettingsUpdatedAt {
                applyFoodSettings(settings)
                localNutritionSettingsUpdatedAt = remoteUpdatedAt
                persistNutritionSettingsUpdatedAt()
                hasLoadedRemoteNutritionSettings = true
                lastErrorMessage = nil
            } else {
                cachedFoodSettings = settings
                mealRemindersEnabled = settings.mealRemindersEnabled
                usefulNotificationsEnabled = settings.usefulNotificationsEnabled
                habitNotificationsEnabled = settings.habitNotificationsEnabled
                waterLoggingRemindersEnabled = settings.waterLoggingRemindersEnabled
                healthSyncEnabled = settings.healthSyncEnabled
                HabitNotificationPreferences.shared.apply(
                    habitNotificationsEnabled: habitNotificationsEnabled,
                    waterLoggingRemindersEnabled: waterLoggingRemindersEnabled
                )
                updateCalorieOnboardingVisibility(from: settings)
                hasLoadedRemoteNutritionSettings = true
                await pushNutritionSettingsToRemote()
            }
        } catch {
            if isCancellationError(error) {
                return
            }
            hasResolvedCalorieOnboardingState = true
            storeLastError(error)
        }
    }

    private func pushNutritionSettingsToRemote() async {
        guard authService != nil else { return }

        do {
            let localNutritionSettings = makeNutritionSettingsPayload()
            if cachedFoodSettings == nil {
                cachedFoodSettings = try await fetchFoodSettings()
            }

            var request = User_UpdateEatometerSettingsRequest()
            request.theme = "system"
            request.listSort = appSettings.listSort.rawValue
            request.nutritionSettings = localNutritionSettings
            request.mealRemindersEnabled = mealRemindersEnabled
            request.usefulNotificationsEnabled = usefulNotificationsEnabled
            request.habitNotificationsEnabled = habitNotificationsEnabled
            request.waterLoggingRemindersEnabled = waterLoggingRemindersEnabled
            request.healthSyncEnabled = healthSyncEnabled
            request.timezoneOffsetMinutes = Int32(TimeZone.current.secondsFromGMT() / 60)

            let updated = try await withAuthenticatedMetadata { metadata in
                try await withUserClient { client in
                    try await client.updateEatometerSettings(request, metadata: metadata)
                }
            }

            // Keep local nutrition settings authoritative after a user edit.
            // Some backends may return stale nutrition_settings immediately after update,
            // which causes visible flicker/revert in the client state.
            var mergedSettings = updated
            mergedSettings.nutritionSettings = localNutritionSettings
            cachedFoodSettings = mergedSettings
            hasLoadedRemoteNutritionSettings = true
            if let remoteUpdatedAt = nutritionSettingsUpdatedAt(from: updated) {
                localNutritionSettingsUpdatedAt = remoteUpdatedAt
            } else {
                localNutritionSettingsUpdatedAt = Date()
            }
            persistNutritionSettingsUpdatedAt()
            lastErrorMessage = nil
        } catch {
            storeLastError(error)
        }
    }

    private func nutritionSettingsUpdatedAt(from settings: User_EatometerSettings) -> Date? {
        guard settings.hasNutritionSettings, settings.nutritionSettings.hasUpdatedAt else {
            return nil
        }
        return date(from: settings.nutritionSettings.updatedAt)
    }

    private func fetchFoodSettings() async throws -> User_EatometerSettings {
        try await withAuthenticatedMetadata { metadata in
            let request = User_GetEatometerSettingsRequest()
            return try await withUserClient { client in
                try await client.getEatometerSettings(request, metadata: metadata)
            }
        }
    }

    private func loadRemoteWaterIntake(from startDay: Date, through endDay: Date) async {
        guard authService != nil else { return }

        do {
            let entries = try await fetchRemoteWaterIntakes(from: startDay, through: endDay)
            applyRemoteWaterIntakes(entries, from: startDay, through: endDay)
        } catch {
            if isCancellationError(error) {
                return
            }
            storeLastError(error)
        }
    }

    private func fetchRemoteWaterIntakes(from startDay: Date, through endDay: Date) async throws -> [Food_WaterIntake] {
        try await withAuthenticatedMetadata { metadata in
            var request = Food_ListWaterIntakesRequest()
            request.startDay = dayKey(for: startDay)
            request.endDay = dayKey(for: endDay)
            return try await withFoodClient { client in
                let response = try await client.listWaterIntakes(request, metadata: metadata)
                return response.entries
            }
        }
    }

    private func scheduleWaterIntakeSync(total: Int, delta: Int?, for day: Date) {
        scheduleWaterIntakeSync(total: total, delta: delta, dayKey: dayKey(for: day))
    }

    private func scheduleWaterIntakeSync(total: Int, delta: Int?, dayKey: String) {
        guard authService != nil else { return }

        Task {
            if let delta, delta > 0 {
                await pushWaterIntakeDelta(delta, dayKey: dayKey)
            } else {
                await pushWaterIntakeTotal(total, dayKey: dayKey)
            }
        }
    }

    private func pushWaterIntakeDelta(_ milliliters: Int, dayKey: String) async {
        guard milliliters > 0 else { return }

        do {
            var request = Food_AddWaterIntakeRequest()
            request.day = dayKey
            request.milliliters = clampedInt32(milliliters)
            let response = try await withAuthenticatedMetadata { metadata in
                try await withFoodClient { client in
                    try await client.addWaterIntake(request, metadata: metadata)
                }
            }
            if response.hasEntry {
                applyRemoteWaterIntakeEntry(response.entry)
            }
            lastErrorMessage = nil
        } catch {
            storeLastError(error)
        }
    }

    private func pushWaterIntakeTotal(_ milliliters: Int, dayKey: String) async {
        do {
            var request = Food_SetWaterIntakeRequest()
            request.day = dayKey
            request.milliliters = clampedInt32(milliliters)
            let response = try await withAuthenticatedMetadata { metadata in
                try await withFoodClient { client in
                    try await client.setWaterIntake(request, metadata: metadata)
                }
            }
            if response.hasEntry {
                applyRemoteWaterIntakeEntry(response.entry)
            }
            lastErrorMessage = nil
        } catch {
            storeLastError(error)
        }
    }

    private func applyRemoteWaterIntakes(_ entries: [Food_WaterIntake], from startDay: Date, through endDay: Date) {
        var updated = waterIntakeByDay
        for day in daysInRange(from: startDay, through: endDay) {
            updated.removeValue(forKey: dayKey(for: day))
        }
        for entry in entries {
            guard let day = FoodDiaryService.normalizedDayKey(from: entry.day) else { continue }
            let total = max(0, Int(entry.milliliters))
            if total > 0 {
                updated[day] = total
            }
        }
        guard updated != waterIntakeByDay else { return }
        waterIntakeByDay = updated
        persistWaterIntake()
    }

    private func applyRemoteWaterIntakeEntry(_ entry: Food_WaterIntake) {
        guard let day = FoodDiaryService.normalizedDayKey(from: entry.day) else { return }
        let total = max(0, Int(entry.milliliters))
        if total > 0 {
            waterIntakeByDay[day] = total
        } else {
            waterIntakeByDay.removeValue(forKey: day)
        }
        persistWaterIntake()
    }

    private func clampedInt32(_ value: Int) -> Int32 {
        Int32(max(0, min(value, Int(Int32.max))))
    }

    private func applyFoodSettings(_ settings: User_EatometerSettings) {
        cachedFoodSettings = settings
        mealRemindersEnabled = settings.mealRemindersEnabled
        usefulNotificationsEnabled = settings.usefulNotificationsEnabled
        habitNotificationsEnabled = settings.habitNotificationsEnabled
        waterLoggingRemindersEnabled = settings.waterLoggingRemindersEnabled
        healthSyncEnabled = settings.healthSyncEnabled
        HabitNotificationPreferences.shared.apply(
            habitNotificationsEnabled: habitNotificationsEnabled,
            waterLoggingRemindersEnabled: waterLoggingRemindersEnabled
        )
        HabitLocalNotificationScheduler.shared.refreshWaterReminders(isWaterTrackingEnabled: dailyWaterGoalMilliliters > 0)
        appSettings.applyFromRemote(listSort: settings.listSort)
        updateCalorieOnboardingVisibility(from: settings)
        guard settings.hasNutritionSettings else { return }

        let nutritionSettings = settings.nutritionSettings
        dietPlan = DietPlanOption.normalized(rawValue: nutritionSettings.dietPlan)
        persistDietPlan()
        // Backend persists meal slots, cheat-day flags, and default goal as source of truth.
        // Goal values are still applied from remote only when nutrition settings are authoritative.
        if nutritionSettings.hasDefaultGoal {
            dailyGoal = mapDailyGoal(nutritionSettings.defaultGoal)
            persistDailyGoal()
        }
        mealCategories = FoodDiaryService.normalizeMealCategories(nutritionSettings.mealSlots.map(mapMealCategory))
        cheatMealDays = Set(nutritionSettings.cheatMealDays.compactMap(FoodDiaryService.normalizedDayKey(from:)))

        if nutritionSettings.waterGoalMilliliters > 0 {
            dailyWaterGoalMilliliters = Int(nutritionSettings.waterGoalMilliliters)
            persistWaterGoal()
        }
        // Zero means an older client that never sent one; leaving the local
        // value alone is better than resetting a deliberate choice to nothing.
        if nutritionSettings.waterStepMilliliters > 0 {
            appSettings.setWaterWidgetStepMilliliters(Int(nutritionSettings.waterStepMilliliters))
        }
        HabitLocalNotificationScheduler.shared.refreshWaterReminders(isWaterTrackingEnabled: dailyWaterGoalMilliliters > 0)

        persistMealCategories()
        persistCheatMealDays()
    }

    /// Onboarding runs once. The server flag is the cross-device source of
    /// truth; the scoped local flag keeps it hidden while an update is in flight.
    private func updateCalorieOnboardingVisibility(from settings: User_EatometerSettings) {
        let remoteCompleted = settings.hasNutritionSettings && settings.nutritionSettings.calorieOnboardingCompleted
        let locallyCompleted = FoodDiaryService.loadCalorieOnboardingCompleted(scopeUserID: scopeUserID) == true
        let isCompleted = !Self.isCalorieOnboardingPersistenceDisabled && (remoteCompleted || locallyCompleted)

        shouldShowCalorieOnboarding = !isCompleted
        hasResolvedCalorieOnboardingState = true
        persistCalorieOnboardingCompleted(isCompleted)
    }

    private func makeNutritionSettingsPayload() -> User_EatometerNutritionSettings {
        var settings = User_EatometerNutritionSettings()
        settings.defaultGoal = makeDailyGoalPayload(dailyGoal)
        settings.mealSlots = mealCategories.map(makeMealSlotPayload)
        settings.cheatMealDays = Array(cheatMealDays).sorted()
        settings.calorieOnboardingCompleted = !Self.isCalorieOnboardingPersistenceDisabled
            && ((cachedFoodSettings?.nutritionSettings.calorieOnboardingCompleted ?? false)
                || (FoodDiaryService.loadCalorieOnboardingCompleted(scopeUserID: scopeUserID) == true))
        settings.waterGoalMilliliters = Int32(dailyWaterGoalMilliliters)
        settings.waterStepMilliliters = Int32(appSettings.waterWidgetStepMilliliters)
        settings.dietPlan = dietPlan.rawValue
        return settings
    }

    func markCalorieOnboardingSeen() async {
        shouldShowCalorieOnboarding = false
        hasResolvedCalorieOnboardingState = true
        persistCalorieOnboardingCompleted(true)
        guard authService != nil else { return }

        if cachedFoodSettings == nil {
            do {
                cachedFoodSettings = try await fetchFoodSettings()
            } catch {
                storeLastError(error)
            }
        }

        guard var settings = cachedFoodSettings else { return }
        var nutritionSettings = settings.nutritionSettings
        nutritionSettings.calorieOnboardingCompleted = true
        settings.nutritionSettings = nutritionSettings
        cachedFoodSettings = settings
        await pushNutritionSettingsToRemote()
    }

    func requireCalorieOnboardingForNewAccount() {
        shouldShowCalorieOnboarding = true
        hasResolvedCalorieOnboardingState = true
        persistCalorieOnboardingCompleted(false)

        guard var settings = cachedFoodSettings else { return }
        var nutritionSettings = settings.nutritionSettings
        nutritionSettings.calorieOnboardingCompleted = false
        settings.nutritionSettings = nutritionSettings
        cachedFoodSettings = settings
    }

    func requestCaloriePlanReviewFromHealthChange() {
        // Do NOT relaunch onboarding. Fire a local notification; the review
        // window opens when the user taps it (handled via the deep link).
        HabitLocalNotificationScheduler.shared.scheduleCaloriePlanReviewNotification()
    }

    /// User accepted the suggestion: open the calorie plan editor (onboarding
    /// flow) so a new target can be computed. Deferred so the review sheet can
    /// finish dismissing before the editor is presented.
    func startCaloriePlanUpdateFromReview() {
        shouldShowCaloriePlanReview = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            shouldShowCalorieOnboarding = true
            hasResolvedCalorieOnboardingState = true
            persistCalorieOnboardingCompleted(false)
        }
    }

    /// User declined the suggestion. It won't reappear until the weight signature
    /// changes again (the caller records the current profile signature).
    func dismissCaloriePlanReview() {
        shouldShowCaloriePlanReview = false
    }

    func setMealRemindersEnabled(_ enabled: Bool) async {
        mealRemindersEnabled = enabled
        if var settings = cachedFoodSettings {
            settings.mealRemindersEnabled = enabled
            cachedFoodSettings = settings
        }
        await pushNutritionSettingsToRemote()
    }

    func setUsefulNotificationsEnabled(_ enabled: Bool) async {
        usefulNotificationsEnabled = enabled
        if var settings = cachedFoodSettings {
            settings.usefulNotificationsEnabled = enabled
            cachedFoodSettings = settings
        }
        await pushNutritionSettingsToRemote()
    }

    func setHabitNotificationsEnabled(_ enabled: Bool) async {
        habitNotificationsEnabled = enabled
        HabitNotificationPreferences.shared.setHabitNotificationsEnabled(enabled)
        if var settings = cachedFoodSettings {
            settings.habitNotificationsEnabled = enabled
            cachedFoodSettings = settings
        }
        await pushNutritionSettingsToRemote()
    }

    func setWaterLoggingRemindersEnabled(_ enabled: Bool) async {
        waterLoggingRemindersEnabled = enabled
        HabitNotificationPreferences.shared.setWaterLoggingRemindersEnabled(enabled)
        HabitLocalNotificationScheduler.shared.refreshWaterReminders(isWaterTrackingEnabled: dailyWaterGoalMilliliters > 0)
        if var settings = cachedFoodSettings {
            settings.waterLoggingRemindersEnabled = enabled
            cachedFoodSettings = settings
        }
        await pushNutritionSettingsToRemote()
    }

    /// Turning the switch on asks HealthKit for permission first; if the request
    /// cannot even be shown (simulator, unsupported device) the switch stays off.
    func setHealthSyncEnabled(_ enabled: Bool) async {
        var resolved = enabled

        if enabled {
            resolved = await HealthKitService.shared.requestAuthorization()
        }

        healthSyncEnabled = resolved
        if var settings = cachedFoodSettings {
            settings.healthSyncEnabled = resolved
            cachedFoodSettings = settings
        }

        await pushNutritionSettingsToRemote()
    }

    /// Makes the Health app agree with the diary for one day.
    ///
    /// Called after anything that changes a day — a meal saved, edited or
    /// deleted — rather than after additions only. The day's totals are the
    /// truth and are stated as such, so removing a meal removes its calories
    /// from Health instead of leaving them behind. That includes a hand-typed
    /// entry, which is a meal item like any other as far as the day is
    /// concerned.
    ///
    /// Deliberately not called on a plain refresh: reconciling means deleting
    /// and rewriting, and doing that every time the diary loads would churn
    /// Health for no change.
    func syncNutritionToHealthIfEnabled(for day: Date) async {
        guard healthSyncEnabled else { return }
        let summary = nutritionSummary(on: day)
        await HealthKitService.shared.replaceNutrition(
            on: day,
            calories: summary.calories,
            protein: summary.protein,
            carbs: summary.carbs,
            fat: summary.fat
        )
    }

    func syncWaterToHealthIfEnabled(for day: Date) async {
        guard healthSyncEnabled else { return }
        await HealthKitService.shared.replaceWater(on: day, milliliters: waterIntake(for: day))
    }

    func pushAppSettingsToRemote() async {
        await pushNutritionSettingsToRemote()
    }

    private func makeDailyGoalPayload(_ goal: DailyNutritionGoal) -> User_EatometerDailyNutritionGoal {
        let sanitized = goal.sanitized
        var payload = User_EatometerDailyNutritionGoal()
        payload.calories = Int32(sanitized.calories)
        payload.proteinPercent = Int32(sanitized.proteinPercent)
        payload.fatPercent = Int32(sanitized.fatPercent)
        payload.carbsPercent = Int32(sanitized.carbsPercent)
        return payload
    }

    private func makeMealSlotPayload(_ category: MealCategory) -> User_EatometerMealSlot {
        var payload = User_EatometerMealSlot()
        payload.id = category.id
        payload.title = category.title
        payload.symbolName = category.symbolName
        payload.sortOrder = Int32(category.sortOrder)
        payload.isEnabled = category.isEnabled
        payload.preferredHour = Int32(category.preferredHour)
        payload.preferredMinute = Int32(category.preferredMinute)
        payload.goalSharePercent = Int32(category.goalSharePercent)
        return payload
    }

    private func mapDailyGoal(_ goal: User_EatometerDailyNutritionGoal) -> DailyNutritionGoal {
        DailyNutritionGoal(
            calories: Int(goal.calories),
            proteinPercent: Int(goal.proteinPercent),
            fatPercent: Int(goal.fatPercent),
            carbsPercent: Int(goal.carbsPercent)
        ).sanitized
    }

    private func mapDailyGoal(_ goal: Food_DailyNutritionGoal) -> DailyNutritionGoal {
        DailyNutritionGoal(
            calories: Int(goal.calories),
            proteinPercent: Int(goal.proteinPercent),
            fatPercent: Int(goal.fatPercent),
            carbsPercent: Int(goal.carbsPercent)
        ).sanitized
    }

    private func mapMealCategory(_ slot: User_EatometerMealSlot) -> MealCategory {
        MealCategory(
            id: slot.id,
            title: slot.title,
            symbolName: slot.symbolName,
            sortOrder: Int(slot.sortOrder),
            isEnabled: slot.isEnabled,
            preferredHour: Int(slot.preferredHour),
            preferredMinute: Int(slot.preferredMinute),
            goalSharePercent: Int(slot.goalSharePercent)
        ).normalized
    }

    private func grpcStatisticsPeriod(from period: NutritionStatsPeriod) -> Food_NutritionStatisticsPeriod {
        switch period {
        case .day:
            return .day
        case .week:
            return .week
        case .month:
            return .month
        case .halfYear:
            return .halfYear
        case .year:
            return .year
        }
    }

    private func mapNutritionStatistics(_ response: Food_NutritionStatisticsResponse) -> NutritionStatisticsSnapshot {
        NutritionStatisticsSnapshot(
            period: mapNutritionStatsPeriod(response.period),
            periodStart: response.hasPeriodStart ? date(from: response.periodStart) : Date(),
            periodEnd: response.hasPeriodEnd ? date(from: response.periodEnd) : Date(),
            selectedAt: response.hasSelectedAt ? date(from: response.selectedAt) : Date(),
            summary: NutritionStatisticsSummary(
                total: response.summary.hasTotal ? nutritionSummary(from: response.summary.total) : .zero,
                averagePerDay: response.summary.hasAveragePerDay ? nutritionSummary(from: response.summary.averagePerDay) : .zero,
                totalDays: Int(response.summary.totalDays),
                recordedDays: Int(response.summary.recordedDays),
                skippedDays: Int(response.summary.skippedDays),
                cheatMealDays: Int(response.summary.cheatMealDays),
                goalMetDays: Int(response.summary.goalMetDays),
                currentGoalStreak: Int(response.summary.currentGoalStreak),
                longestGoalStreak: Int(response.summary.longestGoalStreak)
            ),
            buckets: response.buckets.map { bucket in
                NutritionStatisticsBucket(
                    startAt: bucket.hasStartAt ? date(from: bucket.startAt) : Date(),
                    endAt: bucket.hasEndAt ? date(from: bucket.endAt) : Date(),
                    total: bucket.hasTotal ? nutritionSummary(from: bucket.total) : .zero,
                    goal: bucket.hasGoal ? mapDailyGoal(bucket.goal) : nil,
                    hasEntries: bucket.hasEntries_p,
                    hasCheatMeal: bucket.hasCheatMeal_p,
                    goalMet: bucket.goalMet,
                    mealCount: Int(bucket.mealCount)
                )
            }
        )
    }

    private func adjustedNutritionStatisticsSnapshot(_ snapshot: NutritionStatisticsSnapshot) -> NutritionStatisticsSnapshot {
        let averageDays = nutritionStatisticsAverageDayCount(for: snapshot)
        guard averageDays > 0 else { return snapshot }

        let total = snapshot.summary.total
        let summary = NutritionStatisticsSummary(
            total: total,
            averagePerDay: NutritionSummary(
                calories: total.calories / averageDays,
                protein: total.protein / averageDays,
                fat: total.fat / averageDays,
                carbs: total.carbs / averageDays
            ),
            totalDays: snapshot.summary.totalDays,
            recordedDays: snapshot.summary.recordedDays,
            skippedDays: snapshot.summary.skippedDays,
            cheatMealDays: snapshot.summary.cheatMealDays,
            goalMetDays: snapshot.summary.goalMetDays,
            currentGoalStreak: snapshot.summary.currentGoalStreak,
            longestGoalStreak: snapshot.summary.longestGoalStreak
        )

        return NutritionStatisticsSnapshot(
            period: snapshot.period,
            periodStart: snapshot.periodStart,
            periodEnd: snapshot.periodEnd,
            selectedAt: snapshot.selectedAt,
            summary: summary,
            buckets: snapshot.buckets
        )
    }

    private func nutritionStatisticsAverageDayCount(for snapshot: NutritionStatisticsSnapshot) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let periodStart = calendar.startOfDay(for: snapshot.periodStart)
        let periodEnd = calendar.startOfDay(for: snapshot.periodEnd)

        guard snapshot.period == .week, periodStart <= today, today <= periodEnd else {
            let reportedDays = snapshot.summary.totalDays > 0 ? snapshot.summary.totalDays : snapshot.buckets.count
            return max(1, reportedDays)
        }

        let elapsedBuckets = snapshot.buckets.filter { bucket in
            calendar.startOfDay(for: bucket.startAt) <= today
        }
        return max(1, elapsedBuckets.count)
    }

    private func mapNutritionStatsPeriod(_ period: Food_NutritionStatisticsPeriod) -> NutritionStatsPeriod {
        switch period {
        case .day:
            return .day
        case .month:
            return .month
        case .halfYear:
            return .halfYear
        case .year:
            return .year
        case .week, .unspecified, .UNRECOGNIZED:
            return .week
        }
    }

    private func localNutritionStatisticsSnapshot(period: NutritionStatsPeriod, anchor: Date) -> NutritionStatisticsSnapshot? {
        guard period == .week else { return nil }

        let calendar = Calendar.current
        let periodStart = startOfWeek(for: anchor)
        let periodLastDay = calendar.date(byAdding: .day, value: 6, to: periodStart) ?? periodStart
        let periodEnd = calendar.date(byAdding: .day, value: 1, to: periodLastDay)?.addingTimeInterval(-1) ?? periodLastDay
        let cacheSnapshot = loadedMealCacheSnapshot()

        let buckets = daysInRange(from: periodStart, through: periodLastDay).map { day -> NutritionStatisticsBucket in
            let dayStart = calendar.startOfDay(for: day)
            let dayMeals = dayStart == activeDay
                ? meals
                : Self.cachedMeals(for: dayStart, from: cacheSnapshot)
            let total = dailyHistory[dayStart]
                ?? Self.cachedSummary(for: dayStart, from: cacheSnapshot)
                ?? Self.nutritionSummary(from: dayMeals)
            let goal = goal(for: dayStart)
            let hasEntries = !dayMeals.isEmpty || total != .zero

            return NutritionStatisticsBucket(
                startAt: dayStart,
                endAt: calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? dayStart,
                total: total,
                goal: goal,
                hasEntries: hasEntries,
                hasCheatMeal: cheatMealDays.contains(dayKey(for: dayStart)),
                goalMet: hasEntries && goal.calories > 0 && total.calories <= goal.calories,
                mealCount: dayMeals.isEmpty && hasEntries ? 1 : dayMeals.count
            )
        }

        let total = buckets.reduce(into: NutritionSummary.zero) { partial, bucket in
            partial = NutritionSummary(
                calories: partial.calories + bucket.total.calories,
                protein: partial.protein + bucket.total.protein,
                fat: partial.fat + bucket.total.fat,
                carbs: partial.carbs + bucket.total.carbs
            )
        }
        let totalDays = max(1, buckets.count)
        let today = calendar.startOfDay(for: .now)
        let goalStreaks = goalStreakLengths(in: buckets.filter { $0.startAt <= today })

        return NutritionStatisticsSnapshot(
            period: period,
            periodStart: periodStart,
            periodEnd: periodEnd,
            selectedAt: calendar.startOfDay(for: anchor),
            summary: NutritionStatisticsSummary(
                total: total,
                averagePerDay: NutritionSummary(
                    calories: total.calories / totalDays,
                    protein: total.protein / totalDays,
                    fat: total.fat / totalDays,
                    carbs: total.carbs / totalDays
                ),
                totalDays: totalDays,
                recordedDays: buckets.filter(\.hasEntries).count,
                skippedDays: buckets.filter { !$0.hasEntries }.count,
                cheatMealDays: buckets.filter(\.hasCheatMeal).count,
                goalMetDays: buckets.filter(\.goalMet).count,
                currentGoalStreak: goalStreaks.current,
                longestGoalStreak: goalStreaks.longest
            ),
            buckets: buckets
        )
    }

    private func goalStreakLengths(in buckets: [NutritionStatisticsBucket]) -> (current: Int, longest: Int) {
        var current = 0
        var longest = 0

        for bucket in buckets {
            if bucket.goalMet {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }

        return (current, longest)
    }

    /// Number of consecutive days (ending yesterday) that have logged meals.
    ///
    /// Walks backwards day-by-day from yesterday and lazily loads each week of
    /// history only as it is reached, so the streak is not capped by whatever
    /// week is currently on screen. This makes the value stable and predictable
    /// across week boundaries (it only changes when a real gap is found).
    func loggingStreakDays(asOf referenceDay: Date = Date(), maxDaysToScan: Int = 400) async -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDay)

        var bucketsByDay: [Date: NutritionStatisticsBucket] = [:]
        var cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var streak = 0
        var scanned = 0

        while scanned < maxDaysToScan {
            if bucketsByDay[cursor] == nil {
                guard let snapshot = await loadNutritionStatistics(period: .week, anchor: cursor) else { break }
                if snapshot.buckets.isEmpty { break }
                for bucket in snapshot.buckets {
                    bucketsByDay[calendar.startOfDay(for: bucket.startAt)] = bucket
                }
                // The week loaded but still has no bucket for this exact day → treat as a gap.
                if bucketsByDay[cursor] == nil { break }
            }

            guard let bucket = bucketsByDay[cursor], bucket.hasEntries else { break }
            streak += 1
            scanned += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    private func mapNutritionAchievements(_ response: Food_NutritionAchievementsResponse) -> NutritionAchievementsSnapshot {
        NutritionAchievementsSnapshot(
            selectedAt: response.hasSelectedAt ? date(from: response.selectedAt) : .now,
            achievements: response.achievements.compactMap { achievement in
                guard let kind = mapNutritionAchievementKind(achievement.type) else { return nil }
                return NutritionAchievement(
                    kind: kind,
                    title: localizedAchievementTitle(for: kind, fallback: achievement.title),
                    description: localizedAchievementDescription(for: kind, fallback: achievement.description_p),
                    achieved: achievement.achieved,
                    achievedAt: achievement.hasAchievedAt ? date(from: achievement.achievedAt) : nil,
                    currentStreakDays: Int(achievement.currentStreakDays),
                    bestStreakDays: Int(achievement.bestStreakDays),
                    targetDays: Int(achievement.targetDays)
                )
            }
        )
    }

    private func mapNutritionAchievementKind(_ kind: Food_NutritionAchievementType) -> NutritionAchievementKind? {
        switch kind {
        case .logStreakWeek:
            return .logStreakWeek
        case .logStreakMonth:
            return .logStreakMonth
        case .logStreakHalfYear:
            return .logStreakHalfYear
        case .goalMetWeek:
            return .goalMetWeek
        case .goalMetMonth:
            return .goalMetMonth
        case .goalMetHalfYear:
            return .goalMetHalfYear
        case .goalOverWeek:
            return .goalOverWeek
        case .cheatWeek:
            return .cheatWeek
        case .goalUnderWeek:
            return .goalUnderWeek
        case .unspecified, .UNRECOGNIZED:
            return nil
        }
    }

    private func previewNutritionStatistics(period: NutritionStatsPeriod, anchor: Date) -> NutritionStatisticsSnapshot {
        let calendar = Calendar.current
        let history = FoodDiaryService.previewHistory(centeredOn: anchor)
        let periodStart: Date
        let periodEnd: Date

        switch period {
        case .day:
            periodStart = calendar.startOfDay(for: anchor)
            periodEnd = calendar.date(byAdding: .day, value: 1, to: periodStart)?.addingTimeInterval(-1) ?? periodStart
        case .week:
            periodStart = startOfWeek(for: anchor)
            periodEnd = calendar.date(byAdding: .day, value: 7, to: periodStart)?.addingTimeInterval(-1) ?? periodStart
        case .month:
            let components = calendar.dateComponents([.year, .month], from: anchor)
            periodStart = calendar.date(from: components) ?? anchor
            periodEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: periodStart) ?? periodStart
        case .halfYear:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
            periodStart = calendar.date(byAdding: .month, value: -5, to: monthStart) ?? monthStart
            periodEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) ?? monthStart
        case .year:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
            periodStart = calendar.date(byAdding: .month, value: -11, to: monthStart) ?? monthStart
            periodEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) ?? monthStart
        }

        let filteredDays = history.keys
            .map { calendar.startOfDay(for: $0) }
            .filter { $0 >= calendar.startOfDay(for: periodStart) && $0 <= calendar.startOfDay(for: periodEnd) }
            .sorted()

        let buckets: [NutritionStatisticsBucket]
        switch period {
        case .day:
            let previewMeals = FoodDiaryService.previewMeals(for: anchor)
            buckets = (0..<24).map { hour in
                let bucketStart = calendar.date(byAdding: .hour, value: hour, to: calendar.startOfDay(for: anchor)) ?? anchor
                let bucketMeals = previewMeals.filter { calendar.component(.hour, from: $0.scheduledAt) == hour }
                let total = NutritionSummary(
                    calories: bucketMeals.reduce(0) { $0 + $1.calories },
                    protein: bucketMeals.reduce(0) { $0 + $1.protein },
                    fat: bucketMeals.reduce(0) { $0 + $1.fat },
                    carbs: bucketMeals.reduce(0) { $0 + $1.carbs }
                )
                return NutritionStatisticsBucket(
                    startAt: bucketStart,
                    endAt: bucketStart.addingTimeInterval(3599),
                    total: total,
                    goal: dailyGoal,
                    hasEntries: !bucketMeals.isEmpty,
                    hasCheatMeal: false,
                    goalMet: false,
                    mealCount: bucketMeals.count
                )
            }
        default:
            buckets = filteredDays.map { day in
                let summary = history[day] ?? .zero
                return NutritionStatisticsBucket(
                    startAt: day,
                    endAt: calendar.date(byAdding: .day, value: 1, to: day)?.addingTimeInterval(-1) ?? day,
                    total: summary,
                    goal: goal(for: day),
                    hasEntries: summary != .zero,
                    hasCheatMeal: cheatMealDays.contains(dayKey(for: day)),
                    goalMet: false,
                    mealCount: summary == .zero ? 0 : 1
                )
            }
        }

        let total = buckets.reduce(into: NutritionSummary.zero) { partial, bucket in
            partial = NutritionSummary(
                calories: partial.calories + bucket.total.calories,
                protein: partial.protein + bucket.total.protein,
                fat: partial.fat + bucket.total.fat,
                carbs: partial.carbs + bucket.total.carbs
            )
        }
        let totalDays = max(1, buckets.count)
        let summary = NutritionStatisticsSummary(
            total: total,
            averagePerDay: NutritionSummary(
                calories: total.calories / totalDays,
                protein: total.protein / totalDays,
                fat: total.fat / totalDays,
                carbs: total.carbs / totalDays
            ),
            totalDays: totalDays,
            recordedDays: buckets.filter(\ .hasEntries).count,
            skippedDays: buckets.filter { !$0.hasEntries }.count,
            cheatMealDays: buckets.filter(\ .hasCheatMeal).count,
            goalMetDays: buckets.filter(\ .goalMet).count,
            currentGoalStreak: 0,
            longestGoalStreak: 0
        )
        return NutritionStatisticsSnapshot(
            period: period,
            periodStart: periodStart,
            periodEnd: periodEnd,
            selectedAt: anchor,
            summary: summary,
            buckets: buckets
        )
    }

    private func previewNutritionAchievements(anchor: Date) -> NutritionAchievementsSnapshot {
        let calendar = Calendar.current
        let previewHistory = FoodDiaryService.previewHistory(centeredOn: anchor)
        let sortedDays = previewHistory.keys.map { calendar.startOfDay(for: $0) }.sorted()
        let definitions: [(NutritionAchievementKind, Int, (Date) -> Bool)] = [
            (.logStreakWeek, 7, { day in (previewHistory[day] ?? .zero) != .zero }),
            (.logStreakMonth, 30, { day in (previewHistory[day] ?? .zero) != .zero }),
            (.logStreakHalfYear, 183, { day in (previewHistory[day] ?? .zero) != .zero }),
            (.goalMetWeek, 7, { day in self.previewCalories(in: previewHistory[day] ?? .zero, match: .inRange, goal: self.goal(for: day)) }),
            (.goalMetMonth, 30, { day in self.previewCalories(in: previewHistory[day] ?? .zero, match: .inRange, goal: self.goal(for: day)) }),
            (.goalMetHalfYear, 183, { day in self.previewCalories(in: previewHistory[day] ?? .zero, match: .inRange, goal: self.goal(for: day)) }),
            (.goalOverWeek, 7, { day in self.previewCalories(in: previewHistory[day] ?? .zero, match: .over, goal: self.goal(for: day)) }),
            (.cheatWeek, 7, { day in self.isCheatMealDay(day) && (previewHistory[day] ?? .zero) != .zero }),
            (.goalUnderWeek, 7, { day in self.previewCalories(in: previewHistory[day] ?? .zero, match: .under, goal: self.goal(for: day)) })
        ]

        return NutritionAchievementsSnapshot(
            selectedAt: anchor,
            achievements: definitions.map { definition in
                let progress = previewAchievementProgress(days: sortedDays, target: definition.1, predicate: definition.2)
                return NutritionAchievement(
                    kind: definition.0,
                    title: localizedAchievementTitle(for: definition.0, fallback: definition.0.rawValue),
                    description: localizedAchievementDescription(for: definition.0, fallback: definition.0.rawValue),
                    achieved: progress.best >= definition.1,
                    achievedAt: progress.achievedAt,
                    currentStreakDays: progress.current,
                    bestStreakDays: progress.best,
                    targetDays: definition.1
                )
            }
        )
    }

    private enum PreviewAchievementMatch {
        case inRange
        case over
        case under
    }

    private func previewCalories(in summary: NutritionSummary, match: PreviewAchievementMatch, goal: DailyNutritionGoal) -> Bool {
        guard summary.calories > 0, goal.calories > 0 else { return false }
        let ratio = Double(summary.calories) / Double(goal.calories)
        switch match {
        case .inRange:
            return ratio >= 0.9 && ratio <= 1.1
        case .over:
            return ratio >= 1.15
        case .under:
            return ratio <= 0.7
        }
    }

    private func previewAchievementProgress(days: [Date], target: Int, predicate: (Date) -> Bool) -> (current: Int, best: Int, achievedAt: Date?) {
        var current = 0
        var best = 0
        var running = 0
        var achievedAt: Date?

        for day in days {
            if predicate(day) {
                running += 1
                best = max(best, running)
                if achievedAt == nil && running >= target {
                    achievedAt = day
                }
            } else {
                running = 0
            }
        }

        for day in days.reversed() {
            if !predicate(day) {
                break
            }
            current += 1
        }

        return (current, best, achievedAt)
    }

    private func materializeItems(from items: [MealItemEntry], metadata: Metadata) async throws -> [Food_MealItem] {
        var result: [Food_MealItem] = []
        result.reserveCapacity(items.count)

        for item in items {
            let shouldDetachLinkedItem = await shouldDetachLinkedItemForSaving(item)

            if !shouldDetachLinkedItem {
                if let productID = item.productID,
                   catalogService?.productSummary(id: productID) == nil,
                   item.productSnapshot == nil {
                    _ = await catalogService?.fetchProduct(id: productID)
                } else if let recipeID = item.recipeID,
                          catalogService?.recipeSummary(id: recipeID) == nil,
                          item.recipeSnapshot == nil {
                    _ = await catalogService?.fetchRecipe(id: recipeID)
                }
            }

            var payload = Food_MealItem()
            payload.id = item.id.uuidString
            payload.amount = item.amount
            payload.unit = grpcUnit(from: item.unit)
            payload.note = shouldDetachLinkedItem ? serializedDetachedNutritionNote(for: item) : serializedNote(for: item)
            payload.servingLabel = item.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)

            if !shouldDetachLinkedItem, let productID = item.productID {
                payload.productID = productID.uuidString
                if let snapshot = catalogItemSnapshot(forProductID: productID, fallback: item.productSnapshot) {
                    payload.snapshot = snapshot
                }
            } else if !shouldDetachLinkedItem, let recipeID = item.recipeID {
                payload.recipeID = recipeID.uuidString
                if let snapshot = catalogItemSnapshot(forRecipeID: recipeID, fallback: item.recipeSnapshot) {
                    payload.snapshot = snapshot
                }
            } else if let productSnapshot = item.productSnapshot,
                      let snapshot = catalogItemSnapshot(forProductID: productSnapshot.id, fallback: productSnapshot) {
                payload.snapshot = snapshot
            } else if let recipeSnapshot = item.recipeSnapshot,
                      let snapshot = catalogItemSnapshot(forRecipeID: recipeSnapshot.id, fallback: recipeSnapshot) {
                payload.snapshot = snapshot
            }

            result.append(payload)
        }

        return result
    }

    private func catalogItemSnapshot(forProductID id: UUID, fallback: ProductSummary?) -> Food_CatalogItemSnapshot? {
        guard let product = catalogService?.productSummary(id: id) ?? fallback else { return nil }

        var snapshot = Food_CatalogItemSnapshot()
        var linkedProduct = Food_LinkedProductSnapshot()
        linkedProduct.id = product.id.uuidString
        linkedProduct.name = product.name
        linkedProduct.brand = product.brand
        linkedProduct.description_p = product.details
        linkedProduct.visibility = product.visibility.grpcValue
        linkedProduct.per100G = productNutritionFacts(from: product)
        linkedProduct.servingOptions = product.servingOptions.map { productServingOptionPayload(from: $0) }
        if let createdAt = product.createdAt {
            linkedProduct.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        }
        if let updatedAt = product.updatedAt {
            linkedProduct.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
        }
        snapshot.product = linkedProduct
        return snapshot
    }

    private func catalogItemSnapshot(forRecipeID id: UUID, fallback: RecipeSummary?) -> Food_CatalogItemSnapshot? {
        guard let recipe = catalogService?.recipeSummary(id: id) ?? fallback else { return nil }

        var snapshot = Food_CatalogItemSnapshot()
        var linkedRecipe = Food_LinkedRecipeSnapshot()
        linkedRecipe.id = recipe.id.uuidString
        linkedRecipe.title = recipe.title
        linkedRecipe.description_p = recipe.details
        linkedRecipe.nutritionPerServing = nutritionFacts(from: recipe.nutritionPerServing)
        linkedRecipe.servings = Int32(max(recipe.servings, 1))
        linkedRecipe.nutritionPer100G = nutritionFacts(from: recipe.resolvedNutritionPer100g)
        linkedRecipe.outputWeightGrams = recipe.outputWeightGrams
        linkedRecipe.category = recipe.category
        linkedRecipe.visibility = recipe.visibility.grpcValue
        if let createdAt = recipe.createdAt {
            linkedRecipe.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        }
        if let updatedAt = recipe.updatedAt {
            linkedRecipe.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
        }
        snapshot.recipe = linkedRecipe
        return snapshot
    }

    private func productNutritionFacts(from product: ProductSummary) -> Food_NutritionFacts {
        var facts = nutritionFacts(
            from: NutritionSummary(
                calories: product.caloriesPer100g,
                protein: product.proteinPer100g,
                fat: product.fatPer100g,
                carbs: product.carbsPer100g
            )
        )
        facts.fiber = product.fiberPer100g
        facts.sugar = product.sugarPer100g
        facts.sodiumMg = product.sodiumMgPer100g
        facts.servingAmount = product.servingAmount
        facts.servingUnit = grpcUnit(from: product.servingUnit)
        facts.saturatedFat = product.saturatedFatPer100g
        facts.unsaturatedFat = product.unsaturatedFatPer100g
        facts.additionalNutrients = product.additionalNutrients.map { productNutrientValue(from: $0) }
        return facts
    }

    private func productNutrientValue(from nutrient: ProductNutrient) -> Food_NutrientValue {
        var payload = Food_NutrientValue()
        payload.code = nutrient.code
        payload.label = nutrient.label
        payload.amount = nutrient.amount
        payload.unit = nutrient.unit
        return payload
    }

    private func productServingOptionPayload(from option: ProductServingOption) -> Food_ProductServingOption {
        var payload = Food_ProductServingOption()
        payload.id = option.id
        payload.label = option.label
        payload.amount = option.amount
        payload.unit = grpcUnit(from: option.unit)
        payload.metricAmount = option.metricAmount
        payload.metricUnit = grpcUnit(from: option.metricUnit)
        payload.sortOrder = Int32(option.sortOrder)
        return payload
    }

    private func shouldDetachLinkedItemForSaving(_ item: MealItemEntry) async -> Bool {
        if let productID = item.productID {
            if item.productSnapshot != nil, catalogService?.productSummary(id: productID) == nil {
                return hasAnyNutrition(item)
            }
            if catalogService?.productSummary(id: productID) != nil {
                return false
            }
            _ = await catalogService?.fetchProduct(id: productID)
            return catalogService?.productSummary(id: productID) == nil
                && (item.productSnapshot != nil || hasAnyNutrition(item))
        }

        if let recipeID = item.recipeID {
            if item.recipeSnapshot != nil, catalogService?.recipeSummary(id: recipeID) == nil {
                return hasAnyNutrition(item)
            }
            if catalogService?.recipeSummary(id: recipeID) != nil {
                return false
            }
            _ = await catalogService?.fetchRecipe(id: recipeID)
            return catalogService?.recipeSummary(id: recipeID) == nil
                && (item.recipeSnapshot != nil || hasAnyNutrition(item))
        }

        return false
    }

    private func prefetchMissingCatalogItems(from meals: [Food_Meal]) async {
        guard let catalogService else { return }

        var missingProductIDs = Set<UUID>()
        var missingRecipeIDs = Set<UUID>()

        for meal in meals {
            for item in meal.items {
                let snapshot = item.hasSnapshot ? FoodCatalogService.linkedSummaries(from: item.snapshot) : (product: nil, recipe: nil)

                if let productID = UUID(uuidString: item.productID),
                   catalogService.productSummary(id: productID) == nil,
                   snapshot.product == nil {
                    missingProductIDs.insert(productID)
                }
                if let recipeID = UUID(uuidString: item.recipeID),
                   catalogService.recipeSummary(id: recipeID) == nil,
                   snapshot.recipe == nil {
                    missingRecipeIDs.insert(recipeID)
                }
            }
        }

        guard !missingProductIDs.isEmpty || !missingRecipeIDs.isEmpty else { return }

        for id in missingProductIDs {
            _ = await catalogService.fetchProduct(id: id)
        }
        for id in missingRecipeIDs {
            _ = await catalogService.fetchRecipe(id: id)
        }
    }

    private func mapMeal(_ meal: Food_Meal) -> MealEntry {
        let scheduledAt = meal.hasEatenAt ? date(from: meal.eatenAt) : Date()
        let serverNutrition = meal.hasTotals ? nutritionSummary(from: meal.totals) : NutritionSummary.zero
        let inferredKind = MealKind.inferred(from: scheduledAt)
        let decodedNote = decodedMealNote(from: meal.note)
        let localCategoryID = mealCategoryAssignments[meal.id]
            ?? decodedNote?.categoryID
            ?? matchedCategoryID(forMealTitle: meal.title)
            ?? inferredKind.rawValue
        let legacyMappedItems = applyLegacyManualNutritionFallback(
            to: meal.items.map(mapMealItem),
            mealNutrition: serverNutrition
        )
        let mappedItems = applyMissingLinkedNutritionFallback(
            to: legacyMappedItems,
            mealNutrition: serverNutrition
        )
        let nutrition = resolvedMealNutrition(serverNutrition: serverNutrition, items: mappedItems)
        return MealEntry(
            id: UUID(uuidString: meal.id) ?? UUID(),
            kind: inferredKind,
            mealCategoryID: localCategoryID,
            title: meal.title,
            items: mappedItems,
            note: decodedNote?.userNote ?? meal.note,
            scheduledAt: scheduledAt,
            nutrition: nutrition
        )
    }

    private func hydratedMealEntry(_ meal: MealEntry, fallback: MealEntry?) -> MealEntry {
        guard let fallback else { return meal }

        if shouldPreferFallbackItems(for: meal, fallback: fallback) {
            var hydratedMeal = meal
            hydratedMeal.items = fallback.items
            return hydratedMeal
        }

        guard requiresLinkedItemHydration(meal) else { return meal }

        var remainingFallbackItems = fallback.items
        var hydratedMeal = meal
        hydratedMeal.items = meal.items.map { item in
            guard let fallbackIndex = bestFallbackItemIndex(for: item, in: remainingFallbackItems) else {
                return item
            }

            let fallbackItem = remainingFallbackItems.remove(at: fallbackIndex)
            return hydratedMealItem(item, fallback: fallbackItem)
        }
        return hydratedMeal
    }

    private func shouldPreferFallbackItems(for meal: MealEntry, fallback: MealEntry) -> Bool {
        guard !fallback.items.isEmpty else { return false }
        if meal.items.isEmpty {
            return true
        }

        return meal.items.allSatisfy(isManualNutritionItem)
            && fallback.items.contains { !isManualNutritionItem($0) }
    }

    private func hydratedFetchedMeal(_ meal: MealEntry, cacheSnapshot: DiaryCacheSnapshot?) -> MealEntry {
        hydratedMealEntry(meal, fallback: cachedMeal(id: meal.id, from: cacheSnapshot))
    }

    private func cachedMeal(id: UUID, from snapshot: DiaryCacheSnapshot?) -> MealEntry? {
        guard let snapshot else { return nil }
        for dayMeals in snapshot.mealsByDay.values {
            if let meal = dayMeals.first(where: { $0.id == id }) {
                return meal
            }
        }
        return nil
    }

    private func requiresLinkedItemHydration(_ meal: MealEntry) -> Bool {
        meal.items.contains { item in
            item.isLinkedToCatalogItem && needsFallbackNutrition(for: item)
        }
    }

    private func needsFallbackNutrition(for item: MealItemEntry) -> Bool {
        let hasNoNutrition = item.caloriesPer100g == 0
            && item.proteinPer100g == 0
            && item.fatPer100g == 0
            && item.carbsPer100g == 0
        let hasNoSnapshots = item.productSnapshot == nil && item.recipeSnapshot == nil
        return hasNoNutrition || hasNoSnapshots
    }

    private func hydratedMealItem(_ item: MealItemEntry, fallback: MealItemEntry) -> MealItemEntry {
        var hydratedItem = item

        if item.caloriesPer100g == 0 && item.proteinPer100g == 0 && item.fatPer100g == 0 && item.carbsPer100g == 0 {
            hydratedItem.caloriesPer100g = fallback.caloriesPer100g
            hydratedItem.proteinPer100g = fallback.proteinPer100g
            hydratedItem.fatPer100g = fallback.fatPer100g
            hydratedItem.carbsPer100g = fallback.carbsPer100g
        }

        if hydratedItem.productSnapshot == nil {
            hydratedItem.productSnapshot = fallback.productSnapshot
        }

        if hydratedItem.recipeSnapshot == nil {
            hydratedItem.recipeSnapshot = fallback.recipeSnapshot
        }

        if hydratedItem.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hydratedItem.name = fallback.name
        }

        return hydratedItem
    }

    private func bestFallbackItemIndex(for item: MealItemEntry, in candidates: [MealItemEntry]) -> Int? {
        if let exactIDMatch = candidates.firstIndex(where: { $0.id == item.id }) {
            return exactIDMatch
        }

        if let linkedMatch = candidates.firstIndex(where: {
            $0.productID == item.productID
                && $0.recipeID == item.recipeID
                && $0.unit == item.unit
                && abs($0.amount - item.amount) < 0.0001
        }) {
            return linkedMatch
        }

        return candidates.firstIndex(where: {
            $0.productID == item.productID
                && $0.recipeID == item.recipeID
                && $0.name == item.name
        })
    }

    private func serializedMealNote(for meal: MealEntry) -> String {
        let categoryID = normalizedCategoryID(for: meal)
        let userNote = meal.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.mealCategoryNotePrefix + categoryID + "|" + userNote
    }

    private func decodedMealNote(from note: String) -> (categoryID: String, userNote: String)? {
        guard note.hasPrefix(Self.mealCategoryNotePrefix) else { return nil }
        let payload = String(note.dropFirst(Self.mealCategoryNotePrefix.count))
        let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let rawCategoryID = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !rawCategoryID.isEmpty else {
            return nil
        }
        let userNote = parts.count > 1 ? parts[1] : ""
        return (categoryID: rawCategoryID, userNote: userNote)
    }

    private func mapMealItem(_ item: Food_MealItem) -> MealItemEntry {
        let resolvedUnit = mealUnit(from: item.unit)
        let decodedManualNutrition = manualNutrition(from: item.note)
        let fallbackName = decodedManualNutrition?.name ?? item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemID = UUID(uuidString: item.id) ?? UUID()
        let snapshot = item.hasSnapshot
            ? FoodCatalogService.linkedSummaries(from: item.snapshot, fallbackID: itemID)
            : (product: nil, recipe: nil)

        if let productID = UUID(uuidString: item.productID),
           let product = catalogService?.productSummary(id: productID) ?? snapshot.product {
            return MealItemEntry(
                id: itemID,
                name: product.name,
                amount: item.amount,
                unit: resolvedUnit,
                note: "",
                servingLabel: item.servingLabel,
                caloriesPer100g: product.caloriesPer100g,
                proteinPer100g: product.proteinPer100g,
                fatPer100g: product.fatPer100g,
                carbsPer100g: product.carbsPer100g,
                productID: productID,
                recipeID: nil,
                productSnapshot: product,
                recipeSnapshot: nil
            )
        }

        if let recipeID = UUID(uuidString: item.recipeID),
           let recipe = catalogService?.recipeSummary(id: recipeID) ?? snapshot.recipe {
            if let catalogService {
                return catalogService.makeMealItem(
                    from: recipe,
                    id: itemID,
                    amount: item.amount,
                    unit: resolvedUnit,
                    note: "",
                    servingLabel: item.servingLabel
                )
            }

            let nutrition: NutritionSummary
            switch resolvedUnit {
            case .serving:
                nutrition = recipe.nutritionPerServing
            case .grams, .milliliters:
                nutrition = recipe.resolvedNutritionPer100g
            }

            return MealItemEntry(
                id: itemID,
                name: recipe.title,
                amount: item.amount,
                unit: resolvedUnit,
                note: "",
                servingLabel: item.servingLabel,
                caloriesPer100g: nutrition.calories,
                proteinPer100g: nutrition.protein,
                fatPer100g: nutrition.fat,
                carbsPer100g: nutrition.carbs,
                productID: nil,
                recipeID: recipeID,
                productSnapshot: nil,
                recipeSnapshot: recipe
            )
        }

        if let product = snapshot.product {
            return MealItemEntry(
                id: itemID,
                name: product.name,
                amount: item.amount,
                unit: resolvedUnit,
                note: "",
                servingLabel: item.servingLabel,
                caloriesPer100g: product.caloriesPer100g,
                proteinPer100g: product.proteinPer100g,
                fatPer100g: product.fatPer100g,
                carbsPer100g: product.carbsPer100g,
                productID: nil,
                recipeID: nil,
                productSnapshot: product,
                recipeSnapshot: nil
            )
        }

        if let recipe = snapshot.recipe {
            let nutrition: NutritionSummary
            switch resolvedUnit {
            case .serving:
                nutrition = recipe.nutritionPerServing
            case .grams, .milliliters:
                nutrition = recipe.resolvedNutritionPer100g
            }

            return MealItemEntry(
                id: itemID,
                name: recipe.title,
                amount: item.amount,
                unit: resolvedUnit,
                note: "",
                servingLabel: item.servingLabel,
                caloriesPer100g: nutrition.calories,
                proteinPer100g: nutrition.protein,
                fatPer100g: nutrition.fat,
                carbsPer100g: nutrition.carbs,
                productID: nil,
                recipeID: nil,
                productSnapshot: nil,
                recipeSnapshot: recipe
            )
        }

        return MealItemEntry(
            id: itemID,
            name: unresolvedItemName(for: item, decodedName: fallbackName),
            amount: item.amount,
            unit: resolvedUnit,
            note: "",
            servingLabel: item.servingLabel,
            caloriesPer100g: decodedManualNutrition?.calories ?? 0,
            proteinPer100g: decodedManualNutrition?.protein ?? 0,
            fatPer100g: decodedManualNutrition?.fat ?? 0,
            carbsPer100g: decodedManualNutrition?.carbs ?? 0,
            productID: UUID(uuidString: item.productID),
            recipeID: UUID(uuidString: item.recipeID),
            productSnapshot: snapshot.product,
            recipeSnapshot: snapshot.recipe
        )
    }

    /// What to call an item whose catalog row could not be resolved.
    ///
    /// The name in the payload wins; failing that it is named after whatever it
    /// points at. An item that points at nothing is one the reader typed, and
    /// that case used to fall through to the recipe title — which is how a
    /// hand-entered figure came back looking like a dish nobody had cooked.
    private func unresolvedItemName(for item: Food_MealItem, decodedName: String) -> String {
        if !decodedName.isEmpty { return decodedName }
        if !item.recipeID.isEmpty {
            return NSLocalizedString("recipe.fallback_title", comment: "Fallback recipe title")
        }
        if !item.productID.isEmpty {
            return NSLocalizedString("addmeal.item.product_fallback", comment: "Fallback product title")
        }
        return Self.localizedManualNutritionItemName
    }

    private func serializedNote(for item: MealItemEntry) -> String {
        let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isManualNutritionItem(item) || (!item.isLinkedToCatalogItem && hasAnyNutrition(item)) {
            return Self.manualNutritionNotePrefix + [
                trimmedName.isEmpty ? Self.localizedManualNutritionItemName : Self.normalizedManualNutritionName(trimmedName),
                String(item.caloriesPer100g),
                String(item.proteinPer100g),
                String(item.fatPer100g),
                String(item.carbsPer100g)
            ].joined(separator: "|")
        }
        return trimmedName
    }

    private func serializedDetachedNutritionNote(for item: MealItemEntry) -> String {
        let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.manualNutritionNotePrefix + [
            trimmedName.isEmpty ? Self.localizedManualNutritionItemName : Self.normalizedManualNutritionName(trimmedName),
            String(item.caloriesPer100g),
            String(item.proteinPer100g),
            String(item.fatPer100g),
            String(item.carbsPer100g)
        ].joined(separator: "|")
    }

    private func manualNutrition(from note: String) -> (name: String, calories: Int, protein: Int, fat: Int, carbs: Int)? {
        guard note.hasPrefix(Self.manualNutritionNotePrefix) else { return nil }
        let payload = String(note.dropFirst(Self.manualNutritionNotePrefix.count))
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else { return nil }
        return (
            name: parts[0].isEmpty ? Self.localizedManualNutritionItemName : Self.normalizedManualNutritionName(parts[0]),
            calories: Int(parts[1]) ?? 0,
            protein: Int(parts[2]) ?? 0,
            fat: Int(parts[3]) ?? 0,
            carbs: Int(parts[4]) ?? 0
        )
    }

    private func applyLegacyManualNutritionFallback(to items: [MealItemEntry], mealNutrition: NutritionSummary) -> [MealItemEntry] {
        guard items.count == 1 else { return items }
        guard isLegacyManualNutritionItem(items[0]) else { return items }

        var restoredItems = items
        restoredItems[0].caloriesPer100g = mealNutrition.calories
        restoredItems[0].proteinPer100g = mealNutrition.protein
        restoredItems[0].fatPer100g = mealNutrition.fat
        restoredItems[0].carbsPer100g = mealNutrition.carbs
        restoredItems[0].amount = 1
        restoredItems[0].unit = .serving
        restoredItems[0].name = Self.localizedManualNutritionItemName
        return restoredItems
    }

    private func applyMissingLinkedNutritionFallback(to items: [MealItemEntry], mealNutrition: NutritionSummary) -> [MealItemEntry] {
        let fallbackIndexes = items.indices.filter { needsMissingLinkedNutritionFallback(items[$0]) }
        guard !fallbackIndexes.isEmpty, hasAnyNutrition(mealNutrition) else { return items }

        let knownItems = items.indices
            .filter { !fallbackIndexes.contains($0) }
            .map { items[$0] }
        let knownNutrition = nutritionSummary(for: knownItems)
        let remainingNutrition = NutritionSummary(
            calories: max(mealNutrition.calories - knownNutrition.calories, 0),
            protein: max(mealNutrition.protein - knownNutrition.protein, 0),
            fat: max(mealNutrition.fat - knownNutrition.fat, 0),
            carbs: max(mealNutrition.carbs - knownNutrition.carbs, 0)
        )
        guard hasAnyNutrition(remainingNutrition) else { return items }

        var restoredItems = items
        for (fallbackPosition, itemIndex) in fallbackIndexes.enumerated() {
            let allocatedNutrition = allocatedNutrition(
                from: remainingNutrition,
                count: fallbackIndexes.count,
                index: fallbackPosition
            )
            apply(allocatedNutrition, to: &restoredItems[itemIndex])
        }
        return restoredItems
    }

    private func needsMissingLinkedNutritionFallback(_ item: MealItemEntry) -> Bool {
        item.isLinkedToCatalogItem && !hasAnyNutrition(item)
    }

    private func nutritionSummary(for items: [MealItemEntry]) -> NutritionSummary {
        NutritionSummary(
            calories: items.reduce(0) { $0 + $1.calories },
            protein: items.reduce(0) { $0 + $1.protein },
            fat: items.reduce(0) { $0 + $1.fat },
            carbs: items.reduce(0) { $0 + $1.carbs }
        )
    }

    private func allocatedNutrition(from nutrition: NutritionSummary, count: Int, index: Int) -> NutritionSummary {
        guard count > 1 else { return nutrition }
        return NutritionSummary(
            calories: allocatedValue(nutrition.calories, count: count, index: index),
            protein: allocatedValue(nutrition.protein, count: count, index: index),
            fat: allocatedValue(nutrition.fat, count: count, index: index),
            carbs: allocatedValue(nutrition.carbs, count: count, index: index)
        )
    }

    private func allocatedValue(_ value: Int, count: Int, index: Int) -> Int {
        guard count > 1 else { return value }
        let base = value / count
        return index == count - 1 ? value - base * (count - 1) : base
    }

    private func apply(_ nutrition: NutritionSummary, to item: inout MealItemEntry) {
        let multiplier: Double
        switch item.unit {
        case .serving:
            multiplier = max(item.amount, 1)
        case .grams, .milliliters:
            multiplier = max(item.amount, 1) / 100.0
        }

        item.caloriesPer100g = Int((Double(nutrition.calories) / multiplier).rounded())
        item.proteinPer100g = Int((Double(nutrition.protein) / multiplier).rounded())
        item.fatPer100g = Int((Double(nutrition.fat) / multiplier).rounded())
        item.carbsPer100g = Int((Double(nutrition.carbs) / multiplier).rounded())
    }

    private func hasAnyNutrition(_ item: MealItemEntry) -> Bool {
        item.caloriesPer100g > 0
            || item.proteinPer100g > 0
            || item.fatPer100g > 0
            || item.carbsPer100g > 0
    }

    private func hasAnyNutrition(_ nutrition: NutritionSummary) -> Bool {
        nutrition.calories > 0
            || nutrition.protein > 0
            || nutrition.fat > 0
            || nutrition.carbs > 0
    }

    private func resolvedMealNutrition(serverNutrition: NutritionSummary, items: [MealItemEntry]) -> NutritionSummary {
        guard items.contains(where: isManualNutritionItem) else { return serverNutrition }

        let itemNutrition = NutritionSummary(
            calories: items.reduce(0) { $0 + $1.calories },
            protein: items.reduce(0) { $0 + $1.protein },
            fat: items.reduce(0) { $0 + $1.fat },
            carbs: items.reduce(0) { $0 + $1.carbs }
        )
        guard itemNutrition.calories > serverNutrition.calories
            || itemNutrition.protein > serverNutrition.protein
            || itemNutrition.fat > serverNutrition.fat
            || itemNutrition.carbs > serverNutrition.carbs
        else {
            return serverNutrition
        }

        return itemNutrition
    }

    private func isManualNutritionItem(_ item: MealItemEntry) -> Bool {
        item.productID == nil && item.recipeID == nil && Self.isManualNutritionName(item.name)
    }

    private func isLegacyManualNutritionItem(_ item: MealItemEntry) -> Bool {
        guard item.productID == nil, item.recipeID == nil else { return false }
        guard item.caloriesPer100g == 0, item.proteinPer100g == 0, item.fatPer100g == 0, item.carbsPer100g == 0 else {
            return false
        }
        return Self.isManualNutritionName(item.name)
    }

    private func nutritionSummary(from facts: Food_NutritionFacts) -> NutritionSummary {
        NutritionSummary(
            calories: Int(facts.calories.rounded()),
            protein: Int(facts.protein.rounded()),
            fat: Int(facts.fat.rounded()),
            carbs: Int(facts.carbs.rounded())
        )
    }

    private func nutritionFacts(from summary: NutritionSummary) -> Food_NutritionFacts {
        var facts = Food_NutritionFacts()
        facts.calories = Double(summary.calories)
        facts.protein = Double(summary.protein)
        facts.fat = Double(summary.fat)
        facts.carbs = Double(summary.carbs)
        return facts
    }

    private func mealUnit(from unit: Food_NutritionUnit) -> MealItemUnit {
        switch unit {
        case .grams:
            return .grams
        case .milliliters:
            return .milliliters
        case .serving:
            return .serving
        case .unspecified, .UNRECOGNIZED:
            return .grams
        }
    }

    private func grpcUnit(from unit: MealItemUnit) -> Food_NutritionUnit {
        switch unit {
        case .grams:
            return .grams
        case .milliliters:
            return .milliliters
        case .serving:
            return .serving
        }
    }

    private func date(from timestamp: Google_Protobuf_Timestamp) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp.seconds) + TimeInterval(timestamp.nanos) / 1_000_000_000)
    }

    private func quickMealTitle(for kind: MealKind) -> String {
        switch kind {
        case .breakfast:
            return "Быстрый завтрак"
        case .lunch:
            return "Быстрый обед"
        case .dinner:
            return "Быстрый ужин"
        case .snack:
            return "Перекус"
        }
    }

    private func quickProtein(for kind: MealKind) -> Int {
        switch kind {
        case .breakfast:
            return 22
        case .lunch:
            return 34
        case .dinner:
            return 29
        case .snack:
            return 8
        }
    }

    private func quickItems(for kind: MealKind) -> [MealItemEntry] {
        switch kind {
        case .breakfast:
            return [
                MealItemEntry(id: UUID(), name: "Яйца", amount: 100, unit: .grams, note: "", caloriesPer100g: 155, proteinPer100g: 13, fatPer100g: 11, carbsPer100g: 1, productID: nil, recipeID: nil),
                MealItemEntry(id: UUID(), name: "Овсянка", amount: 80, unit: .grams, note: "", caloriesPer100g: 352, proteinPer100g: 12, fatPer100g: 6, carbsPer100g: 61, productID: nil, recipeID: nil)
            ]
        case .lunch:
            return [
                MealItemEntry(id: UUID(), name: "Курица", amount: 180, unit: .grams, note: "", caloriesPer100g: 165, proteinPer100g: 31, fatPer100g: 4, carbsPer100g: 0, productID: nil, recipeID: nil),
                MealItemEntry(id: UUID(), name: "Рис", amount: 160, unit: .grams, note: "", caloriesPer100g: 130, proteinPer100g: 3, fatPer100g: 0, carbsPer100g: 28, productID: nil, recipeID: nil)
            ]
        case .dinner:
            return [
                MealItemEntry(id: UUID(), name: "Лосось", amount: 150, unit: .grams, note: "", caloriesPer100g: 208, proteinPer100g: 20, fatPer100g: 13, carbsPer100g: 0, productID: nil, recipeID: nil),
                MealItemEntry(id: UUID(), name: "Овощи", amount: 180, unit: .grams, note: "", caloriesPer100g: 45, proteinPer100g: 2, fatPer100g: 0, carbsPer100g: 9, productID: nil, recipeID: nil)
            ]
        case .snack:
            return [
                MealItemEntry(id: UUID(), name: "Йогурт", amount: 170, unit: .grams, note: "", caloriesPer100g: 68, proteinPer100g: 5, fatPer100g: 3, carbsPer100g: 4, productID: nil, recipeID: nil),
                MealItemEntry(id: UUID(), name: "Банан", amount: 120, unit: .grams, note: "", caloriesPer100g: 89, proteinPer100g: 1, fatPer100g: 0, carbsPer100g: 23, productID: nil, recipeID: nil)
            ]
        }
    }

    private static let sampleMeals: [MealEntry] = [
        MealEntry(
            id: UUID(),
            kind: .breakfast,
            mealCategoryID: MealKind.breakfast.rawValue,
            title: "Яйца и колбаса",
            items: [
                MealItemEntry(id: UUID(), name: "Яйца", amount: 100, unit: .grams, note: "", caloriesPer100g: 155, proteinPer100g: 13, fatPer100g: 11, carbsPer100g: 1, productID: nil, recipeID: nil),
                MealItemEntry(id: UUID(), name: "Колбаса", amount: 150, unit: .grams, note: "", caloriesPer100g: 301, proteinPer100g: 12, fatPer100g: 27, carbsPer100g: 1, productID: nil, recipeID: nil)
            ],
            note: "Здесь можно исправить колбасу с 150 г на 100 г",
            scheduledAt: .now.addingTimeInterval(-60 * 60 * 7),
            nutrition: NutritionSummary(calories: 607, protein: 31, fat: 52, carbs: 3)
        ),
        MealEntry(
            id: UUID(),
            kind: .lunch,
            mealCategoryID: MealKind.lunch.rawValue,
            title: "Курица с рисом",
            items: [
                MealItemEntry(id: UUID(), name: "Курица", amount: 180, unit: .grams, note: "", caloriesPer100g: 165, proteinPer100g: 31, fatPer100g: 4, carbsPer100g: 0, productID: nil, recipeID: nil),
                MealItemEntry(id: UUID(), name: "Рис", amount: 160, unit: .grams, note: "", caloriesPer100g: 130, proteinPer100g: 3, fatPer100g: 0, carbsPer100g: 28, productID: nil, recipeID: nil)
            ],
            note: "",
            scheduledAt: .now.addingTimeInterval(-60 * 60 * 3),
            nutrition: NutritionSummary(calories: 505, protein: 61, fat: 7, carbs: 45)
        ),
        MealEntry(
            id: UUID(),
            kind: .snack,
            mealCategoryID: MealKind.snack.rawValue,
            title: "Йогурт и банан",
            items: [
                MealItemEntry(id: UUID(), name: "Йогурт", amount: 170, unit: .grams, note: "", caloriesPer100g: 68, proteinPer100g: 5, fatPer100g: 3, carbsPer100g: 4, productID: nil, recipeID: nil),
                MealItemEntry(id: UUID(), name: "Банан", amount: 120, unit: .grams, note: "", caloriesPer100g: 89, proteinPer100g: 1, fatPer100g: 0, carbsPer100g: 23, productID: nil, recipeID: nil)
            ],
            note: "",
            scheduledAt: .now.addingTimeInterval(-60 * 60),
            nutrition: NutritionSummary(calories: 222, protein: 10, fat: 5, carbs: 34)
        )
    ]

    private func fetchMeals(for day: Date) async throws -> [MealEntry] {
        let start = Calendar.current.startOfDay(for: day)
        let response = try await withAuthenticatedMetadata { metadata in
            var request = Food_ListMealsRequest()
            request.from = Google_Protobuf_Timestamp(date: start)
            request.to = Google_Protobuf_Timestamp(date: Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start)
            request.limit = 100
            return try await withFoodClient { client in
                try await client.listMeals(request, metadata: metadata)
            }
        }
        await prefetchMissingCatalogItems(from: response.meals)
        let cacheSnapshot = loadedMealCacheSnapshot()
        return response.meals
            .map { hydratedFetchedMeal(mapMeal($0), cacheSnapshot: cacheSnapshot) }
            .sorted(by: { $0.scheduledAt < $1.scheduledAt })
    }

    private func fetchMealsGroupedByDay(from startDay: Date, through endDay: Date) async throws -> [Date: [MealEntry]] {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDay)
        let normalizedEnd = calendar.startOfDay(for: endDay)
        guard normalizedStart <= normalizedEnd else { return [:] }

        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: normalizedEnd) ?? normalizedEnd
        let response = try await withAuthenticatedMetadata { metadata in
            var request = Food_ListMealsRequest()
            request.from = Google_Protobuf_Timestamp(date: normalizedStart)
            request.to = Google_Protobuf_Timestamp(date: rangeEnd)
            request.limit = Int32(Self.batchedMealRangeLimit)
            return try await withFoodClient { client in
                try await client.listMeals(request, metadata: metadata)
            }
        }

        await prefetchMissingCatalogItems(from: response.meals)
        let cacheSnapshot = loadedMealCacheSnapshot()
        let meals = response.meals
            .map { hydratedFetchedMeal(mapMeal($0), cacheSnapshot: cacheSnapshot) }
            .sorted(by: { $0.scheduledAt < $1.scheduledAt })
        return Dictionary(grouping: meals) { meal in
            calendar.startOfDay(for: meal.scheduledAt)
        }
    }

    private func historyFetchPlan(for day: Date) -> HistoryFetchPlan {
        let calendar = Calendar.current
        let resolvedDay = calendar.startOfDay(for: day)
        let weekStart = startOfWeek(for: resolvedDay)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? resolvedDay
        let today = calendar.startOfDay(for: .now)
        let primaryEnd = min(weekEnd, today)
        let supplementalDay = (today < weekStart || today > primaryEnd) ? today : nil

        return HistoryFetchPlan(
            primaryStart: weekStart,
            primaryEnd: primaryEnd,
            supplementalDay: supplementalDay
        )
    }

    private func mergeFetchedMealsHistory(_ mealsByDay: [Date: [MealEntry]], from startDay: Date, through endDay: Date) {
        let calendar = Calendar.current
        var snapshot = loadedMealCacheSnapshot()
            ?? DiaryCacheSnapshot(mealsByDay: [:], dailyHistoryByDay: [:])

        for day in daysInRange(from: startDay, through: endDay) {
            let dayStart = calendar.startOfDay(for: day)
            let dayMeals = (mealsByDay[dayStart] ?? []).sorted(by: { $0.scheduledAt < $1.scheduledAt })
            let summary = Self.nutritionSummary(from: dayMeals)
            dailyHistory[dayStart] = summary
            let dayKey = Self.dayKey(from: dayStart)
            snapshot.mealsByDay[dayKey] = dayMeals
            snapshot.dailyHistoryByDay[dayKey] = summary
        }

        let trimmed = Self.trimmedMealCacheSnapshot(snapshot)
        mealCacheSnapshot = trimmed
        hasLoadedMealCacheSnapshot = true
        CachedJSONStore.save(trimmed, key: Self.mealCacheKeyPrefix + cacheScopeID)
    }

    private func loadMealHistory(forWeekContaining day: Date, generation: Int) async {
        guard authService != nil else { return }

        let calendar = Calendar.current
        let weekStart = startOfWeek(for: day)
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return }

        for targetDay in daysInRange(from: weekStart, through: min(weekEnd, calendar.startOfDay(for: .now))) {
            guard generation == mealsLoadGeneration else { return }
            let dayStart = calendar.startOfDay(for: targetDay)
            if dayStart == activeDay {
                dailyHistory[dayStart] = NutritionSummary(
                    calories: totalCalories,
                    protein: totalProtein,
                    fat: totalFat,
                    carbs: totalCarbs
                )
                continue
            }

            do {
                let fetchedMeals = try await fetchMeals(for: dayStart)
                guard generation == mealsLoadGeneration else { return }
                let summary = NutritionSummary(
                    calories: fetchedMeals.reduce(0) { $0 + $1.calories },
                    protein: fetchedMeals.reduce(0) { $0 + $1.protein },
                    fat: fetchedMeals.reduce(0) { $0 + $1.fat },
                    carbs: fetchedMeals.reduce(0) { $0 + $1.carbs }
                )
                dailyHistory[dayStart] = summary
                persistHistorySnapshot(for: dayStart, summary: summary)
            } catch {
                if isCancellationError(error) {
                    return
                }
                dailyHistory[dayStart] = dailyHistory[dayStart] ?? .zero
            }
        }
    }

    private func loadCurrentDayHistoryIfNeeded(generation: Int) async {
        guard authService != nil else { return }
        guard generation == mealsLoadGeneration else { return }

        let today = Calendar.current.startOfDay(for: .now)
        if today == activeDay {
            dailyHistory[today] = NutritionSummary(
                calories: totalCalories,
                protein: totalProtein,
                fat: totalFat,
                carbs: totalCarbs
            )
            return
        }

        do {
            let fetchedMeals = try await fetchMeals(for: today)
            guard generation == mealsLoadGeneration else { return }
            let summary = NutritionSummary(
                calories: fetchedMeals.reduce(0) { $0 + $1.calories },
                protein: fetchedMeals.reduce(0) { $0 + $1.protein },
                fat: fetchedMeals.reduce(0) { $0 + $1.fat },
                carbs: fetchedMeals.reduce(0) { $0 + $1.carbs }
            )
            dailyHistory[today] = summary
            persistHistorySnapshot(for: today, summary: summary)
        } catch {
            if isCancellationError(error) {
                return
            }
            dailyHistory[today] = dailyHistory[today] ?? .zero
        }
    }

    private func loadMealHistorySnapshot(forWeekContaining day: Date, generation: Int) async {
        guard authService != nil else { return }

        let calendar = Calendar.current
        let weekStart = startOfWeek(for: day)
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return }

        for targetDay in daysInRange(from: weekStart, through: min(weekEnd, calendar.startOfDay(for: .now))) {
            guard generation == historyLoadGeneration else { return }
            let dayStart = calendar.startOfDay(for: targetDay)

            if dayStart == activeDay {
                dailyHistory[dayStart] = NutritionSummary(
                    calories: totalCalories,
                    protein: totalProtein,
                    fat: totalFat,
                    carbs: totalCarbs
                )
                continue
            }

            do {
                let fetchedMeals = try await fetchMeals(for: dayStart)
                guard generation == historyLoadGeneration else { return }
                let summary = NutritionSummary(
                    calories: fetchedMeals.reduce(0) { $0 + $1.calories },
                    protein: fetchedMeals.reduce(0) { $0 + $1.protein },
                    fat: fetchedMeals.reduce(0) { $0 + $1.fat },
                    carbs: fetchedMeals.reduce(0) { $0 + $1.carbs }
                )
                dailyHistory[dayStart] = summary
                persistHistorySnapshot(for: dayStart, summary: summary)
            } catch {
                if isCancellationError(error) {
                    return
                }
                dailyHistory[dayStart] = dailyHistory[dayStart] ?? .zero
            }
        }
    }

    private func loadCurrentDayHistorySnapshotIfNeeded(generation: Int) async {
        guard authService != nil else { return }
        guard generation == historyLoadGeneration else { return }

        let today = Calendar.current.startOfDay(for: .now)
        if today == activeDay {
            dailyHistory[today] = NutritionSummary(
                calories: totalCalories,
                protein: totalProtein,
                fat: totalFat,
                carbs: totalCarbs
            )
            return
        }

        do {
            let fetchedMeals = try await fetchMeals(for: today)
            guard generation == historyLoadGeneration else { return }
            let summary = NutritionSummary(
                calories: fetchedMeals.reduce(0) { $0 + $1.calories },
                protein: fetchedMeals.reduce(0) { $0 + $1.protein },
                fat: fetchedMeals.reduce(0) { $0 + $1.fat },
                carbs: fetchedMeals.reduce(0) { $0 + $1.carbs }
            )
            dailyHistory[today] = summary
            persistHistorySnapshot(for: today, summary: summary)
        } catch {
            if isCancellationError(error) {
                return
            }
            dailyHistory[today] = dailyHistory[today] ?? .zero
        }
    }

    private func startOfWeek(for day: Date) -> Date {
        Self.startOfWeek(for: day)
    }

    private func daysInRange(from start: Date, through end: Date) -> [Date] {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        guard normalizedStart <= normalizedEnd else { return [] }

        var days: [Date] = []
        var currentDay = normalizedStart
        while currentDay <= normalizedEnd {
            days.append(currentDay)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }
        return days
    }

    private func mealsOnDay(_ day: Date) -> [MealEntry] {
        let start = Calendar.current.startOfDay(for: day)
        return meals.filter { Calendar.current.isDate($0.scheduledAt, inSameDayAs: start) }
    }

    private func storedMeals(for day: Date) -> [MealEntry] {
        let start = Calendar.current.startOfDay(for: day)
        if Calendar.current.isDate(activeDay, inSameDayAs: start) {
            return mealsOnDay(start)
        }
        return Self.cachedMeals(for: start, from: loadedMealCacheSnapshot())
    }

    private func storedMealRecord(id: UUID) -> (meal: MealEntry, day: Date)? {
        if let meal = meals.first(where: { $0.id == id }) {
            return (meal, Calendar.current.startOfDay(for: meal.scheduledAt))
        }

        if let snapshot = loadedMealCacheSnapshot() {
            for dayMeals in snapshot.mealsByDay.values {
                if let meal = dayMeals.first(where: { $0.id == id }) {
                    return (meal, Calendar.current.startOfDay(for: meal.scheduledAt))
                }
            }
        }

        return nil
    }

    private func applyMealDeletion(id: UUID, on day: Date?) {
        let resolvedDay = day ?? storedMealRecord(id: id)?.day
        mealCategoryAssignments.removeValue(forKey: id.uuidString)
        persistMealCategoryAssignments()

        guard let resolvedDay else { return }

        let updatedMeals = storedMeals(for: resolvedDay)
            .filter { $0.id != id }
            .sorted(by: { $0.scheduledAt < $1.scheduledAt })

        if Calendar.current.isDate(activeDay, inSameDayAs: resolvedDay) {
            meals = updatedMeals
        }

        registerHistory(for: resolvedDay, meals: updatedMeals)
        // The calories left Health with the meal, rather than staying behind as
        // a day the reader can no longer account for.
        Task { await syncNutritionToHealthIfEnabled(for: resolvedDay) }
    }

    private func registerHistory(for day: Date, meals: [MealEntry]) {
        let start = Calendar.current.startOfDay(for: day)
        let summary = Self.nutritionSummary(from: meals)
        dailyHistory[start] = summary
        persistMealsSnapshot(for: start, meals: meals, summary: summary)
        if Calendar.current.isDateInToday(start) {
            persistWidgetTodaySnapshot()
        }
    }

    private func restoreCachedMealsIfAvailable(resetWhenMissing: Bool) {
        applyDiaryCacheSnapshot(loadedMealCacheSnapshot(), resetWhenMissing: resetWhenMissing)
    }

    private func restoreCachedMeals(for day: Date) {
        let dayStart = Calendar.current.startOfDay(for: day)
        let snapshot = loadedMealCacheSnapshot()

        if let snapshot {
            dailyHistory.merge(Self.cachedDailyHistory(from: snapshot)) { _, newValue in newValue }
        }

        meals = Self.cachedMeals(for: dayStart, from: snapshot)

        if let summary = Self.cachedSummary(for: dayStart, from: snapshot) {
            dailyHistory[dayStart] = summary
        } else {
            dailyHistory[dayStart] = dailyHistory[dayStart] ?? Self.nutritionSummary(from: meals)
        }
    }

    private func applyDiaryCacheSnapshot(_ snapshot: DiaryCacheSnapshot?, resetWhenMissing: Bool) {
        guard let snapshot else {
            if resetWhenMissing {
                meals = []
                dailyHistory = [:]
                mealCacheSnapshot = nil
                hasLoadedMealCacheSnapshot = true
            }
            return
        }

        mealCacheSnapshot = snapshot
        hasLoadedMealCacheSnapshot = true
        meals = Self.cachedMeals(for: activeDay, from: snapshot)
        dailyHistory = Self.cachedDailyHistory(from: snapshot)
    }

    private func persistMealsSnapshot(for day: Date, meals: [MealEntry], summary: NutritionSummary? = nil) {
        guard authService != nil else { return }

        let dayKey = Self.dayKey(from: day)
        let resolvedSummary = summary ?? Self.nutritionSummary(from: meals)
        updateMealCacheSnapshot { snapshot in
            snapshot.mealsByDay[dayKey] = meals.sorted(by: { $0.scheduledAt < $1.scheduledAt })
            snapshot.dailyHistoryByDay[dayKey] = resolvedSummary
        }
    }

    private func persistHistorySnapshot(for day: Date, summary: NutritionSummary) {
        guard authService != nil else { return }

        let dayKey = Self.dayKey(from: day)
        updateMealCacheSnapshot { snapshot in
            snapshot.dailyHistoryByDay[dayKey] = summary
        }

        if Calendar.current.isDateInToday(day) {
            persistWidgetTodaySnapshot()
        }
    }

    private func updateMealCacheSnapshot(_ update: (inout DiaryCacheSnapshot) -> Void) {
        var snapshot = loadedMealCacheSnapshot()
            ?? DiaryCacheSnapshot(mealsByDay: [:], dailyHistoryByDay: [:])
        update(&snapshot)
        let trimmed = Self.trimmedMealCacheSnapshot(snapshot)
        mealCacheSnapshot = trimmed
        hasLoadedMealCacheSnapshot = true
        CachedJSONStore.save(trimmed, key: Self.mealCacheKeyPrefix + cacheScopeID)
    }

    private func normalizedCategoryID(for meal: MealEntry) -> String {
        let trimmed = meal.mealCategoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? meal.kind.rawValue : trimmed
    }

    private func matchedCategoryID(forMealTitle title: String) -> String? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }

        return visibleMealCategories.first(where: {
            $0.title.compare(normalizedTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            || $0.displayTitle.compare(normalizedTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })?.id
    }

    private func fallbackCategory(for id: String, sortOrder: Int) -> MealCategory {
        if let legacyKind = MealKind(rawValue: id) {
            return legacyKind.asMealCategory(sortOrder: sortOrder)
        }
        return MealCategory(
            id: id,
            title: id.replacingOccurrences(of: "_", with: " ").capitalized,
            symbolName: "fork.knife",
            sortOrder: sortOrder,
            isEnabled: true,
            preferredHour: 12,
            preferredMinute: 0,
            goalSharePercent: 25
        )
    }

    private func persistDailyGoal() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(dailyGoal) {
            defaults.set(data, forKey: Self.dailyGoalKeyPrefix + scopeUserID)
        }
    }

    private func persistDietPlan() {
        UserDefaults.standard.set(dietPlan.rawValue, forKey: Self.dietPlanKeyPrefix + scopeUserID)
    }

    private func persistGoalOverrides() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(dailyGoalOverrides) {
            defaults.set(data, forKey: Self.dailyGoalOverrideKeyPrefix + scopeUserID)
        }
    }

    private func persistMealCategories() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(mealCategories) {
            defaults.set(data, forKey: Self.mealCategoriesKeyPrefix + scopeUserID)
        }
    }

    private func persistMealCategoryAssignment(mealID: UUID, categoryID: String) {
        mealCategoryAssignments[mealID.uuidString] = categoryID
        persistMealCategoryAssignments()
    }

    private func persistMealCategoryAssignments() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(mealCategoryAssignments) {
            defaults.set(data, forKey: Self.mealCategoryAssignmentsKeyPrefix + scopeUserID)
        }
    }

    private func persistCheatMealDays() {
        let defaults = UserDefaults.standard
        let sortedKeys = Array(cheatMealDays).sorted()
        if let data = try? JSONEncoder().encode(sortedKeys) {
            defaults.set(data, forKey: Self.cheatMealDaysKeyPrefix + scopeUserID)
        }
    }

    private func persistWaterIntake() {
        let defaults = UserDefaults.standard
        let key = Self.waterIntakeKeyPrefix + scopeUserID
        if let data = try? JSONEncoder().encode(waterIntakeByDay) {
            defaults.set(data, forKey: key)
            Self.sharedDefaults?.set(data, forKey: key)
        }
        persistWidgetTodaySnapshot()
    }

    private func persistWaterGoal() {
        let defaults = UserDefaults.standard
        let key = Self.waterGoalKeyPrefix + scopeUserID
        defaults.set(dailyWaterGoalMilliliters, forKey: key)
        Self.sharedDefaults?.set(dailyWaterGoalMilliliters, forKey: key)
        persistWidgetTodaySnapshot()
    }

    private func persistWidgetTodaySnapshot() {
        guard let sharedDefaults = Self.sharedDefaults else { return }

        let today = Calendar.current.startOfDay(for: .now)
        let todayKey = dayKey(for: today)
        let cacheSnapshot = loadedMealCacheSnapshot()

        let todayMeals: [MealEntry]
        if Calendar.current.isDate(activeDay, inSameDayAs: today) {
            todayMeals = mealsOnDay(today)
        } else {
            todayMeals = Self.cachedMeals(for: today, from: cacheSnapshot)
        }

        let summary: NutritionSummary
        if let cachedSummary = dailyHistory[today] {
            summary = cachedSummary
        } else {
            summary = Self.nutritionSummary(from: todayMeals)
        }

        let todayGoal = goal(for: today)
        let quickAddItems = makeWidgetQuickAddItems()
        let snapshot = WidgetTodaySnapshot(
            dayKey: todayKey,
            calories: summary.calories,
            protein: summary.protein,
            fat: summary.fat,
            carbs: summary.carbs,
            isWaterTrackingEnabled: appSettings.isWaterTrackingEnabled,
            caloriesGoal: todayGoal.calories,
            proteinGoal: goalProteinGrams(for: today),
            fatGoal: goalFatGrams(for: today),
            carbsGoal: goalCarbsGrams(for: today),
            waterIntakeMilliliters: waterIntakeByDay[todayKey] ?? 0,
            waterGoalMilliliters: dailyWaterGoalMilliliters,
            waterStepMilliliters: appSettings.waterWidgetStepMilliliters,
            loggingStreakDays: completedWidgetLoggingStreakDays(endingBefore: today, cacheSnapshot: cacheSnapshot),
            meals: makeWidgetMealSummaries(from: todayMeals),
            mealItems: makeWidgetMealItemSummaries(from: todayMeals),
            mealCategories: makeWidgetMealCategories(from: todayMeals, goal: todayGoal),
            products: quickAddItems.products,
            recipes: quickAddItems.recipes,
            mealTemplates: quickAddItems.mealTemplates,
            updatedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let previousData = sharedDefaults.data(forKey: Self.widgetTodaySnapshotKey)
        let previousScope = sharedDefaults.string(forKey: Self.widgetScopeUserIDKey)
        if previousData == data && previousScope == scopeUserID {
            return
        }

        sharedDefaults.set(data, forKey: Self.widgetTodaySnapshotKey)
        sharedDefaults.set(scopeUserID, forKey: Self.widgetScopeUserIDKey)
        reloadWidgetTimelines()
    }

    private func completedWidgetLoggingStreakDays(endingBefore today: Date, cacheSnapshot: DiaryCacheSnapshot?) -> Int {
        let calendar = Calendar.current
        var cursor = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today)) ?? today
        var streak = 0

        while streak < 3_650 {
            let key = dayKey(for: cursor)
            let summary = dailyHistory[cursor] ?? cacheSnapshot?.dailyHistoryByDay[key]
            let hasNutrition = (summary?.calories ?? 0) > 0
                || (summary?.protein ?? 0) > 0
                || (summary?.fat ?? 0) > 0
                || (summary?.carbs ?? 0) > 0
            let hasMeals = !(cacheSnapshot?.mealsByDay[key] ?? []).isEmpty
            guard hasNutrition || hasMeals else { break }

            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    private func makeWidgetMealSummaries(from meals: [MealEntry]) -> [WidgetTodayMealSummary] {
        meals
            .sorted(by: { $0.scheduledAt < $1.scheduledAt })
            .prefix(12)
            .map { meal in
                WidgetTodayMealSummary(
                    id: meal.id.uuidString,
                    title: meal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? category(for: normalizedCategoryID(for: meal)).displayTitle
                        : meal.title,
                    categoryID: normalizedCategoryID(for: meal),
                    categoryTitle: category(for: normalizedCategoryID(for: meal)).displayTitle,
                    calories: meal.calories,
                    scheduledAt: meal.scheduledAt
                )
            }
    }

    private func makeWidgetMealItemSummaries(from meals: [MealEntry]) -> [WidgetTodayMealItemSummary] {
        meals
            .sorted(by: { $0.scheduledAt < $1.scheduledAt })
            .flatMap { meal -> [WidgetTodayMealItemSummary] in
                let categoryID = normalizedCategoryID(for: meal)
                let categoryTitle = category(for: categoryID).displayTitle

                if meal.items.isEmpty {
                    let title = meal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? categoryTitle
                        : meal.title
                    return [
                        WidgetTodayMealItemSummary(
                            id: "meal-\(meal.id.uuidString)",
                            mealID: meal.id.uuidString,
                            itemID: nil,
                            title: title,
                            subtitle: nil,
                            categoryID: categoryID,
                            categoryTitle: categoryTitle,
                            calories: meal.calories,
                            scheduledAt: meal.scheduledAt
                        )
                    ]
                }

                return meal.items.map { item in
                    let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title: String
                    if trimmedName == "Ручной ввод КБЖУ"
                        || trimmedName == NSLocalizedString("addmeal.item.manual_title", comment: "Manual nutrition item title") {
                        title = NSLocalizedString("addmeal.item.manual_title", comment: "Manual nutrition item title")
                    } else if trimmedName.isEmpty {
                        title = categoryTitle
                    } else {
                        title = trimmedName
                    }

                    return WidgetTodayMealItemSummary(
                        id: "\(meal.id.uuidString)-\(item.id.uuidString)",
                        mealID: meal.id.uuidString,
                        itemID: item.id.uuidString,
                        title: title,
                        subtitle: widgetMealItemSubtitle(for: item),
                        categoryID: categoryID,
                        categoryTitle: categoryTitle,
                        calories: item.calories,
                        scheduledAt: meal.scheduledAt
                    )
                }
            }
            .prefix(36)
            .map { $0 }
    }

    private func widgetMealItemSubtitle(for item: MealItemEntry) -> String? {
        let trimmedServingLabel = item.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.unit == .serving,
           !trimmedServingLabel.isEmpty {
            let quantity = max(item.amount, 1)
            if abs(quantity - 1) < 0.0001 {
                return trimmedServingLabel
            }

            return "\(formattedFoodAmountValue(quantity, maximumFractionDigits: 1)) × \(trimmedServingLabel)"
        }

        let amount = item.unit == .serving ? max(item.amount, 1) : item.amount
        guard amount > 0 else { return nil }
        return "\(formattedFoodAmountValue(amount, maximumFractionDigits: 1)) \(item.unit.shortTitle)"
    }

    /// The calories this meal is planned to account for.
    ///
    /// Zero when no share has been set, which the widget reads as "no target"
    /// and draws as an empty ring rather than a full one.
    private func targetCalories(for category: MealCategory, goal: DailyNutritionGoal) -> Int {
        guard category.goalSharePercent > 0, goal.calories > 0 else { return 0 }
        return Int((Double(goal.calories) * Double(category.goalSharePercent) / 100).rounded())
    }

    private func consumedCalories(for categoryID: String, in meals: [MealEntry]) -> Int {
        meals
            .filter { $0.mealCategoryID == categoryID }
            .reduce(0) { $0 + $1.calories }
    }

    private func makeWidgetMealCategories(from meals: [MealEntry], goal: DailyNutritionGoal) -> [WidgetMealCategorySummary] {
        visibleMealCategories
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.displayTitle < rhs.displayTitle
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .map {
            WidgetMealCategorySummary(
                id: $0.id,
                title: $0.displayTitle,
                symbolName: $0.symbolName,
                targetCalories: targetCalories(for: $0, goal: goal),
                calories: consumedCalories(for: $0.id, in: meals)
            )
        }
    }

    private func makeWidgetQuickAddItems() -> (
        products: [WidgetQuickAddItem],
        recipes: [WidgetQuickAddItem],
        mealTemplates: [WidgetQuickAddItem]
    ) {
        let products = (catalogService?.products ?? [])
            .prefix(10)
            .map(makeWidgetQuickAddItem(from:))
        let recipes = (catalogService?.recipes ?? [])
            .prefix(10)
            .map(makeWidgetQuickAddItem(from:))
        let mealTemplates = (catalogService?.mealTemplates ?? [])
            .prefix(10)
            .map(makeWidgetQuickAddItem(from:))

        return (Array(products), Array(recipes), Array(mealTemplates))
    }

    private func makeWidgetQuickAddItem(from product: ProductSummary) -> WidgetQuickAddItem {
        let selection = product.selectionPayload()
        let mealItem = MealItemEntry(
            id: UUID(),
            name: product.name,
            amount: selection.amount,
            unit: selection.unit,
            note: "",
            servingLabel: selection.servingLabel,
            caloriesPer100g: product.caloriesPer100g,
            proteinPer100g: product.proteinPer100g,
            fatPer100g: product.fatPer100g,
            carbsPer100g: product.carbsPer100g,
            productID: product.id,
            recipeID: nil
        )
        let trimmedBrand = product.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = trimmedBrand.isEmpty
            ? (product.defaultSelectableServingOption?.pickerTitle ?? product.servingUnit.title)
            : trimmedBrand

        return WidgetQuickAddItem(
            id: product.id.uuidString,
            title: product.name,
            subtitle: subtitle,
            calories: mealItem.calories
        )
    }

    private func makeWidgetQuickAddItem(from recipe: RecipeSummary) -> WidgetQuickAddItem {
        let trimmedCategory = recipe.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = trimmedCategory.isEmpty ? "\(max(recipe.servings, 1)) servings" : trimmedCategory

        return WidgetQuickAddItem(
            id: recipe.id.uuidString,
            title: recipe.title,
            subtitle: subtitle,
            calories: recipe.caloriesPerServing
        )
    }

    private func makeWidgetQuickAddItem(from mealTemplate: MealTemplateSummary) -> WidgetQuickAddItem {
        let itemCount = mealTemplate.items.count
        let subtitle = itemCount == 1 ? "1 item" : "\(itemCount) items"

        return WidgetQuickAddItem(
            id: mealTemplate.id.uuidString,
            title: mealTemplate.title,
            subtitle: subtitle,
            calories: mealTemplate.calories
        )
    }

    private func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: Self.waterWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.quickMealWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.nutritionWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.statsWidgetKind)
    }

    private func markLocalNutritionSettingsUpdatedNow() {
        localNutritionSettingsUpdatedAt = Date()
        persistNutritionSettingsUpdatedAt()
    }

    private func persistNutritionSettingsUpdatedAt() {
        let defaults = UserDefaults.standard
        defaults.set(localNutritionSettingsUpdatedAt.timeIntervalSince1970, forKey: Self.nutritionSettingsUpdatedAtKeyPrefix + scopeUserID)
    }

    private func knownImportedMealShareCodes() -> Set<String> {
        let defaults = UserDefaults.standard
        let values = defaults.stringArray(forKey: Self.importedMealShareCodesKeyPrefix + scopeUserID) ?? []
        return Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private func markSharedMealImported(code: String) {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else { return }

        let defaults = UserDefaults.standard
        let key = Self.importedMealShareCodesKeyPrefix + scopeUserID
        var values = defaults.stringArray(forKey: key) ?? []
        guard !values.contains(normalizedCode) else { return }
        values.append(normalizedCode)
        defaults.set(values, forKey: key)
    }

    private func persistCalorieOnboardingCompleted(_ completed: Bool) {
        guard !Self.isCalorieOnboardingPersistenceDisabled else { return }
        let defaults = UserDefaults.standard
        defaults.set(completed, forKey: Self.calorieOnboardingCompletedKeyPrefix + scopeUserID)
    }

    private func restoreCachedCalorieOnboardingState() {
        guard authService != nil else {
            shouldShowCalorieOnboarding = false
            hasResolvedCalorieOnboardingState = true
            return
        }

        if let isCompleted = FoodDiaryService.loadCalorieOnboardingCompleted(scopeUserID: scopeUserID) {
            shouldShowCalorieOnboarding = !isCompleted
            hasResolvedCalorieOnboardingState = true
            return
        }

        if localNutritionSettingsUpdatedAt > .distantPast {
            shouldShowCalorieOnboarding = Self.isCalorieOnboardingPersistenceDisabled
            hasResolvedCalorieOnboardingState = true
            return
        }

        shouldShowCalorieOnboarding = false
        hasResolvedCalorieOnboardingState = false
    }

    private func dayKey(for day: Date) -> String {
        Self.dayKey(from: day)
    }

    private static func normalizeScope(_ rawValue: String?) -> String {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "anon" : trimmed
    }

    private static func normalizeMealCategories(_ categories: [MealCategory]) -> [MealCategory] {
        let fallback = categories.isEmpty ? MealCategory.default : categories
        let ordered = fallback.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.sortOrder < rhs.sortOrder
        }

        var normalized = ordered.enumerated().map { index, category in
            var updated = category.normalized
            updated.sortOrder = index
            return updated
        }

        if !normalized.contains(where: { $0.isEnabled }), !normalized.isEmpty {
            normalized[0].isEnabled = true
        }

        let enabledCategories = normalized.filter(\ .isEnabled)
        let categoriesForShare = enabledCategories.isEmpty ? normalized : enabledCategories
        let totalShare = categoriesForShare.reduce(0) { $0 + $1.goalSharePercent }
        guard totalShare > 0 else {
            let share = max(1, 100 / max(normalized.count, 1))
            return normalized.enumerated().map { index, category in
                var updated = category
                updated.goalSharePercent = index == normalized.count - 1 ? max(0, 100 - share * (normalized.count - 1)) : share
                return updated
            }
        }

        return normalized.enumerated().map { index, category in
            var updated = category
            if index == normalized.count - 1 {
                let allocated = normalized.prefix(index).reduce(0) { partial, item in
                    partial + Int((Double(item.goalSharePercent) / Double(totalShare) * 100.0).rounded())
                }
                updated.goalSharePercent = max(0, 100 - allocated)
            } else {
                updated.goalSharePercent = Int((Double(category.goalSharePercent) / Double(totalShare) * 100.0).rounded())
            }
            return updated
        }
    }

    private static func loadDailyGoal(scopeUserID: String) -> DailyNutritionGoal {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.dailyGoalKeyPrefix + scopeUserID),
              let restored = try? JSONDecoder().decode(DailyNutritionGoal.self, from: data) else {
            return DailyNutritionGoal.default
        }
                return restored.sanitized
    }

    private static func loadDietPlan(scopeUserID: String) -> DietPlanOption {
        let storedValue = UserDefaults.standard.string(forKey: Self.dietPlanKeyPrefix + scopeUserID) ?? ""
        return DietPlanOption.normalized(rawValue: storedValue)
    }

    private static func loadGoalOverrides(scopeUserID: String) -> [String: DailyNutritionGoal] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.dailyGoalOverrideKeyPrefix + scopeUserID),
              let restored = try? JSONDecoder().decode([String: DailyNutritionGoal].self, from: data) else {
            return [:]
        }
                return restored.mapValues(\.sanitized)
    }

    private static func loadMealCategories(scopeUserID: String) -> [MealCategory] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.mealCategoriesKeyPrefix + scopeUserID),
              let restored = try? JSONDecoder().decode([MealCategory].self, from: data) else {
            return MealCategory.default
        }
        return normalizeMealCategories(restored)
    }

    private static func loadMealCategoryAssignments(scopeUserID: String) -> [String: String] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.mealCategoryAssignmentsKeyPrefix + scopeUserID),
              let restored = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return restored
    }

    private static func loadCheatMealDays(scopeUserID: String) -> Set<String> {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.cheatMealDaysKeyPrefix + scopeUserID),
              let restored = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(restored.compactMap { normalizedDayKey(from: $0) })
    }

    private static func loadWaterIntake(scopeUserID: String) -> [String: Int] {
        let key = Self.waterIntakeKeyPrefix + scopeUserID
        if let sharedDefaults = Self.sharedDefaults,
           let data = sharedDefaults.data(forKey: key),
           let restored = try? JSONDecoder().decode([String: Int].self, from: data) {
            return restored
        }

        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: key),
              let restored = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        Self.sharedDefaults?.set(data, forKey: key)
        return restored
    }

    private static func loadWaterGoal(scopeUserID: String) -> Int {
        let key = Self.waterGoalKeyPrefix + scopeUserID
        if let sharedDefaults = Self.sharedDefaults, sharedDefaults.object(forKey: key) != nil {
            let value = sharedDefaults.integer(forKey: key)
            return value > 0 ? value : 2000
        }

        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) != nil {
            let value = defaults.integer(forKey: key)
            Self.sharedDefaults?.set(value, forKey: key)
            return value > 0 ? value : 2000
        }
        return 2000
    }

    private static func loadNutritionSettingsUpdatedAt(scopeUserID: String) -> Date {
        let defaults = UserDefaults.standard
        let value = defaults.double(forKey: Self.nutritionSettingsUpdatedAtKeyPrefix + scopeUserID)
        if value > 0 {
            return Date(timeIntervalSince1970: value)
        }
        return .distantPast
    }

    private static func loadCalorieOnboardingCompleted(scopeUserID: String) -> Bool? {
        guard !isCalorieOnboardingPersistenceDisabled else { return nil }
        let defaults = UserDefaults.standard
        let key = Self.calorieOnboardingCompletedKeyPrefix + scopeUserID
        guard defaults.object(forKey: key) != nil else {
            return nil
        }
        return defaults.bool(forKey: key)
    }

    private static func normalizedDayKey(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count >= 10 {
            let candidate = String(trimmed.prefix(10))
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if formatter.date(from: candidate) != nil {
                return candidate
            }
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: trimmed) {
            return dayKey(from: date)
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: trimmed) {
            return dayKey(from: date)
        }
        return nil
    }

    private static func dayKey(from day: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day],
            from: Calendar.current.startOfDay(for: day)
        )
        guard let year = components.year, let month = components.month, let day = components.day else {
            return "1970-01-01"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func nutritionStatisticsCacheAnchor(period: NutritionStatsPeriod, anchor: Date) -> Date {
        let calendar = Calendar.current
        let normalizedAnchor = calendar.startOfDay(for: anchor)

        switch period {
        case .day:
            return normalizedAnchor
        case .week:
            return startOfWeek(for: normalizedAnchor)
        case .month:
            let components = calendar.dateComponents([.year, .month], from: normalizedAnchor)
            return calendar.date(from: components) ?? normalizedAnchor
        case .halfYear:
            var components = calendar.dateComponents([.year, .month], from: normalizedAnchor)
            components.month = (components.month ?? 1) <= 6 ? 1 : 7
            components.day = 1
            return calendar.date(from: components) ?? normalizedAnchor
        case .year:
            let components = calendar.dateComponents([.year], from: normalizedAnchor)
            return calendar.date(from: components) ?? normalizedAnchor
        }
    }

    private static func startOfWeek(for day: Date) -> Date {
        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: normalizedDay)
        let firstWeekday = calendar.firstWeekday
        let distance = (weekday - firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -distance, to: normalizedDay) ?? normalizedDay
    }

    private static func normalizeCacheScope(_ rawValue: String?) -> String {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "anon" : trimmed.lowercased()
    }

    private func loadedMealCacheSnapshot() -> DiaryCacheSnapshot? {
        if hasLoadedMealCacheSnapshot {
            return mealCacheSnapshot
        }

        let snapshot = Self.loadMealCacheSnapshot(scopeID: cacheScopeID)
        mealCacheSnapshot = snapshot
        hasLoadedMealCacheSnapshot = true
        return snapshot
    }

    private static func loadMealCacheSnapshot(scopeID: String) -> DiaryCacheSnapshot? {
        CachedJSONStore.load(DiaryCacheSnapshot.self, key: Self.mealCacheKeyPrefix + scopeID)
    }

    private func saveNutritionStatisticsCache(_ snapshot: NutritionStatisticsSnapshot, period: NutritionStatsPeriod, anchor: Date) {
        CachedJSONStore.save(
            snapshot,
            key: Self.nutritionStatisticsCacheKey(scopeID: cacheScopeID, period: period, anchor: anchor)
        )
    }

    private static func loadNutritionStatisticsCache(
        scopeID: String,
        period: NutritionStatsPeriod,
        anchor: Date
    ) -> NutritionStatisticsSnapshot? {
        CachedJSONStore.load(
            NutritionStatisticsSnapshot.self,
            key: nutritionStatisticsCacheKey(scopeID: scopeID, period: period, anchor: anchor)
        )
    }

    private static func nutritionStatisticsCacheKey(
        scopeID: String,
        period: NutritionStatsPeriod,
        anchor: Date
    ) -> String {
        nutritionStatisticsCacheKeyPrefix + [
            scopeID,
            period.rawValue,
            dayKey(from: nutritionStatisticsCacheAnchor(period: period, anchor: anchor))
        ].joined(separator: ".")
    }

    private static func cachedMeals(for day: Date, from snapshot: DiaryCacheSnapshot?) -> [MealEntry] {
        guard let snapshot else { return [] }
        return (snapshot.mealsByDay[dayKey(from: day)] ?? []).sorted(by: { $0.scheduledAt < $1.scheduledAt })
    }

    private static func cachedSummary(for day: Date, from snapshot: DiaryCacheSnapshot?) -> NutritionSummary? {
        snapshot?.dailyHistoryByDay[dayKey(from: day)]
    }

    private static func cachedDailyHistory(from snapshot: DiaryCacheSnapshot?) -> [Date: NutritionSummary] {
        guard let snapshot else { return [:] }

        var restored: [Date: NutritionSummary] = [:]
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        for (key, summary) in snapshot.dailyHistoryByDay {
            guard let date = formatter.date(from: key) else { continue }
            restored[Calendar.current.startOfDay(for: date)] = summary
        }
        return restored
    }

    private static func trimmedMealCacheSnapshot(_ snapshot: DiaryCacheSnapshot) -> DiaryCacheSnapshot {
        DiaryCacheSnapshot(
            mealsByDay: trimmedCacheValues(snapshot.mealsByDay, limit: maxCachedMealDays),
            dailyHistoryByDay: trimmedCacheValues(snapshot.dailyHistoryByDay, limit: maxCachedHistoryDays)
        )
    }

    private static func trimmedCacheValues<Value>(_ values: [String: Value], limit: Int) -> [String: Value] {
        guard values.count > limit else { return values }

        let keepKeys = Set(values.keys.sorted(by: >).prefix(limit))
        return values.reduce(into: [:]) { partial, pair in
            guard keepKeys.contains(pair.key) else { return }
            partial[pair.key] = pair.value
        }
    }

    private static func nutritionSummary(from meals: [MealEntry]) -> NutritionSummary {
        NutritionSummary(
            calories: meals.reduce(0) { $0 + $1.calories },
            protein: meals.reduce(0) { $0 + $1.protein },
            fat: meals.reduce(0) { $0 + $1.fat },
            carbs: meals.reduce(0) { $0 + $1.carbs }
        )
    }

    private static func previewMeals(for day: Date) -> [MealEntry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        return sampleMeals.map { meal in
            var updated = meal
            let hour = calendar.component(.hour, from: meal.scheduledAt)
            let minute = calendar.component(.minute, from: meal.scheduledAt)
            updated.scheduledAt = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) ?? dayStart
            return updated
        }
    }

    private static func previewHistory(centeredOn day: Date, selectedDayMeals: [MealEntry]? = nil) -> [Date: NutritionSummary] {
        let calendar = Calendar.current
        let centerDay = calendar.startOfDay(for: day)
        let sampleCalories = [1780, 2040, 1910, 2250, 2380, 2120, 1980, 2460, 2210, 2090, 1940, 2310, 2170, 1880, 2420, 2260, 2010, 2140, 2050, 2370, 2190]
        var history: [Date: NutritionSummary] = [:]

        for (index, offset) in (-10...10).enumerated() {
            guard let targetDay = calendar.date(byAdding: .day, value: offset, to: centerDay) else { continue }
            let calories = sampleCalories[index]
            history[targetDay] = NutritionSummary(
                calories: calories,
                protein: Int((Double(calories) * 0.28 / 4.0).rounded()),
                fat: Int((Double(calories) * 0.30 / 9.0).rounded()),
                carbs: Int((Double(calories) * 0.42 / 4.0).rounded())
            )
        }

        if let selectedDayMeals {
            history[centerDay] = NutritionSummary(
                calories: selectedDayMeals.reduce(0) { $0 + $1.calories },
                protein: selectedDayMeals.reduce(0) { $0 + $1.protein },
                fat: selectedDayMeals.reduce(0) { $0 + $1.fat },
                carbs: selectedDayMeals.reduce(0) { $0 + $1.carbs }
            )
        }

        return history
    }
}
