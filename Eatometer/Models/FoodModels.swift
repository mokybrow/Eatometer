import Combine
import Foundation

private func standardMealCategoryTitle(for id: String) -> String? {
    switch id {
    case MealKind.breakfast.rawValue:
        return NSLocalizedString("meal.breakfast", comment: "Breakfast meal title")
    case MealKind.lunch.rawValue:
        return NSLocalizedString("meal.lunch", comment: "Lunch meal title")
    case MealKind.dinner.rawValue:
        return NSLocalizedString("meal.dinner", comment: "Dinner meal title")
    case MealKind.snack.rawValue:
        return NSLocalizedString("meal.snack", comment: "Snack meal title")
    case "drink":
        return NSLocalizedString("meal.drink", comment: "Drink meal title")
    case "cheatmeal":
        return NSLocalizedString("meal.cheatmeal", comment: "Cheat meal category title")
    case "outside":
        return NSLocalizedString("meal.outside", comment: "Outside meal title")
    default:
        return nil
    }
}

private func localizedMealCategoryTitle(for id: String, fallback: String) -> String {
    let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let standardTitle = standardMealCategoryTitle(for: id) else {
        return trimmedFallback.isEmpty
            ? NSLocalizedString("meal.custom_default", comment: "Default custom meal title")
            : trimmedFallback
    }

    let knownStandardTitles = Set(
        [
            MealKind.breakfast.rawValue,
            MealKind.lunch.rawValue,
            MealKind.dinner.rawValue,
            MealKind.snack.rawValue,
            "drink",
            "cheatmeal",
            "outside"
        ].compactMap(standardMealCategoryTitle(for:))
    )

    if !trimmedFallback.isEmpty,
       trimmedFallback.compare(standardTitle, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame,
       !knownStandardTitles.contains(where: {
           $0.compare(trimmedFallback, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
       }) {
        return trimmedFallback
    }

    return standardTitle
}

enum FoodVisibilityOption: String, CaseIterable, Identifiable, Hashable, Codable {
    case privateVisibility
    case friendsVisibility
    case linkShared
    case publicVisibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateVisibility:
            return "product.editor.visibility.private"
        case .friendsVisibility:
            return "product.editor.visibility.friends"
        case .linkShared:
            return "product.editor.visibility.link"
        case .publicVisibility:
            return "product.editor.visibility.public"
        }
    }

    var grpcValue: Food_FoodVisibility {
        switch self {
        case .privateVisibility:
            return .private
        case .friendsVisibility:
            return .friends
        case .linkShared:
            return .linkShared
        case .publicVisibility:
            return .public
        }
    }

    init(grpcValue: Food_FoodVisibility) {
        switch grpcValue {
        case .private:
            self = .privateVisibility
        case .friends:
            self = .friendsVisibility
        case .linkShared:
            self = .linkShared
        case .public:
            self = .publicVisibility
        case .unspecified, .UNRECOGNIZED:
            self = .privateVisibility
        }
    }
}

struct MealTemplateDraft: Identifiable, Hashable {
    let id = UUID()
    var mealTemplateID: UUID?
    var title: String
    var details: String
    var items: [MealItemEntry]
    var visibility: FoodVisibilityOption

    init(summary: MealTemplateSummary? = nil) {
        self.mealTemplateID = summary?.id
        self.title = summary?.title ?? ""
        self.details = summary?.details ?? ""
        self.items = summary?.items ?? []
        self.visibility = summary?.visibility ?? .privateVisibility
    }
}
enum MealKind: String, CaseIterable, Identifiable, Codable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast:
            return NSLocalizedString("meal.breakfast", comment: "Breakfast meal title")
        case .lunch:
            return NSLocalizedString("meal.lunch", comment: "Lunch meal title")
        case .dinner:
            return NSLocalizedString("meal.dinner", comment: "Dinner meal title")
        case .snack:
            return NSLocalizedString("meal.snack", comment: "Snack meal title")
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast:
            return "sunrise.fill"
        case .lunch:
            return "sun.max.fill"
        case .dinner:
            return "moon.stars.fill"
        case .snack:
            return "leaf.fill"
        }
    }

    static func inferred(from date: Date) -> MealKind {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11:
            return .breakfast
        case 11..<16:
            return .lunch
        case 16..<22:
            return .dinner
        default:
            return .snack
        }
    }
}

enum MealItemUnit: String, CaseIterable, Identifiable, Codable {
    case grams
    case milliliters
    case serving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grams:
            return NSLocalizedString("unit.grams", comment: "Grams unit title")
        case .milliliters:
            return NSLocalizedString("unit.milliliters", comment: "Milliliters unit title")
        case .serving:
            return NSLocalizedString("unit.servings", comment: "Servings unit title")
        }
    }

    var shortTitle: String {
        switch self {
        case .grams:
            return NSLocalizedString("unit.grams.short", comment: "Grams unit short title")
        case .milliliters:
            return NSLocalizedString("unit.milliliters.short", comment: "Milliliters unit short title")
        case .serving:
            return NSLocalizedString("unit.servings.short", comment: "Servings unit short title")
        }
    }
}

struct NutritionSummary: Hashable, Codable {
    var calories: Int
    var protein: Int
    var fat: Int
    var carbs: Int

    static let zero = NutritionSummary(calories: 0, protein: 0, fat: 0, carbs: 0)

    func scaled(by factor: Double) -> NutritionSummary {
        NutritionSummary(
            calories: Int((Double(calories) * factor).rounded()),
            protein: Int((Double(protein) * factor).rounded()),
            fat: Int((Double(fat) * factor).rounded()),
            carbs: Int((Double(carbs) * factor).rounded())
        )
    }
}

struct DailyNutritionGoal: Hashable, Codable {
    var calories: Int
    var proteinPercent: Int
    var fatPercent: Int
    var carbsPercent: Int

    static let `default` = DailyNutritionGoal(calories: 2000, proteinPercent: 30, fatPercent: 30, carbsPercent: 40)

