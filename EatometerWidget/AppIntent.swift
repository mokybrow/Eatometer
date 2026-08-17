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
    static let nutritionWidgetKind = "EatometerNutritionWidget"
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

}

private struct PendingWidgetWaterExport: Codable {
    let id: String
    let scopeUserID: String
    let dayKey: String
    let deltaMilliliters: Int
    let totalMilliliters: Int
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
    /// The calories this meal is planned to be, worked out by the app from the
    /// meal's share of the daily goal. Zero when no share has been set.
    var targetCalories: Int = 0
    /// Eaten so far today, so the ring has something to fill.
    var calories: Int = 0
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

    /// One case per stored property, and no more.
    ///
    /// `favoriteProducts` — what `products` used to be called — sat here with
    /// no property behind it, and that alone stopped `Encodable` from being
    /// synthesised: the compiler will not write an encoder when it cannot say
    /// what a key should hold. The old name is still read, from the enum below.
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
        case recipes
        case mealTemplates
        case updatedAt
    }

    /// Names the app no longer writes but may still have written.
    ///
    /// Kept apart from `CodingKeys` so that one stays a faithful list of the
    /// properties, which is what the synthesised encoder needs it to be.
    private enum LegacyCodingKeys: String, CodingKey {
        /// What `products` was called in older builds. Read so a widget whose
        /// shared container was last written by one of them keeps its
        /// quick-add list instead of coming back empty.
        case favoriteProducts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
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
            ?? legacy.decodeIfPresent([EatometerQuickAddItem].self, forKey: .favoriteProducts)
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

struct WaterWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.intent.water.title"
    static let description = IntentDescription("widget.intent.water.description")

    init() {}
}

/// No parameters left.
///
/// The widget used to offer a choice of what to quick-add from — products,
/// recipes, meal templates or a mix — and that list is gone: the tile is a row
/// of meals now, and each ring opens the diary at its own meal. A setting that
/// changes nothing is worse than no setting, because it is still shown when
/// the widget is edited and still has to be answered.
struct QuickMealWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.intent.quick_meal.title"
    static let description = IntentDescription("widget.intent.quick_meal.description")

    init() {}
}

struct NutritionWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.intent.nutrition.title"
    static let description = IntentDescription("widget.intent.nutrition.description")

    init() {}
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
            EatometerWidgetStore.nutritionWidgetKind
        ] {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        return .result()
    }
}

