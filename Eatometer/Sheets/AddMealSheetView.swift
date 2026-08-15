import SwiftUI

struct AddMealSheetView: View {
    @EnvironmentObject private var diaryService: FoodDiaryService
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    private let mergedSourceMealIDs: [UUID]
    private let initialQuickAdd: PendingMealQuickAdd?

    @State private var draft: MealEntry
    @State private var baselineDraft: MealEntry
    @State private var hasAppliedInitialQuickAdd = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var isLibraryPickerPresented: Bool = false
    @State private var quantityEditorTarget: ItemQuantityEditorTarget?
    @State private var manualNutritionEditorTarget: ManualNutritionEditorTarget?
    @State private var pendingCatalogItemIDs: Set<UUID> = []
    @State private var sharePayload: FoodSharePayload?
    @State private var pendingShareSheetItem: SystemShareSheetItem?
    @State private var isPreparingShare = false

    @MainActor
    private var resolvedShareSheetItem: SystemShareSheetItem? {
        guard let sharePayload else { return nil }
        return shareSheetItem(for: sharePayload)
    }

    private struct ItemQuantityEditorTarget: Identifiable {
        let itemID: UUID
        var id: UUID { itemID }
    }

    private struct ManualNutritionEditorTarget: Identifiable {
        let itemID: UUID?
        let item: MealItemEntry

        var id: UUID { item.id }
    }

    private static let legacyManualNutritionItemName = "Ручной ввод КБЖУ"

    private static var localizedManualNutritionItemName: String {
        NSLocalizedString("addmeal.item.manual_title", comment: "Manual nutrition item title")
    }