    var sanitized: DailyNutritionGoal {
        var p = max(0, proteinPercent)
        var f = max(0, fatPercent)
        var c = max(0, carbsPercent)
        let total = p + f + c
        guard total > 0 else {
            return .default
        }
        p = min(p, 100)
        f = min(f, 100)
        c = min(c, 100)
        return DailyNutritionGoal(calories: max(100, calories), proteinPercent: p, fatPercent: f, carbsPercent: c)
    }
}

enum DietPlanOption: String, CaseIterable, Identifiable, Codable {
    case balanced
    case highProtein = "high_protein"
    case lowerCarb = "lower_carb"
    case mediterranean
    case intermittent

    var id: String { rawValue }

    var title: String {
        NSLocalizedString(titleKey, comment: "Diet plan title")
    }

    var subtitle: String {
        NSLocalizedString(subtitleKey, comment: "Diet plan subtitle")
    }

    var titleKey: String {
        switch self {
        case .balanced:
            return "diet.plan.balanced"
        case .highProtein:
            return "diet.plan.high_protein"
        case .lowerCarb:
            return "diet.plan.lower_carb"
        case .mediterranean:
            return "diet.plan.mediterranean"
        case .intermittent:
            return "diet.plan.intermittent"
        }
    }

    var subtitleKey: String {
        switch self {
        case .balanced:
            return "diet.plan.balanced.subtitle"
        case .highProtein:
            return "diet.plan.high_protein.subtitle"
        case .lowerCarb:
            return "diet.plan.lower_carb.subtitle"
        case .mediterranean:
            return "diet.plan.mediterranean.subtitle"
        case .intermittent:
            return "diet.plan.intermittent.subtitle"
        }
    }

    var symbolName: String {
        switch self {
        case .balanced:
            return "circle.grid.cross.fill"
        case .highProtein:
            return "figure.strengthtraining.traditional"
        case .lowerCarb:
            return "leaf.fill"
        case .mediterranean:
            return "fork.knife.circle.fill"
        case .intermittent:
            return "clock.badge.checkmark.fill"
        }
    }

    var macroSplit: DailyNutritionGoal {
        switch self {
        case .balanced:
            return DailyNutritionGoal(calories: DailyNutritionGoal.default.calories, proteinPercent: 30, fatPercent: 30, carbsPercent: 40)
        case .highProtein:
            return DailyNutritionGoal(calories: DailyNutritionGoal.default.calories, proteinPercent: 35, fatPercent: 25, carbsPercent: 40)
        case .lowerCarb:
            return DailyNutritionGoal(calories: DailyNutritionGoal.default.calories, proteinPercent: 35, fatPercent: 35, carbsPercent: 30)
        case .mediterranean:
            return DailyNutritionGoal(calories: DailyNutritionGoal.default.calories, proteinPercent: 25, fatPercent: 35, carbsPercent: 40)
        case .intermittent:
            return DailyNutritionGoal(calories: DailyNutritionGoal.default.calories, proteinPercent: 30, fatPercent: 35, carbsPercent: 35)
        }
    }

    func applying(to goal: DailyNutritionGoal) -> DailyNutritionGoal {
        let split = macroSplit
        return DailyNutritionGoal(
            calories: goal.calories,
            proteinPercent: split.proteinPercent,
            fatPercent: split.fatPercent,
            carbsPercent: split.carbsPercent
        ).sanitized
    }

    static func normalized(rawValue: String) -> DietPlanOption {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "highprotein", "high_protein", "high-protein":
            return .highProtein
        case "lowercarb", "lower_carb", "lower-carb":
            return .lowerCarb
        case "mediterranean":
            return .mediterranean
        case "intermittent", "intermittent_fasting", "intermittent-fasting":
            return .intermittent
        case "balanced":
            return .balanced
        default:
            return .balanced
        }
    }
}

struct MealCategory: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var symbolName: String
    var sortOrder: Int
    var isEnabled: Bool
    var preferredHour: Int
    var preferredMinute: Int
    var goalSharePercent: Int

    init(id: String, title: String, symbolName: String, sortOrder: Int, isEnabled: Bool, preferredHour: Int, preferredMinute: Int = 0, goalSharePercent: Int) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
        self.preferredHour = preferredHour
        self.preferredMinute = preferredMinute
        self.goalSharePercent = goalSharePercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        preferredHour = try container.decode(Int.self, forKey: .preferredHour)
        preferredMinute = try container.decodeIfPresent(Int.self, forKey: .preferredMinute) ?? 0
        goalSharePercent = try container.decode(Int.self, forKey: .goalSharePercent)
    }

    static let availableSymbols = [
        "sunrise.fill",
        "sun.max.fill",
        "fork.knife",
        "moon.stars.fill",
        "leaf.fill",
        "cup.and.saucer.fill",
        "birthday.cake.fill",
        "takeoutbag.and.cup.and.straw.fill"
    ]

    static let `default`: [MealCategory] = MealKind.allCases.enumerated().map { index, kind in
        kind.asMealCategory(sortOrder: index)
    }

    var normalized: MealCategory {
        MealCategory(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSLocalizedString("meal.custom_default", comment: "Default custom meal title") : title.trimmingCharacters(in: .whitespacesAndNewlines),
            symbolName: MealCategory.availableSymbols.contains(symbolName) ? symbolName : "fork.knife",
            sortOrder: max(0, sortOrder),
            isEnabled: isEnabled,
            preferredHour: min(max(preferredHour, 0), 23),
            preferredMinute: min(max(preferredMinute, 0), 59),
            goalSharePercent: min(max(goalSharePercent, 0), 100)
        )
    }

    var displayTitle: String {
        localizedMealCategoryTitle(for: id, fallback: title)
    }
}

