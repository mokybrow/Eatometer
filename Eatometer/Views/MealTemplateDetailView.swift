import SwiftUI

struct MealTemplateDetailView: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    let mealTemplateID: UUID
    let initialMealTemplate: MealTemplateSummary
    var showsDismissButton: Bool = false

    @State private var sharePayload: FoodSharePayload?
    @State private var isPreparingShare = false
    @State private var pendingShareSheetItem: SystemShareSheetItem?
    @State private var selectedProduct: ProductSummary?
    @State private var selectedRecipe: RecipeSummary?
    @State private var isEditorPresented = false

    private var mealTemplate: MealTemplateSummary {
        catalogService.mealTemplateSummary(id: mealTemplateID) ?? initialMealTemplate
    }

    private var resolvedItems: [MealItemEntry] {
        mealTemplate.items.map(resolveItem)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                EOCard {
                    EOListRow(title: Text(verbatim: mealTemplate.title))
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
        .navigationTitle(mealTemplate.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: mealTemplate.id) {
            await loadSharePayloadIfNeeded()
        }
        .task(id: mealTemplate.items) {
            await resolveItemReferencesIfNeeded()
        }
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                toolbarShareButton

                if !showsDismissButton {
                    Menu {
                        Button(NSLocalizedString("common.edit", comment: "Edit action")) {
                            isEditorPresented = true
                        }
                        Button(NSLocalizedString("common.delete", comment: "Delete action"), role: .destructive) {
                            deleteMealTemplate()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.primary)
                }
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            MealTemplateEditorSheet(draft: MealTemplateDraft(summary: mealTemplate))
                .environmentObject(catalogService)
        }
        .sheet(item: $pendingShareSheetItem) { item in
            SystemShareSheet(draft: item) {
                pendingShareSheetItem = nil
            }
        }
        .navigationDestination(item: $selectedProduct) { product in
            ProductDetailView(productID: product.id, initialProduct: product)
                .environmentObject(catalogService)
        }
        .navigationDestination(item: $selectedRecipe) { recipe in
            RecipeDetailView(recipeID: recipe.id, initialRecipe: recipe)
                .environmentObject(catalogService)
        }
    }

    private func deleteMealTemplate() {
        Task {
            let success = await catalogService.deleteMealTemplate(id: mealTemplate.id)
            if success {
                await MainActor.run { dismiss() }
            }
        }
    }

    // MARK: - Cards (mock-up "Meal Viewer" layout)

    private var itemsCard: some View {
        EOCard {
            EOCardTitleRow(title: Text(verbatim: NSLocalizedString("mealtemplate.detail.items", comment: "Food in meal")))

            if resolvedItems.isEmpty {
                EORowSeparator()
                EOListRow(
                    title: Text(verbatim: NSLocalizedString("mealtemplate.detail.empty_items", comment: "Empty meal")),
                    titleColor: .secondary
                )
            } else {
                ForEach(resolvedItems) { item in
                    EORowSeparator()
                    itemRow(item)
                }
            }
        }
    }

    private var nutritionFactsCard: some View {
        EOCard {
            EOCardTitleRow(title: Text(verbatim: nutritionFactsTitle))
            EORowSeparator()
            viewerNutritionRow("addmeal.total.calories", value: mealTemplate.calories, unit: NSLocalizedString("diary.kcal", comment: "Kilocalories"))
            EORowSeparator()
            viewerNutritionRow("addmeal.total.protein", value: mealTemplate.protein, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            EORowSeparator()
            viewerNutritionRow("addmeal.total.carbs", value: mealTemplate.carbs, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            EORowSeparator()
            viewerNutritionRow("addmeal.total.fat", value: mealTemplate.fat, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
        }
    }

    @ViewBuilder
    private var toolbarShareButton: some View {
        Button {
            presentShareSheet()
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .tint(.primary)
        .disabled(isPreparingShare)
        .accessibilityLabel(Text("common.share"))
    }

    private func toolbarIcon(_ systemName: String, color: Color = .primary) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .contentShape(Circle())
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(NSLocalizedString("mealtemplate.detail.about", comment: "Ration overview section title"))

            VStack(alignment: .leading, spacing: 0) {
                overviewDetailRow(
                    title: NSLocalizedString("mealtemplate.detail.name", comment: "Ration name label"),
                    value: mealTemplate.title,
                    valueFont: .body.weight(.semibold),
                    valueColor: .primary
                )

                if !mealTemplate.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    overviewDivider
                    overviewDetailRow(
                        title: NSLocalizedString("recipe.editor.description", comment: "Description"),
                        value: mealTemplate.details,
                        valueFont: .body.weight(.semibold),
                        valueColor: .primary
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 14)
    }

    private func overviewDetailRow(title: String, value: String, valueFont: Font, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text(value)
                .font(valueFont)
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(NSLocalizedString("mealtemplate.detail.items", comment: "Ration items section title"))

            VStack(spacing: 0) {
                if resolvedItems.isEmpty {
                    Text(NSLocalizedString("mealtemplate.detail.empty_items", comment: "Ration empty items message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(resolvedItems.enumerated()), id: \.element.id) { index, item in
                        itemRow(item)

                        if index < resolvedItems.count - 1 {
                            ingredientDivider
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(nutritionFactsTitle)

            NutritionFactsTableCard(
                headerTitle: NSLocalizedString("addmeal.section.total", comment: "Total nutrition card title"),
                summary: NutritionSummary(
                    calories: mealTemplate.calories,
                    protein: mealTemplate.protein,
                    fat: mealTemplate.fat,
                    carbs: mealTemplate.carbs
                )
            )
        }
    }

    private func viewerNutritionRow(_ title: LocalizedStringKey, value: Int, unit: String) -> some View {
        EOListRow(
            title: Text(title),
            accessory: .value(Text(verbatim: "\(value) \(unit)"))
        )
    }

    private func itemRow(_ item: MealItemEntry) -> some View {
        let destination = destination(for: item)

        return Group {
            if let destination {
                Button {
                    switch destination {
                    case .product(let product):
                        selectedProduct = product
                    case .recipe(let recipe):
                        selectedRecipe = recipe
                    }
                } label: {
                    itemRowContent(item)
                }
                .buttonStyle(.plain)
            } else {
                itemRowContent(item)
            }
        }
    }

    private func itemRowContent(_ item: MealItemEntry) -> some View {
        EOListRow(
            title: Text(verbatim: item.name),
            subtitle: Text(verbatim: itemMetaText(item))
        )
    }

    /// Mock-up meta line: "100 g – 90kc – 12p – 2c – 2f".
    private func itemMetaText(_ item: MealItemEntry) -> String {
        let amountText = displayFoodQuantityText(
            amount: item.amount,
            unit: item.unit,
            servingLabel: item.servingLabel,
            product: catalogService.productSummary(for: item)
        )
        return "\(amountText) - \(item.calories)kc - \(item.protein)p - \(item.carbs)c - \(item.fat)f"
    }

    private func sourceDescription(for item: MealItemEntry) -> String {
        if item.productID != nil {
            return NSLocalizedString("mealtemplate.detail.source.product", comment: "Ration item source product")
        }
        if item.recipeID != nil {
            return NSLocalizedString("mealtemplate.detail.source.recipe", comment: "Ration item source recipe")
        }
        return NSLocalizedString("mealtemplate.detail.source.saved_item", comment: "Ration item source fallback")
    }

    private func resolveItem(_ item: MealItemEntry) -> MealItemEntry {
        var resolved = item
        if let product = catalogService.productSummary(for: item) {
            resolved.name = product.name
            resolved.caloriesPer100g = product.caloriesPer100g
            resolved.proteinPer100g = product.proteinPer100g
            resolved.fatPer100g = product.fatPer100g
            resolved.carbsPer100g = product.carbsPer100g
            resolved.productSnapshot = product
            return resolved
        }

        if let recipe = catalogService.recipeSummary(for: item) {
            let nutrition = catalogService.nutritionSummary(for: recipe, unit: item.unit)
            resolved.name = recipe.title
            resolved.caloriesPer100g = nutrition.calories
            resolved.proteinPer100g = nutrition.protein
            resolved.fatPer100g = nutrition.fat
            resolved.carbsPer100g = nutrition.carbs
            resolved.recipeSnapshot = recipe
            return resolved
        }

        return resolved
    }

    private func destination(for item: MealItemEntry) -> ItemDestination? {
        if let product = catalogService.productSummary(for: item) {
            return .product(product)
        }
        if let recipe = catalogService.recipeSummary(for: item) {
            return .recipe(recipe)
        }
        return nil
    }

    private func resolveItemReferencesIfNeeded() async {
        for item in mealTemplate.items {
            if let productID = item.productID,
               catalogService.productSummary(id: productID) == nil,
               item.linkedProductSummary == nil {
                _ = await catalogService.fetchProduct(id: productID)
            } else if let recipeID = item.recipeID,
                      catalogService.recipeSummary(id: recipeID) == nil,
                      item.linkedRecipeSummary == nil {
                _ = await catalogService.fetchRecipe(id: recipeID)
            }
        }
    }

    private func shareSheetItem(for payload: FoodSharePayload) -> SystemShareSheetItem? {
        guard let url = payload.resolvedShareURL else { return nil }
        return SystemShareSheetItem(message: payload.localizedShareMessage, url: url)
    }

    @MainActor
    private func presentShareSheet() {
        if let payload = sharePayload, let item = shareSheetItem(for: payload) {
            pendingShareSheetItem = item
            return
        }
        guard !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            await loadSharePayloadIfNeeded()
            isPreparingShare = false
            if let payload = sharePayload, let item = shareSheetItem(for: payload) {
                pendingShareSheetItem = item
            }
        }
    }

    @MainActor
    private func loadSharePayloadIfNeeded() async {
        guard sharePayload == nil else { return }
        sharePayload = await catalogService.shareMealTemplate(id: mealTemplate.id)
    }

    private var nutritionFactsTitle: String {
        NSLocalizedString(
            "nutrition.facts.title",
            tableName: nil,
            bundle: .main,
            value: "Nutrition Facts",
            comment: "Nutrition facts table title"
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private var ingredientDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 8)
    }

    private var nutritionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private func gramsText(_ value: Int) -> String {
        String(format: NSLocalizedString("recipe.grams_value", comment: "Grams value"), value)
    }

    private func nutritionRow(title: String, value: String, explicitUnit: String? = nil) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            NutritionValueText(value: value, explicitUnit: explicitUnit)
        }
        .padding(.vertical, 7)
    }

    private enum ItemDestination {
        case product(ProductSummary)
        case recipe(RecipeSummary)
    }
}
