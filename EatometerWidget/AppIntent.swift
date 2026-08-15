import AppIntents
import Foundation
import WidgetKit

enum EatometerWidgetStore {
    static let appGroupID = "group.com.goeatometer.Eatometer.shared"
    static let waterIntakeKeyPrefix = "Eatometer.diary.waterIntake."
    static let waterGoalKeyPrefix = "Eatometer.diary.waterGoal."
    static let snapshotKey = "Eatometer.widget.today.snapshot"
    static let scopeUserIDKey = "Eatometer.widget.scopeUserID"
    static let pendingWaterExportsKey = "Eatometer.widget.pendingWaterExports"
    static let nutritionRingMetricsKeyPrefix = "Eatometer.widget.nutritionRingMetrics."
    static let waterWidgetStepKeyPrefix = "Eatometer.widget.waterStep."
    static let waterWidgetKind = "EatometerWidget"
    static let quickMealWidgetKind = "EatometerQuickMealWidget"
    static let habitWidgetKind = "EatometerHabitWidget"
    static let nutritionWidgetKind = "EatometerNutritionWidget"
    static let statsWidgetKind = "EatometerStatsWidget"
    static let habitSnapshotKey = "Eatometer.widget.habits.snapshot"
    static let pendingHabitCheckInsKey = "Eatometer.widget.pendingHabitCheckIns"
    static let defaultNutritionRingMetricIDs = ["calories", "protein", "fat"]
    static let defaultWaterWidgetStep = 200

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.startOfDay(for: date))
    }

    static func currentScopeUserID() -> String {
        let scope = sharedDefaults?.string(forKey: scopeUserIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return scope.isEmpty ? "anon" : scope
    }

    static func loadWaterState(for date: Date = .now) -> (dayKey: String, intake: Int, goal: Int) {
        let resolvedDayKey = dayKey(for: date)
        let scopeUserID = currentScopeUserID()
        let intakeKey = waterIntakeKeyPrefix + scopeUserID
        let goalKey = waterGoalKeyPrefix + scopeUserID

        let intakeByDay: [String: Int]
        if let defaults = sharedDefaults,
           let data = defaults.data(forKey: intakeKey),
           let restored = try? JSONDecoder().decode([String: Int].self, from: data) {
            intakeByDay = restored
        } else {
            intakeByDay = [:]
        }

        let goalValue: Int
        if let defaults = sharedDefaults, defaults.object(forKey: goalKey) != nil {
            let storedGoal = defaults.integer(forKey: goalKey)
            goalValue = storedGoal > 0 ? storedGoal : 2000
        } else {
            goalValue = 2000
        }

        return (resolvedDayKey, intakeByDay[resolvedDayKey] ?? 0, goalValue)
    }

    static func loadTodaySnapshot() -> EatometerTodaySnapshot? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(EatometerTodaySnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static func loadHabitSnapshot() -> EatometerHabitWidgetSnapshot? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: habitSnapshotKey),
              let snapshot = try? JSONDecoder().decode(EatometerHabitWidgetSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static func loadNutritionRingMetricIDs() -> [String] {
        let key = nutritionRingMetricsKeyPrefix + currentScopeUserID()
        let storedIDs = sharedDefaults?.stringArray(forKey: key) ?? defaultNutritionRingMetricIDs

        var resolvedIDs: [String] = []
        for id in storedIDs where !resolvedIDs.contains(id) {
            resolvedIDs.append(id)
        }

        for fallbackID in defaultNutritionRingMetricIDs where !resolvedIDs.contains(fallbackID) {
            guard resolvedIDs.count < 3 else { break }
            resolvedIDs.append(fallbackID)
        }

        for fallbackID in ["calories", "protein", "fat", "carbs"] where !resolvedIDs.contains(fallbackID) {
            guard resolvedIDs.count < 3 else { break }
            resolvedIDs.append(fallbackID)
        }

        return Array(resolvedIDs.prefix(3))
    }

    static func loadWaterWidgetStep() -> Int {
        let key = waterWidgetStepKeyPrefix + currentScopeUserID()
        guard let defaults = sharedDefaults, defaults.object(forKey: key) != nil else {
            return defaultWaterWidgetStep
        }
        let stored = defaults.integer(forKey: key)
        return max(50, min(2000, stored))
    }

    static func adjustWater(by delta: Int, for date: Date = .now) {
        guard let defaults = sharedDefaults else { return }

        let scopeUserID = currentScopeUserID()
        let intakeKey = waterIntakeKeyPrefix + scopeUserID
        let todayKey = dayKey(for: date)

        var intakeByDay: [String: Int] = [:]
        if let data = defaults.data(forKey: intakeKey),
           let restored = try? JSONDecoder().decode([String: Int].self, from: data) {
            intakeByDay = restored
        }

        let current = intakeByDay[todayKey] ?? 0
        let updatedTotal = max(0, current + delta)
        intakeByDay[todayKey] = updatedTotal
        if let encoded = try? JSONEncoder().encode(intakeByDay) {
            defaults.set(encoded, forKey: intakeKey)
        }

        if delta != 0 {
            var pendingExports: [PendingWidgetWaterExport] = []
            if let data = defaults.data(forKey: pendingWaterExportsKey),
               let restored = try? JSONDecoder().decode([PendingWidgetWaterExport].self, from: data) {
                pendingExports = restored
            }

            pendingExports.append(
                PendingWidgetWaterExport(
                    id: UUID().uuidString,
                    scopeUserID: scopeUserID,
                    dayKey: todayKey,
                    deltaMilliliters: delta,
                    totalMilliliters: updatedTotal,
                    createdAt: Date()
                )
            )

            if let encodedPendingExports = try? JSONEncoder().encode(pendingExports) {
                defaults.set(encodedPendingExports, forKey: pendingWaterExportsKey)
            }
        }

        if var snapshot = loadTodaySnapshot(), snapshot.dayKey == todayKey {
            snapshot.waterIntakeMilliliters = updatedTotal
            snapshot.updatedAt = Date()
            if let encodedSnapshot = try? JSONEncoder().encode(snapshot) {
                defaults.set(encodedSnapshot, forKey: snapshotKey)
            }
        }
    }

    static func habitDayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return dayKey(for: date)
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func currentManualHabitStageDayKey(for habit: EatometerHabitWidgetHabit, at date: Date = .now) -> String? {
        guard habit.trackingMode == "manual",
              let startedAt = habit.attemptStartedAt else {
            return nil
        }
        let elapsed = date.timeIntervalSince(startedAt)
        let completedDays = Int(elapsed / 86_400)
        guard completedDays > 0 else { return nil }
        let stageDate = startedAt.addingTimeInterval(TimeInterval(completedDays - 1) * 86_400)
        return habitDayKey(for: stageDate)
    }

    static func markHabitStage(habitID: String, attemptID: String, dayKey: String) {
        guard let defaults = sharedDefaults else { return }

        var pending: [PendingWidgetHabitCheckIn] = []
        if let data = defaults.data(forKey: pendingHabitCheckInsKey),
           let restored = try? JSONDecoder().decode([PendingWidgetHabitCheckIn].self, from: data) {
            pending = restored
        }

        if !pending.contains(where: { $0.habitID == habitID && $0.attemptID == attemptID && $0.dayKey == dayKey }) {
            pending.append(
                PendingWidgetHabitCheckIn(
                    id: UUID().uuidString,
                    scopeUserID: currentScopeUserID(),
                    habitID: habitID,
                    attemptID: attemptID,
                    dayKey: dayKey,
                    createdAt: Date()
                )
            )
        }

        if let encoded = try? JSONEncoder().encode(pending) {
            defaults.set(encoded, forKey: pendingHabitCheckInsKey)
        }

        if var snapshot = loadHabitSnapshot(),
           let habitIndex = snapshot.habits.firstIndex(where: { $0.id == habitID }),
           !snapshot.habits[habitIndex].checkedDayKeys.contains(dayKey) {
            snapshot.habits[habitIndex].checkedDayKeys.append(dayKey)
            snapshot.habits[habitIndex].checkInCount += 1
            snapshot.updatedAt = Date()
            if let encodedSnapshot = try? JSONEncoder().encode(snapshot) {
                defaults.set(encodedSnapshot, forKey: habitSnapshotKey)
            }
        }
    }
}

private struct PendingWidgetWaterExport: Codable {
    let id: String
    let scopeUserID: String
    let dayKey: String
    let deltaMilliliters: Int
    let totalMilliliters: Int
    let createdAt: Date
}

struct EatometerHabitWidgetSnapshot: Codable {
    var habits: [EatometerHabitWidgetHabit]
    var updatedAt: Date
}

struct EatometerHabitWidgetHabit: Codable, Identifiable, Hashable {
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

struct PendingWidgetHabitCheckIn: Codable {
    let id: String
    let scopeUserID: String
    let habitID: String
    let attemptID: String
    let dayKey: String
    let createdAt: Date
}

struct EatometerTodayMealSummary: Codable {
    let id: String
    let title: String
    let categoryID: String?
    let categoryTitle: String
    let calories: Int
    let scheduledAt: Date
}

struct EatometerTodayMealItemSummary: Codable {
    let id: String
    let mealID: String?
    let itemID: String?
    let title: String
    let subtitle: String?
    let categoryID: String?
    let categoryTitle: String
    let calories: Int
    let scheduledAt: Date
}

struct EatometerMealCategorySummary: Codable {
    let id: String
    let title: String
    let symbolName: String
}

struct EatometerQuickAddItem: Codable {
    let id: String
    let title: String
    let subtitle: String
    let calories: Int
}

struct EatometerTodaySnapshot: Codable {
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
    var waterIntakeMilliliters: Int
    let waterGoalMilliliters: Int
    let waterStepMilliliters: Int
    let loggingStreakDays: Int
    let meals: [EatometerTodayMealSummary]
    let mealItems: [EatometerTodayMealItemSummary]
    let mealCategories: [EatometerMealCategorySummary]
    let products: [EatometerQuickAddItem]
    let recipes: [EatometerQuickAddItem]
    let mealTemplates: [EatometerQuickAddItem]
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case dayKey
        case calories
        case protein
        case fat
        case carbs
        case isWaterTrackingEnabled
        case caloriesGoal
        case proteinGoal
        case fatGoal
        case carbsGoal
        case waterIntakeMilliliters
        case waterGoalMilliliters
        case waterStepMilliliters
        case loggingStreakDays
        case meals
        case mealItems
        case mealCategories
        case products
        case favoriteProducts
        case recipes
        case mealTemplates
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        calories = try container.decode(Int.self, forKey: .calories)
        protein = try container.decode(Int.self, forKey: .protein)
        fat = try container.decode(Int.self, forKey: .fat)
        carbs = try container.decode(Int.self, forKey: .carbs)
        isWaterTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isWaterTrackingEnabled) ?? true
        caloriesGoal = try container.decodeIfPresent(Int.self, forKey: .caloriesGoal) ?? 2000
        proteinGoal = try container.decodeIfPresent(Int.self, forKey: .proteinGoal) ?? 150
        fatGoal = try container.decodeIfPresent(Int.self, forKey: .fatGoal) ?? 67
        carbsGoal = try container.decodeIfPresent(Int.self, forKey: .carbsGoal) ?? 200
        waterIntakeMilliliters = try container.decode(Int.self, forKey: .waterIntakeMilliliters)
        waterGoalMilliliters = try container.decode(Int.self, forKey: .waterGoalMilliliters)
        waterStepMilliliters = try container.decodeIfPresent(Int.self, forKey: .waterStepMilliliters) ?? EatometerWidgetStore.defaultWaterWidgetStep
        loggingStreakDays = try container.decodeIfPresent(Int.self, forKey: .loggingStreakDays) ?? 0
        meals = try container.decodeIfPresent([EatometerTodayMealSummary].self, forKey: .meals) ?? []
        mealItems = try container.decodeIfPresent([EatometerTodayMealItemSummary].self, forKey: .mealItems) ?? []
        mealCategories = try container.decodeIfPresent([EatometerMealCategorySummary].self, forKey: .mealCategories) ?? []
        products = try container.decodeIfPresent([EatometerQuickAddItem].self, forKey: .products)
            ?? container.decodeIfPresent([EatometerQuickAddItem].self, forKey: .favoriteProducts)
            ?? []
        recipes = try container.decodeIfPresent([EatometerQuickAddItem].self, forKey: .recipes) ?? []
        mealTemplates = try container.decodeIfPresent([EatometerQuickAddItem].self, forKey: .mealTemplates) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

enum EatometerWidgetVisualStyle {
    case device
    case soft
    case glass
    case transparent
}

enum EatometerWidgetAccent: String {
    case app
    case blue
    case mint
    case peach
    case berry
    case violet

    var hexValue: String {
        switch self {
        case .app:
            return "#FF7A1A"
        case .blue:
            return "#3BA7FF"
        case .mint:
            return "#35C98B"
        case .peach:
            return "#FF9F6E"
        case .berry:
            return "#F26D9A"
        case .violet:
            return "#8F7CFF"
        }
    }

}

enum EatometerStatsWidgetFocus: String, AppEnum {
    case overview
    case calories
    case macros
    case water
    case streak

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "widget.intent.stats.focus")
    }

    static var caseDisplayRepresentations: [EatometerStatsWidgetFocus: DisplayRepresentation] {
        [
            .overview: DisplayRepresentation(title: "widget.intent.stats.focus.overview"),
            .calories: DisplayRepresentation(title: "widget.intent.stats.focus.calories"),
            .macros: DisplayRepresentation(title: "widget.intent.stats.focus.macros"),
            .water: DisplayRepresentation(title: "widget.intent.stats.focus.water"),
            .streak: DisplayRepresentation(title: "widget.intent.stats.focus.streak")
        ]
    }
}