    private static func isManualNutritionName(_ rawValue: String) -> Bool {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return false }
        return trimmedValue == legacyManualNutritionItemName || trimmedValue == localizedManualNutritionItemName
    }

    init(
        editingMeal: MealEntry? = nil,
        mergedSourceMealIDs: [UUID] = [],
        preferredCategoryID: String? = nil,
        preferredDate: Date? = nil,
        initialQuickAdd: PendingMealQuickAdd? = nil
    ) {
        self.initialQuickAdd = initialQuickAdd
        if let editingMeal, mergedSourceMealIDs.isEmpty {
            self.mergedSourceMealIDs = [editingMeal.id]
        } else {
            self.mergedSourceMealIDs = mergedSourceMealIDs
        }

        let scheduledAt = Self.defaultScheduledAt(preferredDate: preferredDate)
        let defaultKind = MealKind.inferred(from: scheduledAt)
        let categoryID = preferredCategoryID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? preferredCategoryID!
            : defaultKind.rawValue
        let initialDraft = editingMeal ?? MealEntry(
            id: UUID(),
            kind: defaultKind,
            mealCategoryID: categoryID,
            title: defaultKind.title,
            items: [],
            note: "",
            scheduledAt: scheduledAt,
            nutrition: .zero
        )
        _draft = State(initialValue: initialDraft)
        _baselineDraft = State(initialValue: initialDraft)
    }

    private var resolvedCategoryTitle: String {
        diaryService.category(for: draft.mealCategoryID).displayTitle
    }

    private var canSave: Bool {
        hasChanges && (canDeleteExistingMeal || hasValidItemsToSave)
    }

    private var hasChanges: Bool {
        normalizedDraft != normalizedInitialDraft
    }

    private var normalizedDraft: MealEntry {
        normalizedMealForSaving(draft)
    }

    private var normalizedInitialDraft: MealEntry {
        normalizedMealForSaving(baselineDraft)
    }

    private var isExistingMeal: Bool {
        diaryService.meal(id: draft.id) != nil
    }

    private var isMergedCategoryDraft: Bool {
        Set(mergedSourceMealIDs).count > 1
    }

    private var hasValidItemsToSave: Bool {
        !normalizedDraft.items.isEmpty && normalizedDraft.items.allSatisfy { $0.amount >= minimumAmount(for: $0.unit) }
    }

    private var canDeleteExistingMeal: Bool {
        isExistingMeal && normalizedDraft.items.isEmpty
    }

    private var visibleItemIndices: [Int] {
        draft.items.indices.filter { !isManualNutritionEntry(draft.items[$0]) }
    }

    private var visibleDraftItems: [MealItemEntry] {
        visibleItemIndices.map { draft.items[$0] }
    }

    private var catalogDraftItems: [MealItemEntry] {
        draft.items.filter { !isManualNutritionEntry($0) && !pendingCatalogItemIDs.contains($0.id) }
    }

    private var liveNutrition: NutritionSummary {
        nutritionSummary(for: draft.items)
    }

    private var gramsUnitText: String {
        NSLocalizedString("unit.grams.short", comment: "Grams unit short title")
    }

    private var kcalUnitText: String {
        NSLocalizedString("diary.kcal", comment: "Calories unit short title")
    }

    private var libraryPickerTitle: String {
        NSLocalizedString(
            "addmeal.add_item",
            tableName: nil,
            bundle: .main,
            value: "Add to meal",
            comment: "Add to meal sheet title"
        )
    }

    private var addItemActionTitle: String {
        NSLocalizedString(
            "addmeal.add_item_short",
            tableName: nil,
            bundle: .main,
            value: NSLocalizedString("addmeal.add_item", comment: "Add to meal button title"),
            comment: "Short add to meal action title"
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                    basicsCard
                    itemsSection
                    totalsCard

                    Text("addmeal.macros.hint")
                        .font(EOTheme.Typography.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, EOTheme.Metrics.cardInset)
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
                title: Text(verbatim: resolvedCategoryTitle),
                trailing: sheetHeaderTrailing,
                onClose: { dismiss() }
            )
        }
        .alert("addmeal.save_error.title", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("common.ok", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .task(id: draft.id) {
            guard isExistingMeal else { return }
            await loadMealDetailsIfNeeded()
            if !isMergedCategoryDraft {
                await loadSharePayload()
            }
        }
        .sheet(isPresented: $isLibraryPickerPresented, onDismiss: discardPendingCatalogItems) {
            FoodCatalogLookupSheet(
                title: libraryPickerTitle,
                allowedScopes: [.products, .recipes, .mealTemplates],
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
                onSelectAndEditMealTemplate: { mealTemplate in
                    let items = await materializedItems(from: mealTemplate)
                    return await MainActor.run {
                        guard !items.isEmpty else { return nil }
                        draft.items.append(contentsOf: items)
                        return nil
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
                    let newItem = Self.makeItem(from: product)
                    draft.items.append(newItem)
                },
                onSelectRecipe: { recipe in
                    let newItem = makeItem(from: recipe)
                    draft.items.append(newItem)
                },
                onSelectMealTemplate: { mealTemplate in
                    Task {
                        let items = await materializedItems(from: mealTemplate)
                        guard !items.isEmpty else { return }
                        await MainActor.run {
                            draft.items.append(contentsOf: items)
                        }
                    }
                }
            )
            .environmentObject(catalogService)
        }
        .task {
            await applyInitialQuickAddIfNeeded()
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
        .sheet(item: $manualNutritionEditorTarget) { target in
            ManualNutritionEditorSheet(
                item: target.item,
                onCancel: {
                    manualNutritionEditorTarget = nil
                },
                onSave: { updatedItem in
                    saveManualNutritionItem(updatedItem, target: target)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    private var sheetHeaderTrailing: EOSheetHeaderTrailing {
        .confirm(isEnabled: canSave && !isSaving) {
            saveMeal()
        }
    }

    private var basicsCard: some View {
        EOCard {
            EOListRow(title: Text(verbatim: resolvedCategoryTitle))
            EORowSeparator()

            EOListRow(title: Text("addmeal.time")) {
                DatePicker(
                    "",
                    selection: $draft.scheduledAt,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .labelsHidden()
            }
        }
    }

    private var itemsSection: some View {
        EOCard {
            EOCardHeaderRow("addmeal.add_food", systemImage: "magnifyingglass") {
                isLibraryPickerPresented = true
            }

            ForEach(Array(visibleDraftItems.enumerated()), id: \.element.id) { _, item in
                EORowSeparator()

                if isManualNutritionEntry(item) {
                    manualNutritionSummaryRow(for: item)
                } else {
                    mealItemRow(for: item)
                }
            }

        }
    }

    /// Manual entry: these steppers only ever hold what the user types in.
    /// Anything picked from the library lives in the items card above; the meal
    /// total is shown by the viewer, not here.
    private var totalsCard: some View {
        EOCard {
            EOCardTitleRow("addmeal.item.manual_title")
            EORowSeparator()
            nutritionStepper(
                title: NSLocalizedString("addmeal.total.calories", comment: "Calories"),
                unit: kcalUnitText,
                value: manualNutritionBinding(\.caloriesPer100g),
                step: 10
            )
            EORowSeparator()
            nutritionStepper(title: NSLocalizedString("addmeal.total.protein", comment: "Protein"), unit: gramsUnitText, value: manualNutritionBinding(\.proteinPer100g), step: 1)
            EORowSeparator()
            nutritionStepper(title: NSLocalizedString("addmeal.total.carbs", comment: "Carbs"), unit: gramsUnitText, value: manualNutritionBinding(\.carbsPer100g), step: 1)
            EORowSeparator()
            nutritionStepper(title: NSLocalizedString("addmeal.total.fat", comment: "Fat"), unit: gramsUnitText, value: manualNutritionBinding(\.fatPer100g), step: 1)

            // Grouped so the card stays within ViewBuilder's ten-child limit.
            Group {
                EORowSeparator()

                EOInlineActionRow("addmeal.clear", tint: EOTheme.Palette.destructive) {
                    draft.items.removeAll { isManualNutritionEntry($0) }
                }
            }
        }
    }

    /// Mock-up row: "Protein, g" on the left, then the value and the `−  |  +`
    /// capsule.
    ///
    /// The value used to be baked into the title, which made it read-only — the
    /// steppers were the only way to reach a number, and 450 kcal in tens is
    /// forty-five taps. It is a field now, so it can simply be typed, and the
    /// unit has moved into the label so the four numbers line up.
    private func nutritionStepper(title: String, unit: String, value: Binding<Int>, step: Int) -> some View {
        EOStepperFieldRow(
            title: Text(verbatim: EOStepperFieldRow.title(title, unit: unit)),
            value: value,
            range: 0...100_000,
            step: step
        )
    }

    /// Reads and writes the manual item alone. It used to work off the meal's
    /// grand total and back out the difference, which meant anything added from
    /// the library showed up as a manually typed value.
    private func manualNutritionBinding(_ keyPath: WritableKeyPath<MealItemEntry, Int>) -> Binding<Int> {
        Binding(
            get: { draft.items.first(where: isManualNutritionEntry)?[keyPath: keyPath] ?? 0 },
            set: { newValue in
                let value = max(0, newValue)
                if let index = draft.items.firstIndex(where: isManualNutritionEntry) {
                    draft.items[index][keyPath: keyPath] = value
                    if !shouldPersistManualNutritionEntry(draft.items[index]) {
                        draft.items.remove(at: index)
                    }
                } else if value > 0 {
                    var manualItem = Self.makeManualItem()
                    manualItem[keyPath: keyPath] = value
                    draft.items.append(manualItem)
                }
            }
        )
    }

    private func commitSectionState() {
        PlatformSupport.dismissActiveInput()
        saveMeal(dismissAfterSave: false)
    }

    private func mealItemRow(for item: MealItemEntry) -> some View {
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
    }

    private func manualNutritionSummaryRow(for item: MealItemEntry) -> some View {
        Button {
            presentManualNutritionEditor(for: item)
        } label: {
            EOListRow(
                title: Text("addmeal.item.manual_title"),
                subtitle: Text(verbatim: itemAmountAndCompactNutritionText(item)),
                accessory: .chevron
            )
        }
        .buttonStyle(.plain)
        .eoRowContextMenu {
            EODestructiveMenuButton("common.delete", systemImage: "trash") {
                removeDraftItem(withID: item.id)
            }
        }
    }

    private func presentNewManualNutritionEditor() {
        manualNutritionEditorTarget = ManualNutritionEditorTarget(itemID: nil, item: Self.makeManualItem())
    }

    private func presentManualNutritionEditor(for item: MealItemEntry) {
        manualNutritionEditorTarget = ManualNutritionEditorTarget(itemID: item.id, item: item)
    }

    private func saveManualNutritionItem(_ item: MealItemEntry, target: ManualNutritionEditorTarget) {
        if let itemID = target.itemID {
            guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else {
                manualNutritionEditorTarget = nil
                return
            }

            if shouldPersistManualNutritionEntry(item) {
                draft.items[index] = item
            } else {
                removeDraftItem(at: index)
            }
        } else if shouldPersistManualNutritionEntry(item) {
            draft.items.append(item)
        }

        manualNutritionEditorTarget = nil
    }

    private static func makeManualItem() -> MealItemEntry {
        MealItemEntry(
            id: UUID(),
            name: localizedManualNutritionItemName,
            amount: 1,
            unit: .serving,
            note: "",
            caloriesPer100g: 0,
            proteinPer100g: 0,
            fatPer100g: 0,
            carbsPer100g: 0,
            productID: nil,
            recipeID: nil
        )
    }

    private static func makeItem(from product: ProductSummary) -> MealItemEntry {
        let baseUnit = product.baseNutritionUnit
        return MealItemEntry(
            id: UUID(),
            name: product.name,
            amount: 100,
            unit: baseUnit,
            note: "",
            servingLabel: "",
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

    private func allowedUnits(for item: MealItemEntry) -> [MealItemUnit] {
        if item.recipeID != nil {
            return [.serving, .grams]
        }
        if let product = productSummary(for: item) {
            return [product.servingUnit]
        }
        return MealItemUnit.allCases
    }

    private func amountStep(for unit: MealItemUnit) -> Double {
        switch unit {
        case .serving:
            return 1
        case .grams, .milliliters:
            return 10
        }
    }

    private func adjustAmount(for index: Int, delta: Double) {
        guard draft.items.indices.contains(index) else { return }
        let next = draft.items[index].amount + delta
        draft.items[index].amount = max(minimumAmount(for: draft.items[index].unit), next)
    }

    private func removeDraftItem(at index: Int) {
        guard draft.items.indices.contains(index) else { return }
        let removalIndex = draft.items.index(draft.items.startIndex, offsetBy: index)
        let removedItemID = draft.items[removalIndex].id
        draft.items.remove(at: removalIndex)
        if quantityEditorTarget?.itemID == removedItemID {
            quantityEditorTarget = nil
        }
    }

    private func removeDraftItem(withID itemID: UUID) {
        guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else { return }
        removeDraftItem(at: index)
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

    private func amountTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.items.indices.contains(index) else { return "" }
                return amountText(for: draft.items[index].amount)
            },
            set: { newValue in
                guard draft.items.indices.contains(index) else { return }
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                draft.items[index].amount = max(
                    minimumAmount(for: draft.items[index].unit),
                    Double(normalized) ?? minimumAmount(for: draft.items[index].unit)
                )
            }
        )
    }

    private func minimumAmount(for unit: MealItemUnit) -> Double {
        switch unit {
        case .serving, .grams, .milliliters:
            return 1
        }
    }

    private func amountText(for value: Double) -> String {
        let normalized = (value * 10).rounded() / 10
        if normalized == normalized.rounded() {
            return String(Int(normalized))
        }
        return String(normalized)
    }

    private static func defaultScheduledAt(preferredDate: Date?) -> Date {
        let now = Date()
        guard let preferredDate else { return now }

        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: preferredDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: now)
        var mergedComponents = DateComponents()
        mergedComponents.year = dayComponents.year
        mergedComponents.month = dayComponents.month
        mergedComponents.day = dayComponents.day
        mergedComponents.hour = timeComponents.hour
        mergedComponents.minute = timeComponents.minute
        return calendar.date(from: mergedComponents) ?? now
    }

    private func displayTitle(for item: MealItemEntry) -> String {
        if isManualNutritionEntry(item) {
            return NSLocalizedString("addmeal.item.manual_title", comment: "Manual nutrition item title")
        }
        return item.name.isEmpty
            ? NSLocalizedString("addmeal.item.product_fallback", comment: "Meal item fallback title")
            : item.name
    }

    private func productSummary(for item: MealItemEntry) -> ProductSummary? {
        catalogService.productSummary(for: item)
    }

    private func isManualNutritionEntry(_ item: MealItemEntry) -> Bool {
        !item.isLinkedToCatalogItem && Self.isManualNutritionName(item.name)
    }

    private func itemSourceDescription(for item: MealItemEntry) -> String {
        if isManualNutritionEntry(item) {
            return NSLocalizedString("addmeal.item.source.manual_nutrition_only", comment: "Manual nutrition source description")
        }
        if item.productID != nil {
            return NSLocalizedString("addmeal.item.source.catalog_product", comment: "Catalog product source description")
        }
        if item.recipeID != nil {
            return NSLocalizedString("addmeal.item.source.catalog_recipe", comment: "Catalog recipe source description")
        }
        return NSLocalizedString("addmeal.item.source.manual", comment: "Manual source description")
    }

    private func itemCompactNutritionText(_ item: MealItemEntry) -> String {
        let caloriesUnit = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        let proteinShort = NSLocalizedString("recipe.detail.protein_short", comment: "Protein short title")
        let fatShort = NSLocalizedString("recipe.detail.fat_short", comment: "Fat short title")
        let carbsShort = NSLocalizedString("recipe.detail.carbs_short", comment: "Carbs short title")
        return "\(item.calories) \(caloriesUnit) · \(proteinShort) \(item.protein) · \(fatShort) \(item.fat) · \(carbsShort) \(item.carbs)"
    }

    private func itemAmountAndCompactNutritionText(_ item: MealItemEntry) -> String {
        "\(displayFoodQuantityText(amount: item.amount, unit: item.unit, servingLabel: item.servingLabel, product: productSummary(for: item))) · \(itemCompactNutritionText(item))"
    }

    private func saveMeal(dismissAfterSave: Bool = true) {
        guard canSave else { return }

        if canDeleteExistingMeal {
            let mealIDsToDelete = mealIDsForDeleting(draft)
            isSaving = true

            Task {
                let didDelete = await deleteMeals(withIDs: mealIDsToDelete)
                await MainActor.run {
                    isSaving = false
                    if didDelete {
                        baselineDraft = draft
                        if dismissAfterSave {
                            dismiss()
                        } else {
                            PlatformFeedback.performSoftImpact()
                        }
                    } else {
                        saveErrorMessage = diaryService.lastErrorMessage ?? NSLocalizedString("addmeal.delete_error", comment: "Delete meal fallback error")
                    }
                }
            }
            return
        }

        let mealToSave = normalizedDraft
        isSaving = true

        Task {
            let didSave = await diaryService.saveMeal(mealToSave)
            let didRemoveMergedSources = await removeMergedSourceMealsIfNeeded(afterSaving: mealToSave, didSave: didSave)

            if didSave {
                // The whole day is restated rather than the difference added.
                // Sending only the increase meant an edit that lowered a meal
                // never reached Health, and a meal moved to another day was
                // counted on both.
                // The day the meal is on now. The day it came from, if it moved,
                // is the store's business — `detachMeal` mirrors that one.
                await diaryService.syncNutritionToHealthIfEnabled(for: mealToSave.scheduledAt)
            }

            await MainActor.run {
                isSaving = false
                if didSave && didRemoveMergedSources {
                    baselineDraft = mealToSave
                    draft = mealToSave
                    if dismissAfterSave {
                        dismiss()
                    } else {
                        PlatformFeedback.performSoftImpact()
                    }
                } else {
                    saveErrorMessage = diaryService.lastErrorMessage ?? NSLocalizedString("addmeal.save_error.generic", comment: "Save meal generic error fallback")
                }
            }
        }
    }

    private func loadMealDetailsIfNeeded() async {
        let currentDraft = draft
        guard shouldLoadDetailedMeal(for: currentDraft) else { return }

        let sourceMealIDs = mergedSourceMealIDs.isEmpty ? [currentDraft.id] : mergedSourceMealIDs
        var detailedMeals: [MealEntry] = []

        for sourceMealID in sourceMealIDs {
            let fallback = sourceMealID == currentDraft.id
                ? currentDraft
                : diaryService.mealForNavigation(id: sourceMealID)
            if let detailedMeal = await diaryService.loadMealDetails(id: sourceMealID, fallback: fallback) {
                detailedMeals.append(detailedMeal)
            }
        }

        let detailedMeal = isMergedCategoryDraft
            ? mergedMeal(from: detailedMeals, fallback: currentDraft)
            : (detailedMeals.first ?? currentDraft)

        await MainActor.run {
            guard draft == currentDraft else { return }
            draft = detailedMeal
            baselineDraft = detailedMeal
        }
    }

    private func removeMergedSourceMealsIfNeeded(afterSaving meal: MealEntry, didSave: Bool) async -> Bool {
        guard didSave else { return false }
        let mealIDsToRemove = uniqueMealIDs(mergedSourceMealIDs.filter { $0 != meal.id })
        guard !mealIDsToRemove.isEmpty else { return true }

        return await deleteMeals(withIDs: mealIDsToRemove)
    }

    private func mealIDsForDeleting(_ meal: MealEntry) -> [UUID] {
        let sourceMealIDs = mergedSourceMealIDs.isEmpty ? [meal.id] : mergedSourceMealIDs
        return uniqueMealIDs(sourceMealIDs)
    }

    private func deleteMeals(withIDs mealIDs: [UUID]) async -> Bool {
        for mealID in mealIDs {
            guard await diaryService.deleteMeal(id: mealID) else { return false }
        }
        return true
    }

    private func uniqueMealIDs(_ mealIDs: [UUID]) -> [UUID] {
        var seenMealIDs: Set<UUID> = []
        return mealIDs.filter { seenMealIDs.insert($0).inserted }
    }

    private func mergedMeal(from meals: [MealEntry], fallback: MealEntry) -> MealEntry {
        guard !meals.isEmpty else { return fallback }

        let sortedMeals = meals.sorted { lhs, rhs in
            if lhs.scheduledAt != rhs.scheduledAt {
                return lhs.scheduledAt < rhs.scheduledAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var mergedMeal = fallback
        mergedMeal.items = sortedMeals.flatMap(\.items)

        let mergedNote = sortedMeals
            .map { $0.note.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if !mergedNote.isEmpty {
            mergedMeal.note = mergedNote
        }

        mergedMeal.nutrition = NutritionSummary(
            calories: sortedMeals.reduce(0) { $0 + $1.calories },
            protein: sortedMeals.reduce(0) { $0 + $1.protein },
            fat: sortedMeals.reduce(0) { $0 + $1.fat },
            carbs: sortedMeals.reduce(0) { $0 + $1.carbs }
        )
        return mergedMeal
    }

    private func shouldLoadDetailedMeal(for meal: MealEntry) -> Bool {
        meal.items.isEmpty || meal.items.allSatisfy(isManualNutritionEntry)
    }

    private func normalizedMealForSaving(_ meal: MealEntry) -> MealEntry {
        var normalizedMeal = meal
        let category = diaryService.category(for: meal.mealCategoryID)
        normalizedMeal.items = normalizedItemsForSaving(meal.items)
        normalizedMeal.title = category.displayTitle
        normalizedMeal.kind = MealKind.inferred(from: meal.scheduledAt)
        normalizedMeal.mealCategoryID = category.id
        normalizedMeal.nutrition = nutritionSummary(for: normalizedMeal.items)
        return normalizedMeal
    }

    private func normalizedItemsForSaving(_ items: [MealItemEntry]) -> [MealItemEntry] {
        items.filter { item in
            if isManualNutritionEntry(item) {
                return shouldPersistManualNutritionEntry(item)
            }
            return true
        }
    }

    private func shouldPersistManualNutritionEntry(_ item: MealItemEntry) -> Bool {
        item.caloriesPer100g > 0
            || item.proteinPer100g > 0
            || item.fatPer100g > 0
            || item.carbsPer100g > 0
    }

    private func nutritionSummary(for items: [MealItemEntry]) -> NutritionSummary {
        NutritionSummary(
            calories: items.reduce(0) { $0 + $1.calories },
            protein: items.reduce(0) { $0 + $1.protein },
            fat: items.reduce(0) { $0 + $1.fat },
            carbs: items.reduce(0) { $0 + $1.carbs }
        )
    }

    private func loadSharePayload() async {
        guard sharePayload == nil else { return }
        guard let payload = await diaryService.shareMeal(id: draft.id) else { return }
        sharePayload = payload
    }

    @MainActor
    private func shareSheetItem(for payload: FoodSharePayload) -> SystemShareSheetItem? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? payload.title
            : draft.title
        let message = String(
            format: NSLocalizedString("meal.share.share_message", comment: "Meal share message"),
            title
        )
        let nutrition = String(
            format: NSLocalizedString(
                "meal.import.nutrition",
                tableName: nil,
                bundle: .main,
                value: "%d kcal • P %d • F %d • C %d",
                comment: "Meal import nutrition summary"
            ),
            draft.calories,
            draft.protein,
            draft.fat,
            draft.carbs
        )
        // Localized caption that accompanies the link. The link is delivered as a
        // dedicated item so the system share sheet uses local metadata and does
        // not generate the goeatometer card; the payload works in every app.
        let caption = [message, nutrition]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard let url = payload.resolvedShareURL else { return nil }
        return SystemShareSheetItem(
            message: caption,
            url: url,
            card: .make(
                title: title,
                kindKey: "share.card.kind.meal",
                items: normalizedDraft.items,
                nutrition: normalizedDraft.nutrition
            )
        )
    }

    @MainActor
    private func presentShareSheet() {
        if let resolvedShareSheetItem {
            pendingShareSheetItem = resolvedShareSheetItem
            return
        }
        guard !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            await loadSharePayload()
            isPreparingShare = false
            if let resolvedShareSheetItem {
                pendingShareSheetItem = resolvedShareSheetItem
            }
        }
    }

    @MainActor
    private func applyInitialQuickAddIfNeeded() async {
        guard !hasAppliedInitialQuickAdd, let initialQuickAdd else { return }
        hasAppliedInitialQuickAdd = true

        switch initialQuickAdd.kind {
        case .product:
            let localProduct = catalogService.productSummary(id: initialQuickAdd.id)
            let product: ProductSummary?
            if let localProduct {
                product = localProduct
            } else {
                product = await catalogService.fetchProduct(id: initialQuickAdd.id)
            }
            guard let product else { return }
            draft.items.append(Self.makeItem(from: product))

        case .recipe:
            let localRecipe = catalogService.recipeSummary(id: initialQuickAdd.id)
            let recipe: RecipeSummary?
            if let localRecipe {
                recipe = localRecipe
            } else {
                recipe = await catalogService.fetchRecipe(id: initialQuickAdd.id)
            }
            guard let recipe else { return }
            draft.items.append(makeItem(from: recipe))

        case .mealTemplate:
            guard let mealTemplate = catalogService.mealTemplateSummary(id: initialQuickAdd.id) else { return }
            let items = await materializedItems(from: mealTemplate)
            guard !items.isEmpty else { return }
            draft.items.append(contentsOf: items)
        }
    }

    private func nutrientValueText(_ value: Int) -> String {
        "\(value)"
    }

    private func mealNutritionRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
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

    private func materializedItems(from mealTemplate: MealTemplateSummary) async -> [MealItemEntry] {
        var items: [MealItemEntry] = []
        items.reserveCapacity(mealTemplate.items.count)

        for item in mealTemplate.items {
            items.append(await materializedItem(from: item))
        }

        return items
    }

    private func materializedItem(from item: MealItemEntry) async -> MealItemEntry {
        if let productID = item.productID {
            let product: ProductSummary?
            if let cachedProduct = catalogService.productSummary(for: item) {
                product = cachedProduct
            } else {
                product = await catalogService.fetchProductSnapshot(id: productID)
            }

            if let product {
                let normalizedServingLabel = item.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if let servingOption = product.selectableServingOption(matching: normalizedServingLabel),
                   servingOption.unit == .serving {
                    let servingQuantity: Double
                    if item.unit == .serving {
                        servingQuantity = max(item.amount, 1)
                    } else if item.unit == servingOption.effectiveMetricUnit,
                              servingOption.effectiveMetricAmount > 0 {
                        servingQuantity = item.amount / servingOption.effectiveMetricAmount
                    } else {
                        servingQuantity = max(item.amount, 1)
                    }

                    let caloriesPerServing = Int((Double(product.caloriesPer100g) * servingOption.effectiveMetricAmount / 100.0).rounded())
                    let proteinPerServing = Int((Double(product.proteinPer100g) * servingOption.effectiveMetricAmount / 100.0).rounded())
                    let fatPerServing = Int((Double(product.fatPer100g) * servingOption.effectiveMetricAmount / 100.0).rounded())
                    let carbsPerServing = Int((Double(product.carbsPer100g) * servingOption.effectiveMetricAmount / 100.0).rounded())

                    return MealItemEntry(
                        id: UUID(),
                        name: product.name,
                        amount: servingQuantity,
                        unit: .serving,
                        note: "",
                        servingLabel: servingOption.selectionLabel,
                        caloriesPer100g: caloriesPerServing,
                        proteinPer100g: proteinPerServing,
                        fatPer100g: fatPerServing,
                        carbsPer100g: carbsPerServing,
                        productID: productID,
                        recipeID: nil,
                        productSnapshot: product,
                        recipeSnapshot: nil
                    )
                }

                return MealItemEntry(
                    id: UUID(),
                    name: product.name,
                    amount: item.amount,
                    unit: item.unit,
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
        }

        if let recipeID = item.recipeID {
            let recipe: RecipeSummary?
            if let cachedRecipe = catalogService.recipeSummary(for: item) {
                recipe = cachedRecipe
            } else {
                recipe = await catalogService.fetchRecipeSnapshot(id: recipeID)
            }

            if let recipe {
                return catalogService.makeMealItem(
                    from: recipe,
                    id: UUID(),
                    amount: item.amount,
                    unit: item.unit,
                    note: "",
                    servingLabel: item.servingLabel
                )
            }
        }

        return MealItemEntry(
            id: UUID(),
            name: item.name,
            amount: item.amount,
            unit: item.unit,
            note: item.note,
            servingLabel: item.servingLabel,
            caloriesPer100g: item.caloriesPer100g,
            proteinPer100g: item.proteinPer100g,
            fatPer100g: item.fatPer100g,
            carbsPer100g: item.carbsPer100g,
            productID: item.productID,
            recipeID: item.recipeID,
            productSnapshot: item.productSnapshot,
            recipeSnapshot: item.recipeSnapshot
        )
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

}

struct ManualNutritionEditorSheet: View {
    private let originalItem: MealItemEntry
    let onCancel: () -> Void
    let onSave: (MealItemEntry) -> Void

    @State private var item: MealItemEntry
    @FocusState private var isManualNutritionFieldFocused: Bool

    init(item: MealItemEntry, onCancel: @escaping () -> Void, onSave: @escaping (MealItemEntry) -> Void) {
        self.originalItem = item
        self.onCancel = onCancel
        self.onSave = onSave
        self._item = State(initialValue: item)
    }

    private var gramsUnitText: String {
        NSLocalizedString("unit.grams.short", comment: "Grams unit short title")
    }

    private var hasChanges: Bool {
        item != originalItem
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    manualNutritionEditorCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appPageBackground.ignoresSafeArea())
            .navigationTitle(Text("addmeal.add_manual"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    PressableIconButton(tintColor: .primary, action: onCancel) {
                        Label("common.close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(item)
                    } label: {
                        Label("common.save", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .tint(.accentColor)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .clipShape(Circle())
                    .disabled(!hasChanges)
                    .opacity(hasChanges ? 1 : 0.45)
                }

            }
        }
    }

    private var manualNutritionEditorCard: some View {
        VStack(spacing: 18) {
            manualNutritionRow(
                title: NSLocalizedString("addmeal.total.calories", comment: "Calories field title"),
                unit: NSLocalizedString("diary.kcal", comment: "Calories suffix"),
                tint: .orange,
                keyPath: \.caloriesPer100g,
                step: 10
            )
            Divider()
            manualNutritionRow(
                title: NSLocalizedString("addmeal.total.protein", comment: "Protein field title"),
                unit: gramsUnitText,
                tint: .green,
                keyPath: \.proteinPer100g,
                step: 1
            )
            Divider()
            manualNutritionRow(
                title: NSLocalizedString("addmeal.total.fat", comment: "Fat field title"),
                unit: gramsUnitText,
                tint: .orange,
                keyPath: \.fatPer100g,
                step: 1
            )
            Divider()
            manualNutritionRow(
                title: NSLocalizedString("addmeal.total.carbs", comment: "Carbs field title"),
                unit: gramsUnitText,
                tint: .blue,
                keyPath: \.carbsPer100g,
                step: 1
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private func manualNutritionRow(
        title: String,
        unit: String,
        tint: Color,
        keyPath: WritableKeyPath<MealItemEntry, Int>,
        step: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                manualNutritionAdjustButton(
                    systemImage: "minus",
                    labelKey: "recipe.editor.decrease",
                    disabled: item[keyPath: keyPath] <= 0,
                    action: { adjustManualNutrition(keyPath: keyPath, delta: -step) }
                )

                ZStack {
                    TextField(
                        text: manualNutritionTextBinding(keyPath: keyPath),
                        prompt: Text("common.zero_placeholder").foregroundStyle(.secondary)
                    ) {
                        Text(title)
                    }
                    .keyboardType(.numberPad)
                    .focused($isManualNutritionFieldFocused)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .frame(maxWidth: .infinity)

                    HStack {
                        Spacer(minLength: 0)
                        Text(unit)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                        .fill(tint.opacity(0.08))
                )

                manualNutritionAdjustButton(
                    systemImage: "plus",
                    labelKey: "recipe.editor.increase",
                    disabled: false,
                    action: { adjustManualNutrition(keyPath: keyPath, delta: step) }
                )
            }
        }
    }

    private func manualNutritionAdjustButton(
        systemImage: String,
        labelKey: LocalizedStringKey,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        PressableIconButton(disabled: disabled, action: action) {
            Label(labelKey, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 52, height: 52)
                .opacity(disabled ? 0.45 : 1)
        }
    }

    private func adjustManualNutrition(keyPath: WritableKeyPath<MealItemEntry, Int>, delta: Int) {
        item[keyPath: keyPath] = max(0, item[keyPath: keyPath] + delta)
    }

    private func manualNutritionTextBinding(keyPath: WritableKeyPath<MealItemEntry, Int>) -> Binding<String> {
        Binding(
            get: {
                let value = item[keyPath: keyPath]
                return value == 0 ? "" : String(value)
            },
            set: { newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                item[keyPath: keyPath] = Int(digitsOnly) ?? 0
            }
        )
    }
}

struct MealItemQuantityEditorSheet: View {
    @Binding var item: MealItemEntry

    let catalogService: FoodCatalogService
    let onDelete: (() -> Void)?
    let onCancel: (() -> Void)?
    let onConfirm: (() -> Void)?
    let onClose: () -> Void
    @FocusState private var isAmountFieldFocused: Bool
    @State private var amountDraftText: String = ""

    init(
        item: Binding<MealItemEntry>,
        catalogService: FoodCatalogService,
        onDelete: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onConfirm: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self._item = item
        self.catalogService = catalogService
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.onClose = onClose
    }

    private var linkedProduct: ProductSummary? {
        catalogService.productSummary(for: item)
    }

    private var linkedRecipe: RecipeSummary? {
        catalogService.recipeSummary(for: item)
    }

    private var selectedServingOption: ProductServingOption? {
        guard let linkedProduct else { return nil }
        let trimmedLabel = item.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return linkedProduct.selectableServingOption(matching: trimmedLabel)
        }
        return nil
    }

    private var productMetricUnits: [MealItemUnit] {
        guard let linkedProduct else { return [] }
        return [linkedProduct.baseNutritionUnit]
    }

    private var allowedUnits: [MealItemUnit] {
        if linkedRecipe != nil {
            return [.serving, .grams]
        }
        if let product = linkedProduct {
            return [product.servingUnit]
        }
        return MealItemUnit.allCases
    }

    private var unitPickerTag: String {
        if linkedProduct != nil {
            if let option = selectedServingOption {
                return "serving_\(option.id)"
            }
            return "metric_\(item.unit.rawValue)"
        }
        return "unit_\(item.unit.rawValue)"
    }

    private var unitPickerBinding: Binding<String> {
        Binding(
            get: { unitPickerTag },
            set: { tag in
                if tag.hasPrefix("serving_") {
                    let optionID = String(tag.dropFirst("serving_".count))
                    if let product = linkedProduct,
                       let option = product.selectableServingOptions.first(where: { $0.id == optionID }) {
                        applyUnitSelectionWithoutAnimation {
                            selectServingOption(option)
                        }
                    }
                } else if tag.hasPrefix("metric_") {
                    let rawValue = String(tag.dropFirst("metric_".count))
                    if let unit = MealItemUnit(rawValue: rawValue) {
                        applyUnitSelectionWithoutAnimation {
                            selectDirectMetricUnit(unit)
                        }
                    }
                } else if tag.hasPrefix("unit_") {
                    let rawValue = String(tag.dropFirst("unit_".count))
                    if let unit = MealItemUnit(rawValue: rawValue) {
                        applyUnitSelectionWithoutAnimation {
                            selectUnit(unit)
                        }
                    }
                }
            }
        )
    }

    private func applyUnitSelectionWithoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            change()
        }
    }

    @ViewBuilder
    private var unitPickerOptions: some View {
        if let linkedProduct {
            ForEach(linkedProduct.selectableServingOptions) { option in
                Text(option.pickerTitle).tag("serving_\(option.id)")
            }

            ForEach(productMetricUnits) { unit in
                Text(unit.title).tag("metric_\(unit.rawValue)")
            }
        } else {
            ForEach(allowedUnits) { unit in
                Text(unit.title).tag("unit_\(unit.rawValue)")
            }
        }
    }

    /// Human-readable label of the unit currently selected in the menu.
    private var selectedUnitTitle: String {
        if let option = selectedServingOption {
            return option.pickerTitle
        }
        return item.unit.title
    }

    private var canDecrease: Bool {
        if linkedProduct != nil {
            return displayAmount > minimumDisplayAmount
        }
        return item.amount > minimumAmount(for: item.unit)
    }

    private var doneTitle: String {
        NSLocalizedString("common.done", tableName: nil, bundle: .main, value: "Done", comment: "Done button title")
    }

    private var presentationHeight: CGFloat {
        onDelete == nil ? 390 : 450
    }

    private var displayAmount: Double {
        displayFoodQuantityValue(amount: item.amount, unit: item.unit, servingLabel: item.servingLabel, product: linkedProduct)
    }

    private var minimumDisplayAmount: Double {
        selectedServingOption == nil ? 0.01 : 1
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                EOCard {
                    EOListRow(title: Text(verbatim: displayTitle))
                    EORowSeparator()

                    EOListRow(title: Text("addmeal.unit")) {
                        Menu {
                            Picker("", selection: unitPickerBinding) {
                                unitPickerOptions
                            }
                            .labelsHidden()
                        } label: {
                            HStack(spacing: 6) {
                                Text(verbatim: selectedUnitTitle)
                                    .font(EOTheme.Typography.rowValue)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize()
                    }
                    EORowSeparator()

                    EOListRow(title: Text("addmeal.amount")) {
                        HStack(spacing: 10) {
                            TextField(
                                "",
                                text: $amountDraftText,
                                prompt: Text("addmeal.amount.placeholder").foregroundStyle(.secondary)
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isAmountFieldFocused)
                            .frame(maxWidth: 96, alignment: .trailing)
                            .font(EOTheme.Typography.rowValue.monospacedDigit())
                            .onChange(of: amountDraftText) { _, newValue in
                                amountDraftText = sanitizedDecimalText(newValue)
                            }

                            EOStepperControl(
                                canDecrement: canDecrease,
                                canIncrement: true,
                                onDecrement: { adjustAmount(by: -amountStep(for: item.unit)) },
                                onIncrement: { adjustAmount(by: amountStep(for: item.unit)) }
                            )
                        }
                    }
                }

                if onDelete != nil {
                    EOCard {
                        EOInlineActionRow("common.delete", tint: EOTheme.Palette.destructive) {
                            dismissKeyboard()
                            onDelete?()
                            onClose()
                        }
                    }
                }

                Text(itemAmountAndCompactNutritionText(item))
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)

                Spacer(minLength: 0)
            }
            .eoCardInsets()
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .eoPageBackground()
            .eoSheetChrome(
                "addmeal.set_portion",
                trailing: .confirm(isEnabled: true) {
                    dismissKeyboard()
                    if let onConfirm {
                        onConfirm()
                    } else {
                        onClose()
                    }
                },
                onClose: {
                    dismissKeyboard()
                    if let onCancel {
                        onCancel()
                    } else {
                        onClose()
                    }
                }
            )
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            normalizeDefaultMetricUnitIfNeeded()
            syncAmountDraftText()
        }
        .onChange(of: displayAmount) { _, _ in
            guard !isAmountFieldFocused else { return }
            syncAmountDraftText()
        }
        .onChange(of: isAmountFieldFocused) { _, isFocused in
            if isFocused {
                syncAmountDraftText()
            } else {
                commitAmountDraftText()
            }
        }
    }

    private var displayTitle: String {
        let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return NSLocalizedString("addmeal.item.product_fallback", comment: "Meal item fallback title")
        }
        return trimmedName
    }

    private var sourceDescription: String {
        if item.productID != nil {
            return NSLocalizedString("addmeal.item.source.catalog_product", comment: "Catalog product source description")
        }
        if item.recipeID != nil {
            return NSLocalizedString("addmeal.item.source.catalog_recipe", comment: "Catalog recipe source description")
        }
        return NSLocalizedString("addmeal.item.source.manual", comment: "Manual source description")
    }

    private func adjustAmount(by delta: Double) {
        if let selectedServingOption {
            let nextAmount = max(minimumDisplayAmount, displayAmount + delta)
            item.amount = nextAmount * selectedServingOption.effectiveMetricAmount
            item.unit = selectedServingOption.effectiveMetricUnit
            item.servingLabel = selectedServingOption.selectionLabel
            syncAmountDraftText()
            return
        }

        let nextAmount = item.amount + delta
        item.amount = max(minimumAmount(for: item.unit), nextAmount)
        syncAmountDraftText()
    }

    private func amountStep(for unit: MealItemUnit) -> Double {
        if selectedServingOption != nil {
            return 1
        }
        switch unit {
        case .serving:
            return 1
        case .grams, .milliliters:
            return 10
        }
    }

    private func minimumAmount(for unit: MealItemUnit) -> Double {
        switch unit {
        case .serving, .grams, .milliliters:
            return 1
        }
    }

    private func amountText(for value: Double) -> String {
        formattedFoodAmountValue(value, maximumFractionDigits: value.magnitude < 1 ? 2 : 1)
    }

    private func dismissKeyboard() {
        isAmountFieldFocused = false
    }

    private func itemCompactNutritionText(_ item: MealItemEntry) -> String {
        let caloriesUnit = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        let proteinShort = NSLocalizedString("recipe.detail.protein_short", comment: "Protein short title")
        let fatShort = NSLocalizedString("recipe.detail.fat_short", comment: "Fat short title")
        let carbsShort = NSLocalizedString("recipe.detail.carbs_short", comment: "Carbs short title")
        return "\(item.calories) \(caloriesUnit) · \(proteinShort) \(item.protein) · \(fatShort) \(item.fat) · \(carbsShort) \(item.carbs)"
    }

    private func itemAmountAndCompactNutritionText(_ item: MealItemEntry) -> String {
        "\(displayFoodQuantityText(amount: item.amount, unit: item.unit, servingLabel: item.servingLabel, product: linkedProduct)) · \(itemCompactNutritionText(item))"
    }

    private func applyAmount(_ nextDisplayAmount: Double) {
        let resolvedAmount = max(minimumDisplayAmount, nextDisplayAmount)
        if let selectedServingOption {
            item.amount = resolvedAmount * selectedServingOption.effectiveMetricAmount
            item.unit = selectedServingOption.effectiveMetricUnit
            item.servingLabel = selectedServingOption.selectionLabel
            syncAmountDraftText()
            return
        }

        item.amount = max(minimumAmount(for: item.unit), resolvedAmount)
        syncAmountDraftText()
    }

    private func selectUnit(_ unit: MealItemUnit) {
        let previousUnit = item.unit
        let previousAmount = item.amount

        if let linkedRecipe {
            selectRecipeUnit(unit, recipe: linkedRecipe)
            return
        }

        item.unit = unit
        item.servingLabel = ""

        if previousUnit == unit {
            item.amount = max(minimumAmount(for: unit), previousAmount)
            syncAmountDraftText()
            return
        }

        if unit == .serving {
            item.amount = 1
            syncAmountDraftText()
            return
        }

        if previousUnit == .serving && unit != .serving {
            item.amount = defaultAmount(for: unit)
            syncAmountDraftText()
            return
        }

        item.amount = max(minimumAmount(for: unit), previousAmount)
        syncAmountDraftText()
    }

    private func selectRecipeUnit(_ unit: MealItemUnit, recipe: RecipeSummary) {
        guard item.unit != unit else { return }

        let currentAmount = item.amount
        let portionWeight = recipePortionWeight(for: recipe)

        switch (item.unit, unit) {
        case (.serving, .grams):
            item.amount = max(minimumAmount(for: unit), currentAmount * portionWeight)
        case (.grams, .serving):
            item.amount = 1
        default:
            item.amount = unit == .serving ? 1 : max(minimumAmount(for: unit), currentAmount)
        }

        item.unit = unit
        item.servingLabel = ""
        applyRecipeNutrition(recipe, unit: unit)
        syncAmountDraftText()
    }

    private func recipePortionWeight(for recipe: RecipeSummary) -> Double {
        let portionWeight = catalogService.portionWeight(for: recipe)
        return portionWeight > 0 ? portionWeight : 100
    }

    private func applyRecipeNutrition(_ recipe: RecipeSummary, unit: MealItemUnit) {
        let nutrition = catalogService.nutritionSummary(for: recipe, unit: unit)
        item.caloriesPer100g = nutrition.calories
        item.proteinPer100g = nutrition.protein
        item.fatPer100g = nutrition.fat
        item.carbsPer100g = nutrition.carbs
    }

    private func selectDirectMetricUnit(_ unit: MealItemUnit) {
        let previousServingOption = selectedServingOption
        let previousUnit = item.unit
        let previousAmount = item.amount

        item.unit = unit
        item.servingLabel = ""

        if previousServingOption != nil {
            item.amount = max(minimumAmount(for: unit), previousAmount)
            syncAmountDraftText()
            return
        }

        if previousUnit == unit {
            item.amount = max(minimumAmount(for: unit), previousAmount)
            syncAmountDraftText()
            return
        }

        if previousUnit != .serving {
            item.amount = max(minimumAmount(for: unit), previousAmount)
            syncAmountDraftText()
            return
        }

        item.amount = defaultAmount(for: unit)
        syncAmountDraftText()
    }

    private func selectServingOption(_ option: ProductServingOption) {
        item.unit = option.effectiveMetricUnit
        item.amount = option.effectiveMetricAmount
        item.servingLabel = option.selectionLabel
        syncAmountDraftText()
    }

    private func defaultAmount(for unit: MealItemUnit) -> Double {
        switch unit {
        case .serving:
            return 1
        case .grams, .milliliters:
            return 100
        }
    }

    private func normalizeDefaultMetricUnitIfNeeded() {
        guard let linkedProduct else { return }
        let trimmedLabel = item.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackUnit = linkedProduct.baseNutritionUnit

        if trimmedLabel.isEmpty {
            guard item.unit != fallbackUnit || item.unit == .serving else { return }
            item.unit = fallbackUnit
            item.servingLabel = ""
            item.amount = max(minimumAmount(for: fallbackUnit), item.amount > 0 ? item.amount : defaultAmount(for: fallbackUnit))
            syncAmountDraftText()
            return
        }

        guard item.unit == .serving else { return }
        item.unit = fallbackUnit
        item.amount = max(minimumAmount(for: fallbackUnit), defaultAmount(for: fallbackUnit))
        syncAmountDraftText()
    }

    private func syncAmountDraftText() {
        amountDraftText = amountText(for: displayAmount)
    }

    private func commitAmountDraftText() {
        let parsedAmount = resolvedDoubleValue(from: amountDraftText)
        applyAmount(parsedAmount > 0 ? parsedAmount : minimumDisplayAmount)
    }

    private func sanitizedDecimalText(_ text: String) -> String {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let alternateSeparator = decimalSeparator == "," ? "." : ","

        var result = ""
        var hasSeparator = false
        for character in text {
            if character.isNumber {
                result.append(character)
                continue
            }

            let scalar = String(character)
            if scalar == decimalSeparator || scalar == alternateSeparator {
                guard !hasSeparator else { continue }
                hasSeparator = true
                result.append(decimalSeparator)
            }
        }

        return result
    }

    private func resolvedDoubleValue(from text: String) -> Double {
        let sanitized = sanitizedDecimalText(text)
        guard !sanitized.isEmpty else { return 0 }

        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: sanitized) {
            return number.doubleValue
        }

        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let normalized = sanitized.replacingOccurrences(of: decimalSeparator, with: ".")
        if normalized.hasPrefix(".") {
            return Double("0\(normalized)") ?? 0
        }
        return Double(normalized) ?? 0
    }
}
