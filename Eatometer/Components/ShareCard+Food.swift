import Foundation

/// Turns the app's own objects into a card.
///
/// Kept apart from the drawing so the view knows nothing about meals, recipes or
/// products — it takes a title, some lines and four numbers, and that is a
/// short enough contract to keep true.
extension ShareCard {
    /// A meal or a meal plan: its items, and what they come to together.
    static func make(
        title: String,
        kindKey: String,
        subtitle: String = "",
        items: [MealItemEntry],
        nutrition: NutritionSummary
    ) -> ShareCard {
        ShareCard(
            title: title,
            kind: NSLocalizedString(kindKey, comment: "Shared item kind"),
            subtitle: subtitle,
            items: items.map(line(for:)),
            nutrition: nutrition,
            nutritionCaption: NSLocalizedString("share.card.total", comment: "Totals caption")
        )
    }

    /// A recipe, described per serving — which is how it is cooked and how the
    /// app shows it, and so how it should read to whoever receives it.
    static func make(recipe: RecipeSummary) -> ShareCard {
        let servings = max(recipe.servings, 1)
        return ShareCard(
            title: recipe.title,
            kind: NSLocalizedString("share.card.kind.recipe", comment: "Recipe"),
            subtitle: String(
                format: NSLocalizedString("share.card.servings", comment: "Servings count"),
                servings
            ),
            items: recipe.ingredients.map(line(for:)),
            nutrition: NutritionSummary(
                calories: recipe.caloriesPerServing,
                protein: recipe.proteinPerServing,
                fat: recipe.fatPerServing,
                carbs: recipe.carbsPerServing
            ),
            nutritionCaption: NSLocalizedString("share.card.per_serving", comment: "Per serving caption")
        )
    }

    /// A product has no composition — it is the ingredient. Its figures are per
    /// 100 g, and saying so is the difference between a useful card and a
    /// misleading one.
    static func make(product: ProductSummary) -> ShareCard {
        ShareCard(
            title: product.name,
            kind: NSLocalizedString("share.card.kind.product", comment: "Product"),
            subtitle: product.brand.trimmingCharacters(in: .whitespacesAndNewlines),
            items: [],
            nutrition: NutritionSummary(
                calories: product.caloriesPer100g,
                protein: product.proteinPer100g,
                fat: product.fatPer100g,
                carbs: product.carbsPer100g
            ),
            nutritionCaption: NSLocalizedString("share.card.per_100g", comment: "Per 100 g caption")
        )
    }

    // MARK: - Lines

    /// "Oat flakes, 80 g" — the name and how much of it.
    ///
    /// Nutrition per line is left out on purpose: four figures repeated down the
    /// card drown the one set that matters, at the bottom.
    private static func line(for item: MealItemEntry) -> String {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = name.isEmpty
            ? NSLocalizedString("addmeal.item.manual_title", comment: "Manual entry")
            : name
        return "\(resolved), \(amountText(item.amount, unit: item.unit))"
    }

    private static func line(for ingredient: RecipeIngredientSummary) -> String {
        let name = ingredient.linkedProductSummary?.name
            ?? ingredient.nestedRecipeSnapshot?.title
            ?? ingredient.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = name.isEmpty
            ? NSLocalizedString("recipe.fallback_title", comment: "Unnamed ingredient")
            : name
        return "\(resolved), \(amountText(ingredient.amount, unit: ingredient.unit))"
    }

    private static func amountText(_ value: Double, unit: MealItemUnit) -> String {
        let rounded = (value * 10).rounded() / 10
        let number = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)

        switch unit {
        case .grams:
            return "\(number) \(NSLocalizedString("unit.grams.short", comment: "Grams"))"
        case .milliliters:
            return "\(number) \(NSLocalizedString("unit.milliliters.short", comment: "Millilitres"))"
        case .serving:
            // The already-formatted number, not a re-rounded integer: half a
            // portion is a thing people log, and "1 serving" for 0.5 is wrong.
            return String(
                format: NSLocalizedString("share.card.servings_value", comment: "Servings amount"),
                number
            )
        }
    }
}