struct WaterWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.intent.water.title"
    static let description = IntentDescription("widget.intent.water.description")

    init() {}
}

enum QuickMealQuickAddSource: String, AppEnum {
    case mixed
    case products
    case recipes
    case mealTemplates

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "widget.intent.quick_meal.source")
    }

    static var caseDisplayRepresentations: [QuickMealQuickAddSource: DisplayRepresentation] {
        [
            .mixed: DisplayRepresentation(title: "widget.intent.quick_meal.source.mixed"),
            .products: DisplayRepresentation(title: "widget.intent.quick_meal.source.products"),
            .recipes: DisplayRepresentation(title: "widget.intent.quick_meal.source.recipes"),
            .mealTemplates: DisplayRepresentation(title: "widget.intent.quick_meal.source.meal_templates")
        ]
    }
}

enum QuickMealMealSlotLimit: String, AppEnum {
    case four
    case five
    case six

    var count: Int {
        switch self {
        case .four:
            return 4
        case .five:
            return 5
        case .six:
            return 6
        }
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "widget.intent.quick_meal.meal_slots")
    }

    static var caseDisplayRepresentations: [QuickMealMealSlotLimit: DisplayRepresentation] {
        [
            .four: DisplayRepresentation(title: "widget.intent.quick_meal.meal_slots.four"),
            .five: DisplayRepresentation(title: "widget.intent.quick_meal.meal_slots.five"),
            .six: DisplayRepresentation(title: "widget.intent.quick_meal.meal_slots.six")
        ]
    }
}

