import SwiftUI

/// Read-only view of a logged meal ("Meal Viewer" in the mock-ups).
///
/// Tapping a meal card on the Diary opens this; editing is reached through the
/// card's context menu, the same way recipes and saved meals behave.
struct MealEntryViewerSheet: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    let title: String
    let items: [MealItemEntry]
    let nutrition: NutritionSummary
    let onShare: () -> Void

    private var nutritionFactsTitle: String {
        NSLocalizedString(
            "nutrition.facts.title",
            tableName: nil,
            bundle: .main,
            value: "Nutrition Facts",
            comment: "Nutrition facts table title"
        )
    }

    private var itemsTitle: String {
        NSLocalizedString(
            "mealtemplate.detail.items",
            tableName: nil,
            bundle: .main,
            value: "Food in Meal:",
            comment: "Food in meal section title"
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                    EOCard {
                        EOListRow(title: Text(verbatim: title))
                    }

                    itemsCard
                    nutritionFactsCard
                }
                .eoCardInsets()
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .eoPageBackground()
            .eoSheetChrome(
                title: Text(verbatim: title),
                trailing: .symbol(name: "square.and.arrow.up", action: onShare),
                onClose: { dismiss() }
            )
        }
    }

    private var itemsCard: some View {
        EOCard {
            EOCardTitleRow(title: Text(verbatim: itemsTitle))

            if items.isEmpty {
                EORowSeparator()
                EOListRow(
                    title: Text("mealtemplate.detail.empty_items"),
                    titleColor: .secondary
                )
            } else {
                ForEach(items) { item in
                    EORowSeparator()
                    EOListRow(
                        title: Text(verbatim: item.name),
                        subtitle: Text(verbatim: metaText(for: item))
                    )
                }
            }
        }
    }

    private var nutritionFactsCard: some View {
        EOCard {
            EOCardTitleRow(title: Text(verbatim: nutritionFactsTitle))
            EORowSeparator()
            row("addmeal.total.calories", value: nutrition.calories, unit: NSLocalizedString("diary.kcal", comment: "Kilocalories"))
            EORowSeparator()
            row("addmeal.total.protein", value: nutrition.protein, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            EORowSeparator()
            row("addmeal.total.carbs", value: nutrition.carbs, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            EORowSeparator()
            row("addmeal.total.fat", value: nutrition.fat, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
        }
    }

    private func row(_ title: LocalizedStringKey, value: Int, unit: String) -> some View {
        EOListRow(
            title: Text(title),
            accessory: .value(Text(verbatim: "\(value) \(unit)"))
        )
    }

    /// Mock-up meta line: "100 g - 90kc - 12p - 2c - 2f".
    private func metaText(for item: MealItemEntry) -> String {
        let amountText = displayFoodQuantityText(
            amount: item.amount,
            unit: item.unit,
            servingLabel: item.servingLabel,
            product: catalogService.productSummary(for: item)
        )
        return "\(amountText) - \(item.calories)kc - \(item.protein)p - \(item.carbs)c - \(item.fat)f"
    }
}