struct MealEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var kind: MealKind
    var mealCategoryID: String
    var title: String
    var items: [MealItemEntry]
    var note: String
    var scheduledAt: Date
    var nutrition: NutritionSummary

    var calories: Int {
        nutrition.calories > 0 ? nutrition.calories : items.reduce(0) { $0 + $1.calories }
    }

    var protein: Int {
        nutrition.protein > 0 ? nutrition.protein : items.reduce(0) { $0 + $1.protein }
    }

    var fat: Int {
        nutrition.fat > 0 ? nutrition.fat : items.reduce(0) { $0 + $1.fat }
    }

    var carbs: Int {
        nutrition.carbs > 0 ? nutrition.carbs : items.reduce(0) { $0 + $1.carbs }
    }
}

extension MealKind {
    var preferredHour: Int {
        switch self {
        case .breakfast:
            return 8
        case .lunch:
            return 13
        case .dinner:
            return 19
        case .snack:
            return 16
        }
    }

    var goalSharePercent: Int {
        switch self {
        case .breakfast:
            return 25
        case .lunch:
            return 35
        case .dinner:
            return 30
        case .snack:
            return 10
        }
    }

    func asMealCategory(sortOrder: Int) -> MealCategory {
        MealCategory(
            id: rawValue,
            title: title,
            symbolName: symbolName,
            sortOrder: sortOrder,
            isEnabled: true,
            preferredHour: preferredHour,
            preferredMinute: 0,
            goalSharePercent: goalSharePercent
        )
    }
}

private func normalizedFoodText(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}

func formattedFoodAmountValue(_ value: Double, maximumFractionDigits: Int = 2) -> String {
    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maximumFractionDigits
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 0.0001
}

private let numericServingLabelUnitTokens = [
    "milliliters",
    "milliliter",
    "liters",
    "liter",
    "grams",
    "gram",
    "ml",
    "mg",
    "kg",
    "cl",
    "gr",
    "g",
    "l"
]

private func isNumericServingLabel(_ value: String) -> Bool {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else { return false }
    guard trimmedValue.rangeOfCharacter(from: .decimalDigits) != nil else { return false }

    var normalizedValue = normalizedFoodText(trimmedValue)
    for token in numericServingLabelUnitTokens {
        normalizedValue = normalizedValue.replacingOccurrences(of: token, with: "")
    }

    let allowedCharacters = CharacterSet(charactersIn: "0123456789.,-–—/()[]{}+~ ")
    return normalizedValue.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
}

func displayFoodQuantityValue(amount: Double, unit: MealItemUnit, servingLabel: String = "", product: ProductSummary? = nil) -> Double {
    guard let product else { return amount }
    return product.displayQuantityValue(amount: amount, unit: unit, servingLabel: servingLabel)
}

func displayFoodQuantityText(amount: Double, unit: MealItemUnit, servingLabel: String = "", product: ProductSummary? = nil) -> String {
    guard let product else {
        return "\(formattedFoodAmountValue(amount, maximumFractionDigits: 1)) \(unit.shortTitle)"
    }
    return product.displayQuantityText(amount: amount, unit: unit, servingLabel: servingLabel)
}

struct ProductNutrient: Identifiable, Hashable, Codable {
    var code: String
    var label: String
    var amount: Double
    var unit: String

    var id: String {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCode.isEmpty {
            return trimmedCode
        }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }
        return "unnamed-\(unit.trimmingCharacters(in: .whitespacesAndNewlines))-\(amount)"
    }
}

struct ProductServingOption: Identifiable, Hashable, Codable {
    var id: String
    var label: String
    var amount: Double
    var unit: MealItemUnit
    var metricAmount: Double
    var metricUnit: MealItemUnit
    var sortOrder: Int

    init(
        id: String = UUID().uuidString,
        label: String = "",
        amount: Double = 1,
        unit: MealItemUnit = .grams,
        metricAmount: Double = 0,
        metricUnit: MealItemUnit = .grams,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.label = label
        self.amount = amount
        self.unit = unit
        self.metricAmount = metricAmount
        self.metricUnit = metricUnit
        self.sortOrder = sortOrder
    }

    var effectiveAmount: Double {
        max(amount, 1)
    }

    var effectiveMetricAmount: Double {
        metricAmount > 0 ? metricAmount : effectiveAmount
    }

    var effectiveMetricUnit: MealItemUnit {
        metricUnit == .serving ? (unit == .serving ? .grams : unit) : metricUnit
    }

    private var genericServingTitle: String {
        NSLocalizedString(
            "product.serving.generic_title",
            tableName: nil,
            bundle: .main,
            value: "Serving",
            comment: "Generic title for a serving option"
        )
    }

    private var usesGenericServingTitle: Bool {
        unit == .serving && (!hasExplicitLabel || isNumericServingLabel(label))
    }

    var displayTitle: String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if usesGenericServingTitle {
            return genericServingTitle
        }
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }
        if unit == .serving && approximatelyEqual(effectiveAmount, 1) {
            return genericServingTitle
        }
        return "\(formattedFoodAmountValue(effectiveAmount, maximumFractionDigits: 1)) \(unit.shortTitle)"
    }

    var hasExplicitLabel: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isSyntheticMetricOption: Bool {
        !hasExplicitLabel
            && unit != .serving
            && unit == effectiveMetricUnit
            && approximatelyEqual(effectiveAmount, effectiveMetricAmount)
    }

    var pickerTitle: String {
        guard let metricDescription, !isSyntheticMetricOption else {
            return displayTitle
        }
        return "\(displayTitle) (\(metricDescription))"
    }

    var quantityTitle: String {
        usesGenericServingTitle ? pickerTitle : displayTitle
    }

    var selectionLabel: String {
        quantityTitle
    }

    var metricDescription: String? {
        guard unit != effectiveMetricUnit || !approximatelyEqual(effectiveAmount, effectiveMetricAmount) else {
            return nil
        }
        return "\(formattedFoodAmountValue(effectiveMetricAmount, maximumFractionDigits: 1)) \(effectiveMetricUnit.shortTitle)"
    }

    func matchesSelectionLabel(_ rawValue: String) -> Bool {
        let normalizedValue = normalizedFoodText(rawValue)
        guard !normalizedValue.isEmpty else { return false }
        return normalizedFoodText(label) == normalizedValue
            || normalizedFoodText(displayTitle) == normalizedValue
            || normalizedFoodText(pickerTitle) == normalizedValue
            || normalizedFoodText(quantityTitle) == normalizedValue
    }
}