struct QuickMealWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.intent.quick_meal.title"
    static let description = IntentDescription("widget.intent.quick_meal.description")

    @Parameter(title: "widget.intent.quick_meal.source")
    var quickAddSource: QuickMealQuickAddSource?

    @Parameter(title: "widget.intent.quick_meal.meal_slots")
    var mealSlotLimit: QuickMealMealSlotLimit?

    init() {
        quickAddSource = .mixed
        mealSlotLimit = .four
    }

    init(
        quickAddSource: QuickMealQuickAddSource?,
        mealSlotLimit: QuickMealMealSlotLimit? = nil
    ) {
        self.quickAddSource = quickAddSource
        self.mealSlotLimit = mealSlotLimit ?? .four
    }
}

struct HabitWidgetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "widget.intent.habit.type")
    }

    static var defaultQuery = HabitWidgetEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct HabitWidgetEntityQuery: EntityQuery {
    func entities(for identifiers: [HabitWidgetEntity.ID]) async throws -> [HabitWidgetEntity] {
        allEntities(includeInactive: true).filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HabitWidgetEntity] {
        allEntities(includeInactive: false)
    }

    func defaultResult() async -> HabitWidgetEntity? {
        allEntities(includeInactive: false).first ?? allEntities(includeInactive: true).first
    }

    private func allEntities(includeInactive: Bool) -> [HabitWidgetEntity] {
        let snapshot = EatometerWidgetStore.loadHabitSnapshot()
        return (snapshot?.habits ?? [])
            .filter { includeInactive || ($0.attemptStartedAt != nil && $0.attemptEndedAt == nil) }
            .map { HabitWidgetEntity(id: $0.id, name: $0.name) }
    }
}

