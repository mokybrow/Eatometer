import Foundation

struct WatchMealSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let categoryID: String?
    let categoryTitle: String
    let calories: Int
    let scheduledAt: Date
}

struct WatchMealItemSummary: Identifiable, Codable, Hashable, Sendable {
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

struct WatchMealCategory: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let symbolName: String
}

struct WatchQuickAddItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let calories: Int
}

struct WatchTodaySnapshot: Codable, Sendable {
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
    let meals: [WatchMealSummary]
    let mealItems: [WatchMealItemSummary]
    let mealCategories: [WatchMealCategory]
    let products: [WatchQuickAddItem]
    let recipes: [WatchQuickAddItem]
    let mealTemplates: [WatchQuickAddItem]
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
        case meals
        case mealItems
        case mealCategories
        case products
        case favoriteProducts
        case recipes
        case mealTemplates
        case updatedAt
    }

    init(
        dayKey: String,
        calories: Int,
        protein: Int,
        fat: Int,
        carbs: Int,
        isWaterTrackingEnabled: Bool,
        caloriesGoal: Int,
        proteinGoal: Int,
        fatGoal: Int,
        carbsGoal: Int,
        waterIntakeMilliliters: Int,
        waterGoalMilliliters: Int,
        waterStepMilliliters: Int = 200,
        meals: [WatchMealSummary] = [],
        mealItems: [WatchMealItemSummary] = [],
        mealCategories: [WatchMealCategory] = [],
        products: [WatchQuickAddItem] = [],
        recipes: [WatchQuickAddItem] = [],
        mealTemplates: [WatchQuickAddItem] = [],
        updatedAt: Date
    ) {
        self.dayKey = dayKey
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.isWaterTrackingEnabled = isWaterTrackingEnabled
        self.caloriesGoal = caloriesGoal
        self.proteinGoal = proteinGoal
        self.fatGoal = fatGoal
        self.carbsGoal = carbsGoal
        self.waterIntakeMilliliters = waterIntakeMilliliters
        self.waterGoalMilliliters = waterGoalMilliliters
        self.waterStepMilliliters = waterStepMilliliters
        self.meals = meals
        self.mealItems = mealItems
        self.mealCategories = mealCategories
        self.products = products
        self.recipes = recipes
        self.mealTemplates = mealTemplates
        self.updatedAt = updatedAt
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
        waterStepMilliliters = try container.decodeIfPresent(Int.self, forKey: .waterStepMilliliters) ?? 200
        meals = try container.decodeIfPresent([WatchMealSummary].self, forKey: .meals) ?? []
        mealItems = try container.decodeIfPresent([WatchMealItemSummary].self, forKey: .mealItems) ?? []
        mealCategories = try container.decodeIfPresent([WatchMealCategory].self, forKey: .mealCategories) ?? []
        products = try container.decodeIfPresent([WatchQuickAddItem].self, forKey: .products)
            ?? container.decodeIfPresent([WatchQuickAddItem].self, forKey: .favoriteProducts)
            ?? []
        recipes = try container.decodeIfPresent([WatchQuickAddItem].self, forKey: .recipes) ?? []
        mealTemplates = try container.decodeIfPresent([WatchQuickAddItem].self, forKey: .mealTemplates) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    static let empty = WatchTodaySnapshot(
        dayKey: "",
        calories: 0, protein: 0, fat: 0, carbs: 0,
        isWaterTrackingEnabled: true,
        caloriesGoal: 2000, proteinGoal: 50, fatGoal: 67, carbsGoal: 200,
        waterIntakeMilliliters: 0, waterGoalMilliliters: 2000,
        waterStepMilliliters: 200,
        meals: [],
        mealItems: [],
        mealCategories: [],
        products: [],
        recipes: [],
        mealTemplates: [],
        updatedAt: .distantPast
    )

    var hasData: Bool {
        dayKey == Self.todayKey()
    }

    static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.startOfDay(for: .now))
    }
}