struct MealItemEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var amount: Double
    var unit: MealItemUnit
    var note: String
    var servingLabel: String = ""
    var caloriesPer100g: Int
    var proteinPer100g: Int
    var fatPer100g: Int
    var carbsPer100g: Int
    var productID: UUID?
    var recipeID: UUID?
    var productSnapshot: ProductSummary? = nil
    var recipeSnapshot: RecipeSummary? = nil

    var isLinkedToCatalogItem: Bool {
        productID != nil || recipeID != nil
    }

    var calories: Int {
        switch unit {
        case .serving:
            return Int((Double(caloriesPer100g) * max(amount, 1)).rounded())
        case .grams, .milliliters:
            return Int((Double(caloriesPer100g) * amount / 100.0).rounded())
        }
    }

    var protein: Int {
        switch unit {
        case .serving:
            return Int((Double(proteinPer100g) * max(amount, 1)).rounded())
        case .grams, .milliliters:
            return Int((Double(proteinPer100g) * amount / 100.0).rounded())
        }
    }

    var fat: Int {
        switch unit {
        case .serving:
            return Int((Double(fatPer100g) * max(amount, 1)).rounded())
        case .grams, .milliliters:
            return Int((Double(fatPer100g) * amount / 100.0).rounded())
        }
    }

    var carbs: Int {
        switch unit {
        case .serving:
            return Int((Double(carbsPer100g) * max(amount, 1)).rounded())
        case .grams, .milliliters:
            return Int((Double(carbsPer100g) * amount / 100.0).rounded())
        }
    }
}

struct MealTemplateSummary: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var details: String
    var items: [MealItemEntry]
    var nutrition: NutritionSummary
    var createdAt: Date? = nil
    var updatedAt: Date? = nil
    var visibility: FoodVisibilityOption = .privateVisibility

    init(
        id: UUID,
        title: String,
        details: String = "",
        items: [MealItemEntry] = [],
        nutrition: NutritionSummary = .zero,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        visibility: FoodVisibilityOption = .privateVisibility
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.items = items
        self.nutrition = nutrition
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.visibility = visibility
    }

    var calories: Int {
        nutrition.calories > 0 ? nutrition.calories : items.reduce(0) { $0 + $1.calories }
    }

    var protein: Int {
        nutrition.protein > 0 ? nutrition.protein : items.reduce(0) { $0 + $1.protein }
    }

    var fat: Int {
        nutrition.fat > 0 ? nutrition.fat : items.reduce(0) { $0 + $1.fat }
    }

    var carbs: Int {
        nutrition.carbs > 0 ? nutrition.carbs : items.reduce(0) { $0 + $1.carbs }
    }
}

struct ProductSummary: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let brand: String
    var barcode: String?
    let caloriesPer100g: Int
    let proteinPer100g: Int
    let fatPer100g: Int
    let carbsPer100g: Int
    var createdAt: Date? = nil
    var updatedAt: Date? = nil
    var details: String = ""
    var visibility: FoodVisibilityOption = .privateVisibility
    var servingAmount: Double = 100
    var servingUnit: MealItemUnit = .grams
    var fiberPer100g: Double = 0
    var sugarPer100g: Double = 0
    var sodiumMgPer100g: Double = 0
    var saturatedFatPer100g: Double = 0
    var unsaturatedFatPer100g: Double = 0
    var additionalNutrients: [ProductNutrient] = []
    var servingOptions: [ProductServingOption] = []

    init(
        id: UUID,
        name: String,
        brand: String,
        barcode: String? = nil,
        caloriesPer100g: Int,
        proteinPer100g: Int,
        fatPer100g: Int,
        carbsPer100g: Int,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        details: String = "",
        visibility: FoodVisibilityOption = .privateVisibility,
        servingAmount: Double = 100,
        servingUnit: MealItemUnit = .grams,
        fiberPer100g: Double = 0,
        sugarPer100g: Double = 0,
        sodiumMgPer100g: Double = 0,
        saturatedFatPer100g: Double = 0,
        unsaturatedFatPer100g: Double = 0,
        additionalNutrients: [ProductNutrient] = [],
        servingOptions: [ProductServingOption] = []
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.fatPer100g = fatPer100g
        self.carbsPer100g = carbsPer100g
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.details = details
        self.visibility = visibility
        self.servingAmount = servingAmount
        self.servingUnit = servingUnit
        self.fiberPer100g = fiberPer100g
        self.sugarPer100g = sugarPer100g
        self.sodiumMgPer100g = sodiumMgPer100g
        self.saturatedFatPer100g = saturatedFatPer100g
        self.unsaturatedFatPer100g = unsaturatedFatPer100g
        self.additionalNutrients = additionalNutrients
        self.servingOptions = servingOptions
    }
}

extension ProductSummary {
    var portionReferenceServingOption: ProductServingOption? {
        if let servingOption = resolvedServingOptions.first(where: { $0.unit == .serving }) {
            return servingOption
        }

        let baseUnit = baseNutritionUnit
        return resolvedServingOptions.first(where: {
            $0.effectiveMetricUnit == baseUnit
                && !approximatelyEqual($0.effectiveMetricAmount, 100)
        })
    }

    var baseNutritionUnit: MealItemUnit {
        if servingUnit != .serving {
            return servingUnit
        }

        if let firstMetricUnit = resolvedServingOptions.first?.effectiveMetricUnit,
           firstMetricUnit != .serving {
            return firstMetricUnit
        }

        return .grams
    }