struct HabitWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.intent.habit.title"
    static let description = IntentDescription("widget.intent.habit.description")

    @Parameter(title: "widget.intent.habit.habit")
    var habit: HabitWidgetEntity?

    init() {}

    init(habit: HabitWidgetEntity?) {
        self.habit = habit
    }
}

struct NutritionWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.intent.nutrition.title"
    static let description = IntentDescription("widget.intent.nutrition.description")

    init() {}
}

struct StatsWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.intent.stats.title"
    static let description = IntentDescription("widget.intent.stats.description")

    @Parameter(title: "widget.intent.stats.focus")
    var focus: EatometerStatsWidgetFocus?

    init() {
        focus = .overview
    }

    init(focus: EatometerStatsWidgetFocus?) {
        self.focus = focus ?? .overview
    }
}

struct AdjustWaterIntakeIntent: AppIntent {
    static let title: LocalizedStringResource = "widget.intent.adjust_water.title"

    @Parameter(title: "widget.intent.adjust_water.delta")
    var delta: Int

    init() {}

    init(delta: Int) {
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        EatometerWidgetStore.adjustWater(by: delta)
        for kind in [
            EatometerWidgetStore.waterWidgetKind,
            EatometerWidgetStore.nutritionWidgetKind,
            EatometerWidgetStore.statsWidgetKind
        ] {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        return .result()
    }
}

struct MarkHabitStageIntent: AppIntent {
    static let title: LocalizedStringResource = "widget.intent.habit.mark_stage.title"

    @Parameter(title: "widget.intent.habit.habit_id")
    var habitID: String

    @Parameter(title: "widget.intent.habit.attempt_id")
    var attemptID: String

    @Parameter(title: "widget.intent.habit.day")
    var dayKey: String

    init() {
        habitID = ""
        attemptID = ""
        dayKey = ""
    }

    init(habitID: String, attemptID: String, dayKey: String) {
        self.habitID = habitID
        self.attemptID = attemptID
        self.dayKey = dayKey
    }

    func perform() async throws -> some IntentResult {
        EatometerWidgetStore.markHabitStage(habitID: habitID, attemptID: attemptID, dayKey: dayKey)
        WidgetCenter.shared.reloadTimelines(ofKind: EatometerWidgetStore.habitWidgetKind)
        return .result()
    }
}
