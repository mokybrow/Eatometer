import SwiftUI

struct MealTemplateEditorSheet: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    private let initialDraft: MealTemplateDraft

    @State private var draft: MealTemplateDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var libraryPickerPresentation: LibraryPickerPresentation?
    @State private var quantityEditorTarget: ItemQuantityEditorTarget?
    @State private var pendingCatalogItemIDs: Set<UUID> = []
    @State private var sharePayload: FoodSharePayload?
    @State private var pendingShareSheetItem: SystemShareSheetItem?
    @State private var isPreparingShare = false

    private struct ItemQuantityEditorTarget: Identifiable {
        let itemID: UUID
        var id: UUID { itemID }
    }

    private struct LibraryPickerPresentation: Identifiable {
        let id = UUID()
        let title: String
        let scopes: [SearchScope]
    }

    init(draft: MealTemplateDraft = MealTemplateDraft()) {
        self.initialDraft = draft
        _draft = State(initialValue: draft)
    }

    private var isExistingMealTemplate: Bool {
        guard let mealTemplateID = draft.mealTemplateID else { return false }
        return catalogService.mealTemplateSummary(id: mealTemplateID) != nil
    }

    private var canSave: Bool {
        hasChanges && !normalizedDraft(draft).title.isEmpty && hasValidItemsToSave
    }

    private var hasChanges: Bool {
        normalizedDraft(draft) != normalizedDraft(initialDraft)
    }

    private var hasValidItemsToSave: Bool {
        !draft.items.isEmpty && draft.items.allSatisfy {
            ($0.productID != nil || $0.recipeID != nil) && $0.amount >= minimumAmount(for: $0.unit)
        }
    }

    private var resolvedShareURL: URL? {
        sharePayload?.resolvedShareURL
    }

    private var liveNutrition: NutritionSummary {
        NutritionSummary(
            calories: draft.items.reduce(0) { $0 + $1.calories },
            protein: draft.items.reduce(0) { $0 + $1.protein },
            fat: draft.items.reduce(0) { $0 + $1.fat },
            carbs: draft.items.reduce(0) { $0 + $1.carbs }
        )
    }

    private var catalogDraftItems: [MealItemEntry] {
        draft.items.filter { !pendingCatalogItemIDs.contains($0.id) }
    }

    private var navigationTitleKey: LocalizedStringKey {
        draft.mealTemplateID == nil ? "recipes.add_saved_meal" : "mealtemplate.editor.edit_title"
    }

    private func libraryPickerTitle(for scope: SearchScope) -> String {
        switch scope {
        case .products:
            return NSLocalizedString("products.add", comment: "Add product button title")
        case .recipes:
            return NSLocalizedString("recipes.add", comment: "Add recipe button title")
        case .mealTemplates:
            return NSLocalizedString("mealtemplate.editor.library.title", comment: "Ration library picker title")
        }
    }

    private var shareSavedMealTitle: String {
        NSLocalizedString("mealtemplate.editor.share", comment: "Share ration action title")
    }

    private var genericSaveErrorMessage: String {
        NSLocalizedString("mealtemplate.editor.save_error.generic", comment: "Ration generic save error")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                    basicsCard
                    itemsSection
                    totalsCard
                }
                .eoCardInsets()
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .dismissesKeyboardInteractively()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .eoPageBackground()
            .overlay {
                if isSaving {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .eoSheetChrome(
                "mealtemplate.editor.sheet_title",
                trailing: .confirm(isEnabled: canSave && !isSaving) {
                    saveMealTemplate()
                },
                onClose: { dismiss() }
            )
        }
        .alert("common.error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("common.ok", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: draft.mealTemplateID) {
            guard isExistingMealTemplate else { return }
            await loadSharePayload()
        }
        .task {
            await resolveItemNutritionIfNeeded()
        }
        .sheet(item: $libraryPickerPresentation, onDismiss: discardPendingCatalogItems) { presentation in
            FoodCatalogLookupSheet(
                title: presentation.title,
                allowedScopes: presentation.scopes,
                onSelectAndEditProduct: { product in
                    let resolved = await catalogService.fetchProduct(id: product.id) ?? product
                    return await MainActor.run {
                        let newItem = Self.makeItem(from: resolved)
                        draft.items.append(newItem)
                        pendingCatalogItemIDs.insert(newItem.id)
                        return newItem.id
                    }
                },
                onSelectAndEditRecipe: { recipe in
                    let resolved = await catalogService.fetchRecipe(id: recipe.id) ?? recipe
                    return await MainActor.run {
                        let newItem = makeItem(from: resolved)
                        draft.items.append(newItem)
                        pendingCatalogItemIDs.insert(newItem.id)
                        return newItem.id
                    }
                },
                addedItems: catalogDraftItems,
                itemBindingProvider: { itemID in
                    bindingForDraftItem(withID: itemID)
                },
                customEditorSheetProvider: { itemID, closeEditor in
                    pendingCatalogItemEditor(for: itemID, onClose: closeEditor)
                },
                onRemoveAddedItem: { itemID in
                    removeCatalogDraftItem(withID: itemID)
                },
                onSelectProduct: { product in
                    draft.items.append(Self.makeItem(from: product))
                },
                onSelectRecipe: { recipe in
                    draft.items.append(makeItem(from: recipe))
                }
            )
            .environmentObject(catalogService)
        }
        .sheet(item: $pendingShareSheetItem) { item in
            SystemShareSheet(draft: item) {
                pendingShareSheetItem = nil
            }
        }
        .sheet(item: $quantityEditorTarget) { target in
            if let itemBinding = bindingForDraftItem(withID: target.itemID) {
                MealItemQuantityEditorSheet(
                    item: itemBinding,
                    catalogService: catalogService,
                    onDelete: {
                        removeDraftItem(withID: target.itemID)
                    },
                    onClose: {
                        quantityEditorTarget = nil
                    }
                )
            }
        }
    }

    private var basicsCard: some View {
        EOCard {
            EOTextFieldRow("mealtemplate.editor.title.placeholder", text: $draft.title)
        }
    }

    private var itemsSection: some View {
        EOCard {
            EOCardHeaderRow("addmeal.add_food", systemImage: "magnifyingglass") {
                libraryPickerPresentation = LibraryPickerPresentation(
                    title: libraryPickerTitle(for: .products),
                    scopes: [.products, .mealTemplates, .recipes]
                )
            }

            ForEach(Array(draft.items.enumerated()), id: \.element.id) { _, item in
                EORowSeparator()
                itemRow(for: item)
            }
        }
    }

    private func actionButton(titleKey: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        actionButton(
            title: NSLocalizedString(titleKey, comment: "Action button title"),
            systemImage: systemImage,
            tint: tint,
            action: action
        )
    }

    private func actionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)

                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private var totalsCard: some View {
        EOCard {
            EOCardTitleRow(title: Text(verbatim: nutritionFactsTitle))
            EORowSeparator()
            totalsRow("addmeal.total.calories", value: liveNutrition.calories, unit: NSLocalizedString("diary.kcal", comment: "Kilocalories"))
            EORowSeparator()
            totalsRow("addmeal.total.protein", value: liveNutrition.protein, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            EORowSeparator()
            totalsRow("addmeal.total.carbs", value: liveNutrition.carbs, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            EORowSeparator()
            totalsRow("addmeal.total.fat", value: liveNutrition.fat, unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
        }
    }

    private func totalsRow(_ title: LocalizedStringKey, value: Int, unit: String) -> some View {
        EOListRow(
            title: Text(title),
            accessory: .value(Text(verbatim: "\(value) \(unit)"))
        )
    }

    private func itemRow(for item: MealItemEntry) -> some View {
        Button {
            quantityEditorTarget = ItemQuantityEditorTarget(itemID: item.id)
        } label: {
            EOListRow(
                title: Text(verbatim: displayTitle(for: item)),
                subtitle: Text(verbatim: itemAmountAndCompactNutritionText(item)),
                accessory: .valueChevron(Text("common.edit"))
            )
        }
        .buttonStyle(.plain)
        .eoRowContextMenu {
            EODestructiveMenuButton("common.delete", systemImage: "trash") {
                removeDraftItem(withID: item.id)
            }
        }
    }

    private func displayTitle(for item: MealItemEntry) -> String {
        let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("addmeal.item.product_fallback", comment: "Meal item fallback title") : trimmed
    }

    private func productSummary(for item: MealItemEntry) -> ProductSummary? {
        catalogService.productSummary(for: item)
    }

    private func itemAmountAndCompactNutritionText(_ item: MealItemEntry) -> String {
        let caloriesUnit = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        let proteinShort = NSLocalizedString("recipe.detail.protein_short", comment: "Protein short title")
        let fatShort = NSLocalizedString("recipe.detail.fat_short", comment: "Fat short title")
        let carbsShort = NSLocalizedString("recipe.detail.carbs_short", comment: "Carbs short title")
        let quantityText = displayFoodQuantityText(amount: item.amount, unit: item.unit, servingLabel: item.servingLabel, product: productSummary(for: item))
        return "\(quantityText) · \(item.calories) \(caloriesUnit) · \(proteinShort) \(item.protein) · \(fatShort) \(item.fat) · \(carbsShort) \(item.carbs)"
    }

    private func bindingForDraftItem(withID itemID: UUID) -> Binding<MealItemEntry>? {
        guard let currentItem = draft.items.first(where: { $0.id == itemID }) else { return nil }

        return Binding(
            get: {
                draft.items.first(where: { $0.id == itemID }) ?? currentItem
            },
            set: { updatedItem in
                guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else { return }
                draft.items[index] = updatedItem
            }
        )
    }

    private func removeDraftItem(withID itemID: UUID) {
        guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else { return }
        pendingCatalogItemIDs.remove(itemID)
        draft.items.remove(at: index)
        if quantityEditorTarget?.itemID == itemID {
            quantityEditorTarget = nil
        }
    }

    private func pendingCatalogItemEditor(for itemID: UUID, onClose: @escaping () -> Void) -> AnyView? {
        guard let itemBinding = bindingForDraftItem(withID: itemID) else { return nil }

        return AnyView(
            MealItemQuantityEditorSheet(
                item: itemBinding,
                catalogService: catalogService,
                onDelete: {
                    removeCatalogDraftItem(withID: itemID)
                },
                onCancel: {
                    discardPendingCatalogItem(withID: itemID)
                    onClose()
                },
                onConfirm: {
                    commitPendingCatalogItem(withID: itemID)
                    onClose()
                },
                onClose: {
                    discardPendingCatalogItem(withID: itemID)
                    onClose()
                }
            )
        )
    }

    private func commitPendingCatalogItem(withID itemID: UUID) {
        pendingCatalogItemIDs.remove(itemID)
    }

    private func discardPendingCatalogItem(withID itemID: UUID) {
        guard pendingCatalogItemIDs.remove(itemID) != nil else { return }
        removeDraftItem(withID: itemID)
    }

    private func discardPendingCatalogItems() {
        guard !pendingCatalogItemIDs.isEmpty else { return }
        let itemIDs = pendingCatalogItemIDs
        pendingCatalogItemIDs.removeAll()
        draft.items.removeAll { itemIDs.contains($0.id) }
    }

    private func removeCatalogDraftItem(withID itemID: UUID) {
        pendingCatalogItemIDs.remove(itemID)
        removeDraftItem(withID: itemID)
    }

    private func minimumAmount(for unit: MealItemUnit) -> Double {
        switch unit {
        case .serving, .grams, .milliliters:
            return 1
        }
    }

    private func nutrientValueText(_ value: Int) -> String {
        "\(value)"
    }

    private func normalizedDraft(_ draft: MealTemplateDraft) -> MealTemplateDraft {
        var normalized = draft
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.details = normalized.details.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.items = normalized.items.filter { $0.productID != nil || $0.recipeID != nil }
        return normalized
    }

    private func saveMealTemplate() {
        guard canSave else { return }

        let draftToSave = normalizedDraft(draft)
        isSaving = true

        Task {
            let saved = await catalogService.saveMealTemplate(draftToSave)
            await MainActor.run {
                isSaving = false
                if saved != nil {
                    dismiss()
                } else {
                    errorMessage = catalogService.lastErrorMessage ?? genericSaveErrorMessage
                }
            }
        }
    }

    private func loadSharePayload() async {
        guard sharePayload == nil else { return }
        guard let mealTemplateID = draft.mealTemplateID else { return }
        guard let payload = await catalogService.shareMealTemplate(id: mealTemplateID) else { return }
        sharePayload = payload
    }

    @MainActor
    private func presentShareSheet() {
        if let payload = sharePayload, let resolvedShareURL {
            pendingShareSheetItem = SystemShareSheetItem(message: payload.localizedShareMessage, url: resolvedShareURL)
            return
        }
        guard !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            await loadSharePayload()
            isPreparingShare = false
            if let payload = sharePayload, let resolvedShareURL {
                pendingShareSheetItem = SystemShareSheetItem(message: payload.localizedShareMessage, url: resolvedShareURL)
            }
        }
    }

    private func resolveItemNutritionIfNeeded() async {
        for (index, item) in draft.items.enumerated() {
            if let productID = item.productID {
                var product = catalogService.productSummary(for: item)
                if product == nil {
                    product = await catalogService.fetchProductSnapshot(id: productID)
                }
                if let product {
                    draft.items[index].name = product.name
                    draft.items[index].caloriesPer100g = product.caloriesPer100g
                    draft.items[index].proteinPer100g = product.proteinPer100g
                    draft.items[index].fatPer100g = product.fatPer100g
                    draft.items[index].carbsPer100g = product.carbsPer100g
                    draft.items[index].productSnapshot = product
                }
            } else if let recipeID = item.recipeID {
                var recipe = catalogService.recipeSummary(for: item)
                if recipe == nil {
                    recipe = await catalogService.fetchRecipeSnapshot(id: recipeID)
                }
                if let recipe {
                    let nutrition = catalogService.nutritionSummary(for: recipe, unit: item.unit)
                    draft.items[index].name = recipe.title
                    draft.items[index].caloriesPer100g = nutrition.calories
                    draft.items[index].proteinPer100g = nutrition.protein
                    draft.items[index].fatPer100g = nutrition.fat
                    draft.items[index].carbsPer100g = nutrition.carbs
                    draft.items[index].recipeSnapshot = recipe
                }
            }
        }
    }

    private static func makeItem(from product: ProductSummary) -> MealItemEntry {
        let selection = product.selectionPayload()
        return MealItemEntry(
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
            recipeID: nil,
            productSnapshot: product,
            recipeSnapshot: nil
        )
    }

    private func makeItem(from recipe: RecipeSummary) -> MealItemEntry {
        catalogService.makeMealItem(from: recipe)
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

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
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

    private func nutritionSnapshotCard(summary: NutritionSummary) -> some View {
        NutritionFactsTableCard(
            headerTitle: NSLocalizedString("addmeal.section.total", comment: "Total nutrition card title"),
            summary: summary
        )
    }

    private func nutritionSummaryRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            NutritionValueText(value: value)
        }
        .padding(.vertical, 10)
    }

    private var nutritionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private func cardSection<Content: View>(horizontalPadding: CGFloat = 20, verticalPadding: CGFloat = 20, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                    .fill(Color.appCardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }
}
