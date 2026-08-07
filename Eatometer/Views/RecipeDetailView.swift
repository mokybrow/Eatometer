import SwiftUI
import UIKit

struct RecipeDetailView: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    let recipeID: UUID
    let initialRecipe: RecipeSummary
    var showsDismissButton: Bool = false

    @State private var sharePayload: FoodSharePayload?
    @State private var isPreparingShare = false
    @State private var pendingShareSheetItem: SystemShareSheetItem?
    @State private var isCookingModePresented = false
    @State private var selectedIngredientProduct: ProductSummary?
    @State private var selectedIngredientRecipe: RecipeSummary?

    private var isRecipeShare: Bool {
        sharePayload?.isRecipeShare == true
    }

    private var recipe: RecipeSummary {
        catalogService.recipeSummary(id: recipeID) ?? initialRecipe
    }

    private var nutritionPreview: RecipeNutritionPreview {
        catalogService.nutritionPreview(for: recipe)
    }

    private var effectiveOutputWeight: Double {
        catalogService.effectiveOutputWeight(for: recipe)
    }

    private var portionWeight: Double {
        catalogService.portionWeight(for: recipe)
    }

    private var sortedIngredients: [RecipeIngredientSummary] {
        recipe.ingredients.sorted { lhs, rhs in
            let lhsAmount = comparableAmount(for: lhs)
            let rhsAmount = comparableAmount(for: rhs)
            if lhsAmount != rhsAmount {
                return lhsAmount > rhsAmount
            }

            let lhsName = ingredientName(for: lhs)
            let rhsName = ingredientName(for: rhs)
            let nameOrder = lhsName.localizedCaseInsensitiveCompare(rhsName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var totalWeightMetricTitle: String {
        if recipe.outputWeightGrams > 0 {
            return NSLocalizedString("recipe.editor.output_weight", comment: "Finished dish weight title")
        }

        return NSLocalizedString("recipe.editor.total_weight", comment: "Total weight title")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                EOCard {
                    EOListRow(title: Text(verbatim: recipe.title))
                    EORowSeparator()
                    EOListRow(
                        title: Text("recipe.editor.servings"),
                        accessory: .value(Text(verbatim: String(max(recipe.servings, 1))))
                    )
                }

                ingredientsCard
                nutritionFactsCard
            }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .eoPageBackground()
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: recipe.id) {
            await loadSharePayloadIfNeeded()
        }
        .task(id: recipe.ingredients) {
            await resolveIngredientReferencesIfNeeded()
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
                        Button("recipe.cooking.title") {
                            isCookingModePresented = true
                        }
                        Button("common.edit") {
                            catalogService.presentRecipeEditor(draft: RecipeDraft(summary: recipe))
                        }
                        Button("common.delete", role: .destructive) {
                            deleteRecipe()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.primary)
                }
            }
        }
        .navigationDestination(item: $selectedIngredientProduct) { product in
            ProductDetailView(productID: product.id, initialProduct: product)
                .environmentObject(catalogService)
        }
        .navigationDestination(item: $selectedIngredientRecipe) { recipe in
            RecipeDetailView(recipeID: recipe.id, initialRecipe: recipe)
                .environmentObject(catalogService)
        }
        .fullScreenCover(isPresented: $isCookingModePresented) {
            RecipeCookingModeView(recipe: recipe)
                .environmentObject(catalogService)
        }
        .sheet(item: $pendingShareSheetItem) { item in
            SystemShareSheet(draft: item) {
                pendingShareSheetItem = nil
            }
        }
    }

    private func deleteRecipe() {
        Task {
            let success = await catalogService.deleteRecipe(id: recipe.id)
            if success {
                await MainActor.run { dismiss() }
            }
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

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("today.stats.summary.title")

            VStack(spacing: 0) {
                if RecipeCategory(rawString: recipe.category) != .none {
                    metricsValueRow(
                        title: NSLocalizedString("recipe.editor.category", comment: "Recipe category title"),
                        value: RecipeCategory(rawString: recipe.category).title
                    )

                    nutritionDivider
                }

                metricsValueRow(
                    title: NSLocalizedString("recipe.editor.servings", comment: "Servings title"),
                    value: String(recipe.servings)
                )

                nutritionDivider

                metricsValueRow(
                    title: NSLocalizedString("recipe.editor.portion_weight", comment: "Portion weight title"),
                    value: portionWeight > 0 ? gramsText(Int(portionWeight.rounded())) : "-"
                )

                nutritionDivider

                metricsValueRow(
                    title: totalWeightMetricTitle,
                    value: effectiveOutputWeight > 0 ? gramsText(Int(effectiveOutputWeight.rounded())) : "-"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("recipe.detail.about")

            VStack(alignment: .leading, spacing: 0) {
                overviewDetailRow(
                    title: NSLocalizedString("recipe.editor.name", comment: "Recipe name title"),
                    value: recipe.title,
                    valueFont: .body.weight(.semibold),
                    valueColor: .primary
                )

                let trimmedDetails = recipe.details.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedDetails.isEmpty {
                    overviewDivider
                    overviewDetailRow(
                        title: NSLocalizedString("product.editor.description", comment: "Description"),
                        value: trimmedDetails,
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

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(Text(nutritionFactsTitle))

            NutritionFactsTableCard(
                leftHeaderTitle: NSLocalizedString("recipe.editor.per_100g", comment: "Per 100g"),
                rightHeaderTitle: NSLocalizedString("recipe.editor.per_serving", comment: "Per serving"),
                leftSummary: nutritionPreview.per100g,
                rightSummary: nutritionPreview.perServing
            )
        }
    }

    private func toolbarIcon(_ systemName: String, color: Color = .primary) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .contentShape(Circle())
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("recipe.editor.section.ingredients")

            VStack(spacing: 0) {
                if sortedIngredients.isEmpty {
                    Text("recipe.detail.ingredients.empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(sortedIngredients.enumerated()), id: \.element.id) { index, ingredient in
                        ingredientRow(ingredient)

                        if index < sortedIngredients.count - 1 {
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

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("recipe.editor.section.steps")

            VStack(spacing: 0) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    stepRow(index: index, step: step)

                    if index < recipe.steps.count - 1 {
                        nutritionDivider
                            .padding(.vertical, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private func stepRow(index: Int, step: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1).")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            Text(step.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
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

    // MARK: - Cards (mock-up "Recipe Viewer" layout)

    private var ingredientsCard: some View {
        EOCard {
            EOCardTitleRow("recipe.editor.section.ingredients")

            if sortedIngredients.isEmpty {
                EORowSeparator()
                EOListRow("recipe.detail.ingredients.empty", titleColor: .secondary)
            } else {
                ForEach(sortedIngredients) { ingredient in
                    EORowSeparator()
                    ingredientRow(ingredient)
                }
            }
        }
    }

    private var nutritionFactsCard: some View {
        EOCard {
            EOCardTitleRow(title: Text(verbatim: nutritionFactsTitle))
            EORowSeparator()
            viewerNutritionRow("addmeal.total.calories", value: nutritionPreview.perServing.calories, unit: NSLocalizedString("diary.kcal", comment: "Kilocalories"))
            EORowSeparator()
            viewerNutritionRow("addmeal.total.protein", value: nutritionPreview.perServing.protein, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            EORowSeparator()
            viewerNutritionRow("addmeal.total.carbs", value: nutritionPreview.perServing.carbs, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            EORowSeparator()
            viewerNutritionRow("addmeal.total.fat", value: nutritionPreview.perServing.fat, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
        }
    }

    private func viewerNutritionRow(_ title: LocalizedStringKey, value: Int, unit: String) -> some View {
        EOListRow(
            title: Text(title),
            accessory: .value(Text(verbatim: "\(value) \(unit)"))
        )
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private func sectionTitle(_ title: Text) -> some View {
        title
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private var nutritionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 14)
    }

    private func metricsValueRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
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

    private var ingredientDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 14)
    }

    /// Mock-up row: ingredient name with an "amount – macros" meta line under it.
    private func ingredientRow(_ ingredient: RecipeIngredientSummary) -> some View {
        let note = ingredient.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let meta = note.isEmpty
            ? amountText(for: ingredient)
            : "\(amountText(for: ingredient)) - \(note)"

        return EOListRow(
            title: Text(verbatim: ingredientName(for: ingredient)),
            subtitle: Text(verbatim: meta)
        )
    }

    private func gramsText(_ value: Int) -> String {
        String(format: NSLocalizedString("recipe.grams_value", comment: "Grams value"), value)
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
        guard let payload = await catalogService.shareRecipe(id: recipe.id) else { return }
        sharePayload = payload
    }

    private func resolveIngredientReferencesIfNeeded() async {
        for ingredient in recipe.ingredients {
            if let productID = ingredient.productID,
               catalogService.productSummary(id: productID) == nil,
               ingredient.linkedProductSummary == nil {
                _ = await catalogService.fetchProduct(id: productID)
            }

            if let nestedRecipeID = ingredient.nestedRecipeID,
               catalogService.recipeSummary(id: nestedRecipeID) == nil,
               ingredient.linkedRecipeSummary == nil {
                _ = await catalogService.fetchRecipe(id: nestedRecipeID)
            }
        }
    }

    private func ingredientName(for ingredient: RecipeIngredientSummary) -> String {
        if let product = product(for: ingredient) {
            return product.name
        }
        if let nestedRecipe = nestedRecipe(for: ingredient) {
            return nestedRecipe.title
        }
        return NSLocalizedString("recipe.editor.new_ingredient", comment: "Ingredient fallback")
    }

    @ViewBuilder
    private func ingredientTitle(for ingredient: RecipeIngredientSummary) -> some View {
        if let product = product(for: ingredient) {
            Button {
                selectedIngredientProduct = product
            } label: {
                HStack(spacing: 6) {
                    Text(product.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if let nestedRecipe = nestedRecipe(for: ingredient) {
            Button {
                selectedIngredientRecipe = nestedRecipe
            } label: {
                HStack(spacing: 6) {
                    Text(nestedRecipe.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(ingredientName(for: ingredient))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func product(for ingredient: RecipeIngredientSummary) -> ProductSummary? {
        catalogService.productSummary(for: ingredient)
    }

    private func nestedRecipe(for ingredient: RecipeIngredientSummary) -> RecipeSummary? {
        catalogService.recipeSummary(for: ingredient)
    }

    private func comparableAmount(for ingredient: RecipeIngredientSummary) -> Double {
        switch ingredient.unit {
        case .grams, .milliliters:
            return ingredient.amount
        case .serving:
            if let product = product(for: ingredient) {
                return product.actualAmount(
                    for: ingredient.amount,
                    unit: ingredient.unit,
                    servingLabel: ingredient.servingLabel
                ).amount
            }

            if let nestedRecipe = nestedRecipe(for: ingredient) {
                let nestedPortionWeight = catalogService.portionWeight(for: nestedRecipe)
                if nestedPortionWeight > 0 {
                    return ingredient.amount * nestedPortionWeight
                }
            }

            return ingredient.amount
        }
    }

    private func amountText(for ingredient: RecipeIngredientSummary) -> String {
        displayFoodQuantityText(
            amount: ingredient.amount,
            unit: ingredient.unit,
            servingLabel: ingredient.servingLabel,
            product: product(for: ingredient)
        )
    }

    private func formattedAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value.magnitude < 1 ? 2 : 1
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

private struct RecipeCookingModeView: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    let recipe: RecipeSummary

    @State private var ingredients: [CookingIngredient]
    @State private var previousIdleTimerState = false

    init(recipe: RecipeSummary) {
        self.recipe = recipe
        _ingredients = State(initialValue: recipe.ingredients.map { CookingIngredient(source: $0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ingredientsSection

                    if !recipe.steps.isEmpty {
                        stepsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appPageBackground.ignoresSafeArea())
            .navigationTitle(Text(localizedCookingString("recipe.cooking.title", fallback: "Cooking mode")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("common.done", systemImage: "checkmark")
                    }
                    .tint(.accentColor)
                }
            }
        }
        .onAppear {
            previousIdleTimerState = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerState
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("recipe.editor.section.ingredients")

            VStack(spacing: 0) {
                if ingredients.isEmpty {
                    Text("recipe.detail.ingredients.empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        cookingIngredientRow(ingredient, index: index)

                        if index < ingredients.count - 1 {
                            divider
                                .padding(.vertical, 12)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("recipe.editor.section.steps")

            VStack(spacing: 0) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1).")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)

                        Text(step.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)

                    if index < recipe.steps.count - 1 {
                        divider
                            .padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private func cookingIngredientRow(_ ingredient: CookingIngredient, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ingredientName(for: ingredient.source))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !ingredient.source.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(ingredient.source.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                PressableIconButton(disabled: !canDecrease(ingredient), action: {
                    adjustIngredient(at: index, by: -amountStep(for: ingredient.unit))
                }) {
                    Label("recipe.editor.decrease", systemImage: "minus")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .opacity(canDecrease(ingredient) ? 1 : 0.45)
                }

                HStack(spacing: 8) {
                    Spacer(minLength: 0)

                    TextField(
                        "common.zero_placeholder",
                        text: amountBinding(for: index)
                    )
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .frame(minWidth: 72, idealWidth: 96, maxWidth: 120)

                    Text(unitText(for: ingredient))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.appPageBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                PressableIconButton(action: {
                    adjustIngredient(at: index, by: amountStep(for: ingredient.unit))
                }) {
                    Label("recipe.editor.increase", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func amountBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard ingredients.indices.contains(index) else { return "" }
                return formattedCookingAmount(displayAmount(for: ingredients[index]))
            },
            set: { newValue in
                guard ingredients.indices.contains(index) else { return }
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                guard let value = Double(normalized) else { return }
                setIngredientAmount(at: index, nextDisplayAmount: value)
            }
        )
    }

    private func adjustIngredient(at index: Int, by delta: Double) {
        guard ingredients.indices.contains(index) else { return }
        setIngredientAmount(at: index, nextDisplayAmount: displayAmount(for: ingredients[index]) + delta)
    }

    private func setIngredientAmount(at index: Int, nextDisplayAmount: Double) {
        guard ingredients.indices.contains(index) else { return }
        let currentDisplayAmount = max(displayAmount(for: ingredients[index]), minimumAmount(for: ingredients[index].unit))
        let resolvedNextDisplayAmount = max(nextDisplayAmount, minimumAmount(for: ingredients[index].unit))
        guard currentDisplayAmount > 0 else { return }

        let scale = resolvedNextDisplayAmount / currentDisplayAmount
        for ingredientIndex in ingredients.indices {
            ingredients[ingredientIndex].amount = max(
                minimumAmount(for: ingredients[ingredientIndex].unit),
                ingredients[ingredientIndex].amount * scale
            )
        }
    }

    private func displayAmount(for ingredient: CookingIngredient) -> Double {
        displayFoodQuantityValue(
            amount: ingredient.amount,
            unit: ingredient.unit,
            servingLabel: ingredient.servingLabel,
            product: product(for: ingredient.source)
        )
    }

    private func canDecrease(_ ingredient: CookingIngredient) -> Bool {
        displayAmount(for: ingredient) > minimumAmount(for: ingredient.unit)
    }

    private func amountStep(for unit: MealItemUnit) -> Double {
        switch unit {
        case .serving:
            return 1
        case .grams, .milliliters:
            return 10
        }
    }

    private func minimumAmount(for unit: MealItemUnit) -> Double {
        switch unit {
        case .serving:
            return 1
        case .grams, .milliliters:
            return 0.01
        }
    }

    private func unitText(for ingredient: CookingIngredient) -> String {
        if let product = product(for: ingredient.source),
           let servingOption = product.selectableServingOption(matching: ingredient.servingLabel) {
            return servingOption.quantityTitle
        }
        return ingredient.unit.shortTitle
    }

    private func ingredientName(for ingredient: RecipeIngredientSummary) -> String {
        if let product = product(for: ingredient) {
            return product.name
        }
        if let nestedRecipe = nestedRecipe(for: ingredient) {
            return nestedRecipe.title
        }
        return NSLocalizedString("recipe.editor.new_ingredient", comment: "Ingredient fallback")
    }

    private func product(for ingredient: RecipeIngredientSummary) -> ProductSummary? {
        catalogService.productSummary(for: ingredient)
    }

    private func nestedRecipe(for ingredient: RecipeIngredientSummary) -> RecipeSummary? {
        catalogService.recipeSummary(for: ingredient)
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private func formattedCookingAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value.magnitude < 1 ? 2 : 1
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}

private struct CookingIngredient: Identifiable, Hashable {
    let id: UUID
    let source: RecipeIngredientSummary
    var amount: Double
    let unit: MealItemUnit
    let servingLabel: String

    init(source: RecipeIngredientSummary) {
        self.id = source.id
        self.source = source
        self.amount = source.amount
        self.unit = source.unit
        self.servingLabel = source.servingLabel
    }
}

private func localizedCookingString(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "Cooking mode")
}