    var per100UnitShortTitle: String {
        baseNutritionUnit.shortTitle
    }

    var localizedPer100UnitTitle: String {
        String(
            format: NSLocalizedString("recipe.editor.nutrition_per_100_unit", comment: "Nutrition per 100 unit"),
            per100UnitShortTitle
        )
    }

    var selectableServingOptions: [ProductServingOption] {
        resolvedServingOptions.filter { !$0.isSyntheticMetricOption }
    }

    var resolvedServingOptions: [ProductServingOption] {
        let normalizedOptions: [ProductServingOption]
        if servingOptions.isEmpty {
            let legacyAmount = max(servingAmount, 1)
            if servingUnit == .serving || !approximatelyEqual(legacyAmount, 100) {
                normalizedOptions = [
                    ProductServingOption(
                        id: "legacy-default-serving",
                        label: "",
                        amount: 1,
                        unit: .serving,
                        metricAmount: legacyAmount,
                        metricUnit: servingUnit == .serving ? .grams : servingUnit,
                        sortOrder: 0
                    )
                ]
            } else {
                normalizedOptions = [
                    ProductServingOption(
                        id: "legacy-default-metric",
                        label: "",
                        amount: legacyAmount,
                        unit: servingUnit,
                        metricAmount: legacyAmount,
                        metricUnit: servingUnit,
                        sortOrder: 0
                    )
                ]
            }
        } else {
            normalizedOptions = servingOptions.enumerated().map { index, option in
                ProductServingOption(
                    id: option.id.isEmpty ? "serving-option-\(index)" : option.id,
                    label: option.label,
                    amount: option.amount <= 0 ? 1 : option.amount,
                    unit: option.unit,
                    metricAmount: option.metricAmount <= 0 ? (option.amount <= 0 ? 1 : option.amount) : option.metricAmount,
                    metricUnit: option.metricUnit,
                    sortOrder: option.sortOrder
                )
            }
        }

        return normalizedOptions.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.displayTitle < $1.displayTitle
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var defaultServingOption: ProductServingOption {
        resolvedServingOptions[0]
    }

    var defaultSelectableServingOption: ProductServingOption? {
        selectableServingOptions.first
    }

    func servingOption(matching servingLabel: String) -> ProductServingOption? {
        let trimmedLabel = servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return nil }
        return resolvedServingOptions.first(where: { $0.matchesSelectionLabel(trimmedLabel) })
    }

    func selectableServingOption(matching servingLabel: String) -> ProductServingOption? {
        let trimmedLabel = servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return nil }
        return selectableServingOptions.first(where: { $0.matchesSelectionLabel(trimmedLabel) })
    }

    func preferredServingOption(for amount: Double, unit: MealItemUnit, servingLabel: String) -> ProductServingOption {
        if let matched = selectableServingOption(matching: servingLabel) {
            return matched
        }
        if unit == .serving {
            return defaultSelectableServingOption ?? defaultServingOption
        }
        return defaultSelectableServingOption ?? defaultServingOption
    }

    func selectionPayload(quantity: Double = 1, option: ProductServingOption? = nil) -> (amount: Double, unit: MealItemUnit, servingLabel: String) {
        let resolvedQuantity = max(quantity, 1)
        if let resolvedOption = option ?? defaultSelectableServingOption {
            return (
                amount: resolvedQuantity * resolvedOption.effectiveMetricAmount,
                unit: resolvedOption.effectiveMetricUnit,
                servingLabel: resolvedOption.selectionLabel
            )
        }

        let resolvedOption = defaultServingOption
        return (
            amount: resolvedQuantity * resolvedOption.effectiveMetricAmount,
            unit: resolvedOption.effectiveMetricUnit,
            servingLabel: resolvedOption.isSyntheticMetricOption ? "" : resolvedOption.selectionLabel
        )
    }

    func actualAmount(for quantity: Double, unit: MealItemUnit, servingLabel: String) -> (amount: Double, unit: MealItemUnit) {
        if unit != .serving {
            return (amount: quantity, unit: unit)
        }
        let matchedOption = servingOption(matching: servingLabel) ?? defaultServingOption
        return (
            amount: max(quantity, 0) * matchedOption.effectiveMetricAmount,
            unit: matchedOption.effectiveMetricUnit
        )
    }

    func displayQuantityValue(amount: Double, unit: MealItemUnit, servingLabel: String) -> Double {
        guard let matchedOption = selectableServingOption(matching: servingLabel) else {
            if unit == .serving {
                return max(amount, 1)
            }
            return amount
        }

        if unit == matchedOption.effectiveMetricUnit && matchedOption.effectiveMetricAmount > 0 {
            return amount / matchedOption.effectiveMetricAmount
        }
        if unit == matchedOption.unit && matchedOption.effectiveAmount > 0 {
            return amount / matchedOption.effectiveAmount
        }
        return amount
    }

    func displayQuantityText(amount: Double, unit: MealItemUnit, servingLabel: String) -> String {
        if let matchedOption = selectableServingOption(matching: servingLabel) {
            let quantity = displayQuantityValue(amount: amount, unit: unit, servingLabel: servingLabel)
            if quantity > 0 {
                if approximatelyEqual(quantity, 1) {
                    return matchedOption.quantityTitle
                }
                return "\(formattedFoodAmountValue(quantity, maximumFractionDigits: 1)) × \(matchedOption.quantityTitle)"
            }
        }
        return "\(formattedFoodAmountValue(amount, maximumFractionDigits: 1)) \(unit.shortTitle)"
    }
}

struct RecipeIngredientSummary: Identifiable, Hashable, Codable {
    let id: UUID
    let productID: UUID?
    let nestedRecipeID: UUID?
    let amount: Double
    let unit: MealItemUnit
    let note: String
    var servingLabel: String = ""
    var productSnapshot: ProductSummary? = nil
    var nestedRecipeSnapshot: RecipeSummary? = nil
}

extension MealItemEntry {
    var linkedProductSummary: ProductSummary? {
        productSnapshot
    }

    var linkedRecipeSummary: RecipeSummary? {
        recipeSnapshot
    }
}

extension RecipeIngredientSummary {
    var linkedProductSummary: ProductSummary? {
        productSnapshot
    }

    var linkedRecipeSummary: RecipeSummary? {
        nestedRecipeSnapshot
    }
}

struct RecipeSummary: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let servings: Int
    let caloriesPerServing: Int
    let proteinPerServing: Int
    let fatPerServing: Int
    let carbsPerServing: Int
    let cookTimeMinutes: Int
    var category: String = ""
    var emoji: String = ""
    var createdAt: Date? = nil
    var updatedAt: Date? = nil
    var details: String = ""
    var ingredients: [RecipeIngredientSummary] = []
    var steps: [String] = []
    var visibility: FoodVisibilityOption = .privateVisibility
    var outputWeightGrams: Double = 0
    var nutritionPer100g: NutritionSummary = .zero

    init(
        id: UUID,
        title: String,
        servings: Int,
        caloriesPerServing: Int,
        proteinPerServing: Int,
        fatPerServing: Int,
        carbsPerServing: Int,
        cookTimeMinutes: Int,
        category: String = "",
        emoji: String = "",
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        details: String = "",
        ingredients: [RecipeIngredientSummary] = [],
        steps: [String] = [],
        visibility: FoodVisibilityOption = .privateVisibility,
        outputWeightGrams: Double = 0,
        nutritionPer100g: NutritionSummary = .zero
    ) {
        self.id = id
        self.title = title
        self.servings = servings
        self.caloriesPerServing = caloriesPerServing
        self.proteinPerServing = proteinPerServing
        self.fatPerServing = fatPerServing
        self.carbsPerServing = carbsPerServing
        self.cookTimeMinutes = cookTimeMinutes
        self.category = category
        self.emoji = emoji
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.details = details
        self.ingredients = ingredients
        self.steps = steps
        self.visibility = visibility
        self.outputWeightGrams = outputWeightGrams
        self.nutritionPer100g = nutritionPer100g
    }
}

extension RecipeSummary {
    var nutritionPerServing: NutritionSummary {
        NutritionSummary(
            calories: caloriesPerServing,
            protein: proteinPerServing,
            fat: fatPerServing,
            carbs: carbsPerServing
        )
    }

    var resolvedNutritionPer100g: NutritionSummary {
        if nutritionPer100g != .zero {
            return nutritionPer100g
        }

        guard outputWeightGrams > 0 else {
            return .zero
        }

        let servingsCount = max(servings, 1)
        let totalNutrition = nutritionPerServing.scaled(by: Double(servingsCount))
        let factor = 100.0 / outputWeightGrams
        return totalNutrition.scaled(by: factor)
    }
}

struct FoodSharePayload: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let shareCode: String
    let shareURL: String
    let previewTitle: String? = nil
    let previewSubtitle: String? = nil

    private static let foodWebBaseURL = "https://goeatometer.com"

    var isRecipeShare: Bool {
        shareCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("rshare")
    }

    var isMealTemplateShare: Bool {
        shareCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("mtshare")
    }

    var isProductShare: Bool {
        shareCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("pshare")
    }

    var resolvedShareLink: String? {
        let trimmedShareURL = shareURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedShareURL.isEmpty, URL(string: trimmedShareURL)?.scheme != nil {
            return trimmedShareURL
        }

        let trimmedShareCode = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedShareCode.isEmpty, Self.isKnownShareCode(trimmedShareCode) {
            let encodedCode = trimmedShareCode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmedShareCode
            return "\(Self.foodWebBaseURL)/r/\(encodedCode)"
        }

        return trimmedShareCode.isEmpty ? nil : trimmedShareCode
    }

    var resolvedShareURL: URL? {
        guard let link = resolvedSharePreviewLink else { return nil }
        return URL(string: link)
    }

    var resolvedSharePreviewLink: String? {
        resolvedShareLink
    }

    private static func isKnownShareCode(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("rshare")
            || normalized.hasPrefix("mtshare")
            || normalized.hasPrefix("mshare")
            || normalized.hasPrefix("pshare")
    }

    var localizedShareSubject: String {
        if isRecipeShare {
            return String(format: NSLocalizedString("share.subject.recipe", value: "Recipe: %@", comment: "Recipe share subject"), title)
        } else if isMealTemplateShare {
            return String(format: NSLocalizedString("share.subject.meal_template", value: "Ration: %@", comment: "Ration share subject"), title)
        } else if isProductShare {
            return String(format: NSLocalizedString("share.subject.product", value: "Product: %@", comment: "Product share subject"), title)
        } else {
            return String(format: NSLocalizedString("share.subject.meal", value: "Meal: %@", comment: "Meal share subject"), title)
        }
    }

    /// Localized text that accompanies the shared link. The visual card is
    /// rendered by the web service from the link, so the app only supplies a
    /// short localized caption describing what is being shared.
    var localizedShareMessage: String {
        localizedShareSubject
    }
}

struct DiaryHistoryPoint: Identifiable, Hashable {
    var id: Date { day }
    let day: Date
    let calories: Int
    let goal: Int
    let hasCheatMeal: Bool
    let isOverride: Bool
}

enum NutritionStatsPeriod: String, CaseIterable, Identifiable, Hashable, Codable {
    case day
    case week
    case month
    case halfYear
    case year

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .day:
            return NSLocalizedString("today.stats.period.day.short", comment: "Day period short title")
        case .week:
            return NSLocalizedString("today.stats.period.week.short", comment: "Week period short title")
        case .month:
            return NSLocalizedString("today.stats.period.month.short", comment: "Month period short title")
        case .halfYear:
            return NSLocalizedString("today.stats.period.halfyear.short", comment: "Half-year period short title")
        case .year:
            return NSLocalizedString("today.stats.period.year.short", comment: "Year period short title")
        }
    }

    var title: String {
        switch self {
        case .day:
            return NSLocalizedString("today.stats.period.day", comment: "Day period title")
        case .week:
            return NSLocalizedString("today.stats.period.week", comment: "Week period title")
        case .month:
            return NSLocalizedString("today.stats.period.month", comment: "Month period title")
        case .halfYear:
            return NSLocalizedString("today.stats.period.halfyear", comment: "Half-year period title")
        case .year:
            return NSLocalizedString("today.stats.period.year", comment: "Year period title")
        }
    }
}

struct NutritionStatisticsBucket: Identifiable, Hashable, Codable {
    var id: Date { startAt }
    let startAt: Date
    let endAt: Date
    let total: NutritionSummary
    let goal: DailyNutritionGoal?
    let hasEntries: Bool
    let hasCheatMeal: Bool
    let goalMet: Bool
    let mealCount: Int
}

struct NutritionStatisticsSummary: Hashable, Codable {
    let total: NutritionSummary
    let averagePerDay: NutritionSummary
    let totalDays: Int
    let recordedDays: Int
    let skippedDays: Int
    let cheatMealDays: Int
    let goalMetDays: Int
    let currentGoalStreak: Int
    let longestGoalStreak: Int
}

struct NutritionStatisticsSnapshot: Hashable, Codable {
    let period: NutritionStatsPeriod
    let periodStart: Date
    let periodEnd: Date
    let selectedAt: Date
    let summary: NutritionStatisticsSummary
    let buckets: [NutritionStatisticsBucket]
}

enum NutritionAchievementKind: String, CaseIterable, Identifiable, Hashable {
    case logStreakWeek
    case logStreakMonth
    case logStreakHalfYear
    case goalMetWeek
    case goalMetMonth
    case goalMetHalfYear
    case goalOverWeek
    case cheatWeek
    case goalUnderWeek

    var id: String { rawValue }
}

struct NutritionAchievement: Identifiable, Hashable {
    var id: NutritionAchievementKind { kind }
    let kind: NutritionAchievementKind
    let title: String
    let description: String
    let achieved: Bool
    let achievedAt: Date?
    let currentStreakDays: Int
    let bestStreakDays: Int
    let targetDays: Int

    var localizedTitle: String {
        kind.localizedTitle(fallback: title)
    }

    var localizedDescription: String {
        kind.localizedDescription(fallback: description)
    }
}

extension NutritionAchievementKind {
    private var titleKey: String {
        switch self {
        case .logStreakWeek:
            return "today.achievement.log_streak_week.title"
        case .logStreakMonth:
            return "today.achievement.log_streak_month.title"
        case .logStreakHalfYear:
            return "today.achievement.log_streak_halfyear.title"
        case .goalMetWeek:
            return "today.achievement.goal_met_week.title"
        case .goalMetMonth:
            return "today.achievement.goal_met_month.title"
        case .goalMetHalfYear:
            return "today.achievement.goal_met_halfyear.title"
        case .goalOverWeek:
            return "today.achievement.goal_over_week.title"
        case .cheatWeek:
            return "today.achievement.cheat_week.title"
        case .goalUnderWeek:
            return "today.achievement.goal_under_week.title"
        }
    }

    private var descriptionKey: String {
        switch self {
        case .logStreakWeek:
            return "today.achievement.log_streak_week.description"
        case .logStreakMonth:
            return "today.achievement.log_streak_month.description"
        case .logStreakHalfYear:
            return "today.achievement.log_streak_halfyear.description"
        case .goalMetWeek:
            return "today.achievement.goal_met_week.description"
        case .goalMetMonth:
            return "today.achievement.goal_met_month.description"
        case .goalMetHalfYear:
            return "today.achievement.goal_met_halfyear.description"
        case .goalOverWeek:
            return "today.achievement.goal_over_week.description"
        case .cheatWeek:
            return "today.achievement.cheat_week.description"
        case .goalUnderWeek:
            return "today.achievement.goal_under_week.description"
        }
    }

    func localizedTitle(fallback: String) -> String {
        let localized = NSLocalizedString(titleKey, comment: "Nutrition achievement title")
        return localized == titleKey ? fallback : localized
    }

    func localizedDescription(fallback: String) -> String {
        let localized = NSLocalizedString(descriptionKey, comment: "Nutrition achievement description")
        return localized == descriptionKey ? fallback : localized
    }
}

struct NutritionAchievementsSnapshot: Hashable {
    let selectedAt: Date
    let achievements: [NutritionAchievement]
}

struct RecipeNutritionPreview: Hashable {
    let total: NutritionSummary
    let perServing: NutritionSummary
    let per100g: NutritionSummary

    static let zero = RecipeNutritionPreview(total: .zero, perServing: .zero, per100g: .zero)
}

struct ProductDraft: Identifiable, Hashable {
    let id = UUID()
    var productID: UUID?
    var name: String
    var brand: String
    var barcode: String
    var details: String
    var visibility: FoodVisibilityOption
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var fatPer100g: Double
    var saturatedFatPer100g: Double
    var unsaturatedFatPer100g: Double
    var carbsPer100g: Double
    var servingAmount: Double
    var servingUnit: MealItemUnit
    var fiberPer100g: Double
    var sugarPer100g: Double
    var sodiumMgPer100g: Double
    var additionalNutrients: [ProductNutrient]
    var servingOptions: [ProductServingOption]

    init(summary: ProductSummary? = nil) {
        let baseUnit = summary?.baseNutritionUnit ?? .grams
        let portionOption = summary?.portionReferenceServingOption
        self.productID = summary?.id
        self.name = summary?.name ?? ""
        self.brand = summary?.brand ?? ""
        self.barcode = summary?.barcode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.details = summary?.details ?? ""
        self.visibility = summary?.visibility ?? .privateVisibility
        self.caloriesPer100g = Double(summary?.caloriesPer100g ?? 0)
        self.proteinPer100g = Double(summary?.proteinPer100g ?? 0)
        self.fatPer100g = Double(summary?.fatPer100g ?? 0)
        self.saturatedFatPer100g = summary?.saturatedFatPer100g ?? 0
        self.unsaturatedFatPer100g = summary?.unsaturatedFatPer100g ?? 0
        self.carbsPer100g = Double(summary?.carbsPer100g ?? 0)
        self.servingAmount = portionOption?.effectiveMetricAmount ?? summary?.servingAmount ?? 100
        self.servingUnit = baseUnit == .serving ? .grams : baseUnit
        self.fiberPer100g = summary?.fiberPer100g ?? 0
        self.sugarPer100g = summary?.sugarPer100g ?? 0
        self.sodiumMgPer100g = summary?.sodiumMgPer100g ?? 0
        self.additionalNutrients = summary?.additionalNutrients ?? []
        self.servingOptions = summary?.servingOptions ?? []
    }
}

struct RecipeIngredientDraft: Identifiable, Hashable {
    let id: UUID
    var name: String
    var productID: UUID?
    var nestedRecipeID: UUID?
    var amount: Double
    var unit: MealItemUnit
    var note: String
    var servingLabel: String
    var productSnapshot: ProductSummary?
    var nestedRecipeSnapshot: RecipeSummary?

    init(
        id: UUID = UUID(),
        name: String = "",
        productID: UUID? = nil,
        nestedRecipeID: UUID? = nil,
        amount: Double = 100,
        unit: MealItemUnit = .grams,
        note: String = "",
        servingLabel: String = "",
        productSnapshot: ProductSummary? = nil,
        nestedRecipeSnapshot: RecipeSummary? = nil
    ) {
        self.id = id
        self.name = name
        self.productID = productID
        self.nestedRecipeID = nestedRecipeID
        self.amount = amount
        self.unit = unit
        self.note = note
        self.servingLabel = servingLabel
        self.productSnapshot = productSnapshot
        self.nestedRecipeSnapshot = nestedRecipeSnapshot
    }

    init(summary: RecipeIngredientSummary) {
        self.id = summary.id
        self.name = summary.linkedProductSummary?.name ?? summary.linkedRecipeSummary?.title ?? ""
        self.productID = summary.productID
        self.nestedRecipeID = summary.nestedRecipeID
        self.amount = summary.amount
        self.unit = summary.unit
        self.note = summary.note
        self.servingLabel = summary.servingLabel
        self.productSnapshot = summary.productSnapshot
        self.nestedRecipeSnapshot = summary.nestedRecipeSnapshot
    }
}

extension RecipeIngredientDraft {
    var linkedProductSummary: ProductSummary? {
        productSnapshot
    }

    var linkedRecipeSummary: RecipeSummary? {
        nestedRecipeSnapshot
    }
}

struct RecipeDraft: Identifiable, Hashable {
    let id = UUID()
    var recipeID: UUID?
    var title: String
    var details: String
    var category: String
    var emoji: String
    var servings: Int
    var outputWeightGrams: Double
    var ingredients: [RecipeIngredientDraft]
    var stepsText: String
    var visibility: FoodVisibilityOption

    init(summary: RecipeSummary? = nil) {
        self.recipeID = summary?.id
        self.title = summary?.title ?? ""
        self.details = summary?.details ?? ""
        self.category = summary?.category ?? ""
        self.emoji = summary?.emoji ?? ""
        self.servings = summary?.servings ?? 0
        self.outputWeightGrams = max(summary?.outputWeightGrams ?? 0, 0)
        self.ingredients = summary?.ingredients.map(RecipeIngredientDraft.init) ?? []
        self.stepsText = summary?.steps.joined(separator: "\n") ?? ""
        self.visibility = summary?.visibility ?? .privateVisibility
    }

    var steps: [String] {
        stepsText
            .split(whereSeparator: \ .isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct RecipeStepField: Identifiable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct RecipeIngredientEditorTarget: Identifiable, Hashable {
    let ingredientID: UUID
    var id: UUID { ingredientID }
}

final class RecipeEditorDraftStore: ObservableObject, Identifiable {
    let id = UUID()

    @Published var draft: RecipeDraft
    @Published var stepFields: [RecipeStepField]
    @Published var isIngredientPickerPresented = false
    @Published var ingredientEditorTarget: RecipeIngredientEditorTarget?

    let initialDraft: RecipeDraft

    init(draft: RecipeDraft) {
        self.draft = draft
        self.stepFields = draft.steps.map { RecipeStepField(text: $0) }
        self.initialDraft = draft
    }
}

enum RecipeCategory: String, CaseIterable, Identifiable, Codable {
    case none = ""
    case soup
    case hot
    case stew
    case porridge
    case meat
    case fish
    case pasta
    case pizza
    case salad
    case appetizer
    case side
    case sauce
    case baking
    case dessert
    case drink
    case other

    var id: String { rawValue }

    var titleKey: String {
        "recipe.category.\(rawValue.isEmpty ? "none" : rawValue)"
    }

    var title: String {
        NSLocalizedString(titleKey, comment: "Recipe category")
    }

    init(rawString: String) {
        self = RecipeCategory(rawValue: rawString) ?? .none
    }
}

enum SearchScope: String, CaseIterable, Identifiable {
    case products
    case recipes
    case mealTemplates

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .products:
            return "search.scope.products"
        case .recipes:
            return "search.scope.recipes"
        case .mealTemplates:
            return "search.scope.meals"
        }
    }

    var title: String {
        switch self {
        case .products:
            return NSLocalizedString(titleKey, comment: "Search scope title")
        case .recipes:
            return NSLocalizedString(titleKey, comment: "Search scope title")
        case .mealTemplates:
            return NSLocalizedString(titleKey, tableName: nil, bundle: .main, value: "Meals", comment: "Search scope title")
        }
    }
}
