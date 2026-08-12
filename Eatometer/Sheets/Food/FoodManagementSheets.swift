import SwiftUI
import Combine
import Vision
import UIKit

struct FoodCatalogTrayItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let summary: String
}

private func formatFoodAmount(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = value.magnitude < 1 ? 2 : 1
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

struct FoodCatalogLookupSheet: View {
    enum CustomEditorPresentationMode {
        case sheet
        case push
    }

    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let allowedScopes: [SearchScope]
    let onSelectAndEditProduct: ((ProductSummary) async -> UUID?)?
    let onSelectAndEditRecipe: ((RecipeSummary) async -> UUID?)?
    let onSelectAndEditMealTemplate: ((MealTemplateSummary) async -> UUID?)?
    let addedItems: [MealItemEntry]
    let trayItems: [FoodCatalogTrayItem]
    let externalEditorTargetID: Binding<UUID?>?
    let itemBindingProvider: ((UUID) -> Binding<MealItemEntry>?)?
    let customEditorSheetProvider: ((UUID, @escaping () -> Void) -> AnyView?)?
    let customEditorPresentationMode: CustomEditorPresentationMode
    let onRemoveAddedItem: ((UUID) -> Void)?
    let onSelectProduct: (ProductSummary) -> Void
    let onSelectRecipe: (RecipeSummary) -> Void
    let onSelectMealTemplate: (MealTemplateSummary) -> Void

    @State private var query = ""
    @State private var scope: LookupScope
    @State private var scannedBarcode: String = ""
    @StateObject private var searchService = FoodSearchService(authService: FoodAuthService.shared)
    @ObservedObject private var frequentStore = FrequentProductsStore.shared
    @State private var remoteProducts: [ProductSummary] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var previewDestination: FoodCatalogPreviewDestination?
    @State private var isBarcodeScannerPresented = false
    @State private var quantityEditorTarget: AddedItemEditorTarget?
    @State private var pushedCustomEditorTarget: AddedItemEditorTarget?

    private enum FoodCatalogPreviewDestination: Identifiable, Hashable {
        case product(ProductSummary)
        case recipe(RecipeSummary)
        case mealTemplate(MealTemplateSummary)

        var id: String {
            switch self {
            case .product(let product):
                return "product-\(product.id.uuidString)"
            case .recipe(let recipe):
                return "recipe-\(recipe.id.uuidString)"
            case .mealTemplate(let mealTemplate):
                return "meal-template-\(mealTemplate.id.uuidString)"
            }
        }
    }

    private struct AddedItemEditorTarget: Identifiable, Hashable {
        let itemID: UUID
        var id: UUID { itemID }
    }

    private enum ProductLookupTab: String, CaseIterable, Identifiable {
        case global
        case favorites

        var id: String { rawValue }
    }

    private typealias LibraryLookupTab = ProductLookupTab

    fileprivate enum LookupScope: Hashable, Identifiable {
        case scope(SearchScope)
        case favorites

        var id: String {
            switch self {
            case .scope(let s): return s.rawValue
            case .favorites: return "favorites"
            }
        }
    }

    init(
        title: String = NSLocalizedString(
            "catalog.lookup.title",
            tableName: nil,
            bundle: .main,
            value: "Catalog search",
            comment: "Food catalog lookup sheet title"
        ),
        allowedScopes: [SearchScope] = [.products, .recipes],
        onSelectAndEditProduct: ((ProductSummary) async -> UUID?)? = nil,
        onSelectAndEditRecipe: ((RecipeSummary) async -> UUID?)? = nil,
        onSelectAndEditMealTemplate: ((MealTemplateSummary) async -> UUID?)? = nil,
        addedItems: [MealItemEntry] = [],
        trayItems: [FoodCatalogTrayItem] = [],
        externalEditorTargetID: Binding<UUID?>? = nil,
        itemBindingProvider: ((UUID) -> Binding<MealItemEntry>?)? = nil,
        customEditorSheetProvider: ((UUID, @escaping () -> Void) -> AnyView?)? = nil,
        customEditorPresentationMode: CustomEditorPresentationMode = .sheet,
        onRemoveAddedItem: ((UUID) -> Void)? = nil,
        onSelectProduct: @escaping (ProductSummary) -> Void,
        onSelectRecipe: @escaping (RecipeSummary) -> Void,
        onSelectMealTemplate: @escaping (MealTemplateSummary) -> Void = { _ in }
    ) {
        self.title = title
        self.allowedScopes = allowedScopes
        self.onSelectAndEditProduct = onSelectAndEditProduct
        self.onSelectAndEditRecipe = onSelectAndEditRecipe
        self.onSelectAndEditMealTemplate = onSelectAndEditMealTemplate
        self.addedItems = addedItems
        self.trayItems = trayItems
        self.externalEditorTargetID = externalEditorTargetID
        self.itemBindingProvider = itemBindingProvider
        self.customEditorSheetProvider = customEditorSheetProvider
        self.customEditorPresentationMode = customEditorPresentationMode
        self.onRemoveAddedItem = onRemoveAddedItem
        self.onSelectProduct = onSelectProduct
        self.onSelectRecipe = onSelectRecipe
        self.onSelectMealTemplate = onSelectMealTemplate
        self._scope = State(initialValue: .scope(allowedScopes.first ?? .products))
    }

    private var effectiveTrayItems: [FoodCatalogTrayItem] {
        if !trayItems.isEmpty {
            return trayItems
        }

        return addedItems.map {
            FoodCatalogTrayItem(
                id: $0.id,
                title: displayTitle(for: $0),
                summary: itemChipSummary(for: $0)
            )
        }
    }

    private var quantityEditorBinding: Binding<AddedItemEditorTarget?> {
        if let externalEditorTargetID {
            return Binding(
                get: {
                    externalEditorTargetID.wrappedValue.map { AddedItemEditorTarget(itemID: $0) }
                },
                set: { newValue in
                    externalEditorTargetID.wrappedValue = newValue?.itemID
                }
            )
        }

        return $quantityEditorTarget
    }

    private var usesPushedCustomEditor: Bool {
        customEditorSheetProvider != nil && customEditorPresentationMode == .push
    }

    private var showsScopePicker: Bool {
        allowedScopes.count > 1
    }

    private var displayedScopes: [LookupScope] {
        let designOrder: [SearchScope] = [.products, .mealTemplates, .recipes]
        return designOrder
            .filter(allowedScopes.contains)
            .map { .scope($0) }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasActiveProductsQuery: Bool {
        !normalizedQuery.isEmpty || !scannedBarcode.isEmpty
    }

    private var localProducts: [ProductSummary] {
        if !scannedBarcode.isEmpty { return [] }
        return catalogService.search(query: query, scope: .products).products
    }

    /// Most frequently added products (on-device), shown before the user types.
    /// Excludes anything already listed under "My products" to avoid duplicates.
    private var frequentProducts: [ProductSummary] {
        let localIDs = Set(localProducts.map(\.id))
        return frequentStore.products.filter { !localIDs.contains($0.id) }
    }

    private var frequentProductsSectionTitle: String {
        localizedCatalogText("catalog.lookup.section.frequent_products", fallback: "Frequently used")
    }

    private var localRecipes: [RecipeSummary] {
        catalogService.search(query: query, scope: .recipes).recipes
    }

    private var localMealTemplates: [MealTemplateSummary] {
        catalogService.mealTemplatesMatching(query: query)
    }

    private var favoriteProducts: [ProductSummary] {
        []
    }

    private var favoriteRecipes: [RecipeSummary] {
        []
    }

    private var favoriteMealTemplates: [MealTemplateSummary] {
        []
    }

    private var globalProducts: [ProductSummary] {
        guard hasActiveProductsQuery else { return [] }
        let localIDs = Set(localProducts.map(\.id))
        return remoteProducts.filter { !localIDs.contains($0.id) }
    }

    private var shouldShowPlaceholder: Bool {
        normalizedQuery.isEmpty && scannedBarcode.isEmpty && localProducts.isEmpty && localRecipes.isEmpty
    }

    private var sheetBackgroundColor: Color {
        EOTheme.Palette.pageBackground
    }

    private var rowCardBackground: Color {
        EOTheme.Palette.card
    }

    private var addedTrayForeground: Color {
        colorScheme == .dark ? Color.black.opacity(0.88) : .white
    }

    private var addedTraySecondaryForeground: Color {
        colorScheme == .dark ? Color.black.opacity(0.68) : .white.opacity(0.85)
    }

    private var addedTrayStroke: Color {
        colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.25)
    }

    private var favoritesSectionTitle: String {
        localizedCatalogText("catalog.lookup.section.favorites", fallback: "Favorites")
    }

    private var globalProductsTabTitle: String {
        localizedCatalogText("products.tab.global", fallback: "Global")
    }

    private var favoritesProductsTabTitle: String {
        localizedCatalogText("products.tab.favorites", fallback: "Favorites")
    }

    private var localProductsSectionTitle: String {
        localizedCatalogText("catalog.lookup.section.local_products", fallback: "My products")
    }

    private var globalSearchSectionTitle: String {
        localizedCatalogText("catalog.lookup.section.global_search", fallback: "Global search")
    }

    private var loadingProductsTitle: String {
        localizedCatalogText("catalog.lookup.loading_products", fallback: "Searching products...")
    }

    private var noProductsTitle: String {
        localizedCatalogText("catalog.lookup.no_products", fallback: "No products found")
    }

    private var noMoreGlobalProductsTitle: String {
        localizedCatalogText("catalog.lookup.no_more_global_products", fallback: "Nothing else found globally")
    }

    private var noRecipesTitle: String {
        localizedCatalogText("catalog.lookup.no_recipes", fallback: "You don't have any recipes yet")
    }

    private var noRecipesFoundTitle: String {
        localizedCatalogText("catalog.lookup.no_recipes_found", fallback: "No recipes found")
    }

    private var noFavoriteProductsTitle: String {
        localizedCatalogText("products.favorites.empty.title", fallback: "No favorites yet")
    }

    private var noFavoriteProductsSubtitle: String {
        localizedCatalogText("products.favorites.empty.subtitle", fallback: "Swipe right on a product to add it to favorites.")
    }

    private var noFavoritesFoundTitle: String {
        localizedCatalogText("catalog.lookup.no_favorites_found", fallback: "No favorites found")
    }

    private var noMealTemplatesTitle: String {
        localizedCatalogText("catalog.lookup.no_meal_templates", fallback: "You don't have any rations yet")
    }

    private var noMealTemplatesFoundTitle: String {
        localizedCatalogText("catalog.lookup.no_meal_templates_found", fallback: "No rations found")
    }

    private var productPlaceholderTitle: String {
        localizedCatalogText("catalog.lookup.placeholder.products.title", fallback: "My products and global search")
    }

    private var productPlaceholderSubtitle: String {
        localizedCatalogText("catalog.lookup.placeholder.products.subtitle", fallback: "Search your library or the global product database.")
    }

    private var recipePlaceholderSubtitle: String {
        localizedCatalogText("catalog.lookup.placeholder.recipes.subtitle", fallback: "Choose a recipe from your library.")
    }

    private var mealTemplatePlaceholderSubtitle: String {
        localizedCatalogText("catalog.lookup.placeholder.meals.subtitle", fallback: "Choose a ration from your library.")
    }

    private var productNutritionSummaryUnit: String {
        NSLocalizedString("diary.kcal", comment: "Calories suffix")
    }

    private var gramsShortTitle: String {
        NSLocalizedString("unit.grams.short", comment: "Grams unit short title")
    }

    private var proteinShortTitle: String {
        NSLocalizedString("recipe.detail.protein_short", comment: "Protein short")
    }

    private var fatShortTitle: String {
        NSLocalizedString("recipe.detail.fat_short", comment: "Fat short")
    }

    private var carbsShortTitle: String {
        NSLocalizedString("recipe.detail.carbs_short", comment: "Carbs short")
    }

    private var perServingTitle: String {
        NSLocalizedString("recipe.editor.per_serving", comment: "Per serving")
    }

    private var nutritionPer100UnitTitle: String {
        String(
            format: NSLocalizedString("recipe.editor.nutrition_per_100_unit", comment: "Per 100 unit nutrition title"),
            gramsShortTitle
        )
    }

    private func localizedScopeTitle(_ scope: SearchScope) -> String {
        switch scope {
        case .products:
            return localizedCatalogText(scope.titleKey, fallback: "Products")
        case .recipes:
            return localizedCatalogText(scope.titleKey, fallback: "Recipes")
        case .mealTemplates:
            return localizedCatalogText(scope.titleKey, fallback: "Meals")
        }
    }

    private func localizedLookupScopeTitle(_ scope: LookupScope) -> String {
        switch scope {
        case .scope(let s):
            return localizedScopeTitle(s)
        case .favorites:
            return favoritesSectionTitle
        }
    }

    private var scopeSegments: [EOSegmentedPicker<LookupScope>.Segment] {
        displayedScopes.map { lookupScope in
            EOSegmentedPicker<LookupScope>.Segment(
                lookupScope,
                title: Text(verbatim: localizedLookupScopeTitle(lookupScope))
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showsScopePicker {
                    EOSegmentedPicker(selection: $scope, segments: scopeSegments)
                        .padding(.horizontal, EOTheme.Metrics.screenInset)
                        .padding(.bottom, 8)
                }

                switch scope {
                case .scope(.products):
                    productsTab
                case .scope(.recipes):
                    recipesTab
                case .scope(.mealTemplates):
                    mealTemplatesTab
                case .favorites:
                    favoritesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(sheetBackgroundColor)
            .eoSheetChrome(
                title: Text(verbatim: title),
                trailing: .confirm(isEnabled: true) { dismiss() },
                onClose: { dismiss() }
            )
            .dismissesKeyboardInteractively()
            .onAppear {
                scheduleRemoteSearch()
            }
            .onChange(of: query) { _, newValue in
                if !newValue.isEmpty {
                    scannedBarcode = ""
                }
                scheduleRemoteSearch()
            }
            .onChange(of: scope) { _, _ in
                scheduleRemoteSearch()
            }
            .onChange(of: scannedBarcode) { _, _ in
                scheduleRemoteSearch()
            }
            .onDisappear {
                searchTask?.cancel()
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                VStack(spacing: 10) {
                    addedItemsTray
                        .opacity(effectiveTrayItems.isEmpty ? 0 : 1)
                        .frame(height: effectiveTrayItems.isEmpty ? 0 : nil)
                        .clipped()

                    EOSearchBar(
                        text: $query,
                        showsScanner: allowedScopes.contains(.products),
                        onScan: { isBarcodeScannerPresented = true }
                    )
                }
            }
            .navigationDestination(item: $pushedCustomEditorTarget) { target in
                if let customEditorSheetProvider,
                   let editorView = customEditorSheetProvider(target.itemID, {
                       pushedCustomEditorTarget = nil
                   }) {
                    editorView
                }
            }
        }
        .sheet(isPresented: $isBarcodeScannerPresented) {
            BarcodeScannerSheet { code in
                let digits = code.filter { $0.isNumber }
                let resolved = digits.count >= 6 ? digits : code
                scope = .scope(.products)
                query = ""
                scannedBarcode = resolved
            }
        }
        .sheet(item: $previewDestination) { destination in
            NavigationStack {
                switch destination {
                case .product(let product):
                    ProductDetailView(productID: product.id, initialProduct: product, showsDismissButton: true, allowsProductForking: false)
                case .recipe(let recipe):
                    RecipeDetailView(recipeID: recipe.id, initialRecipe: recipe, showsDismissButton: true)
                case .mealTemplate(let mealTemplate):
                    MealTemplateDetailView(mealTemplateID: mealTemplate.id, initialMealTemplate: mealTemplate, showsDismissButton: true)
                }
            }
            .environmentObject(catalogService)
        }
        .sheet(item: quantityEditorBinding) { target in
            if let customEditorSheetProvider,
               let editorSheet = customEditorSheetProvider(target.itemID, {
                   quantityEditorBinding.wrappedValue = nil
               }) {
                editorSheet
            } else if let itemBinding = itemBindingProvider?(target.itemID) {
                MealItemQuantityEditorSheet(
                    item: itemBinding,
                    catalogService: catalogService,
                    onDelete: {
                        onRemoveAddedItem?(target.itemID)
                    },
                    onClose: {
                        quantityEditorBinding.wrappedValue = nil
                    }
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(sheetBackgroundColor.ignoresSafeArea())
            }
        }
    }

    @ViewBuilder
    private var productsTab: some View {
        globalProductsTab
    }

    @ViewBuilder
    private func productListCard(_ products: [ProductSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                productRow(product)
                if index < products.count - 1 {
                    EORowSeparator()
                }
            }
        }
        .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .padding(.horizontal, EOTheme.Metrics.screenInset)
    }

    @ViewBuilder
    private var globalProductsTab: some View {
        if !hasActiveProductsQuery {
            if frequentProducts.isEmpty && localProducts.isEmpty {
                productPlaceholderView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !frequentProducts.isEmpty {
                            sectionHeader(
                                frequentProductsSectionTitle,
                                actionTitle: "common.clear"
                            ) {
                                frequentStore.clear()
                            }
                            productListCard(frequentProducts)
                        }
                        if !localProducts.isEmpty {
                            if !frequentProducts.isEmpty {
                                Spacer().frame(height: 2)
                            }
                            sectionHeader(localProductsSectionTitle)
                            productListCard(localProducts)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        } else if hasActiveProductsQuery && searchService.isLoading && localProducts.isEmpty && globalProducts.isEmpty {
            emptyStatePlaceholder(title: loadingProductsTitle)
        } else if let errorText = searchErrorText, localProducts.isEmpty && globalProducts.isEmpty {
            emptyStatePlaceholder(title: errorText)
        } else if hasActiveProductsQuery && !searchService.isLoading && localProducts.isEmpty && globalProducts.isEmpty {
            emptyStatePlaceholder(title: noProductsTitle)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !localProducts.isEmpty {
                        sectionHeader(localProductsSectionTitle)
                        VStack(spacing: 0) {
                            ForEach(Array(localProducts.enumerated()), id: \.element.id) { index, product in
                                productRow(product)
                                if index < localProducts.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                        .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                        .padding(.horizontal, EOTheme.Metrics.screenInset)
                    }

                    if hasActiveProductsQuery {
                        if !localProducts.isEmpty {
                            Spacer().frame(height: 12)
                        }
                        sectionHeader(globalSearchSectionTitle)

                        if searchService.isLoading {
                            emptyStateListPlaceholder(title: loadingProductsTitle)
                        } else if !globalProducts.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(globalProducts.enumerated()), id: \.element.id) { index, product in
                                    productRow(product)
                                    if index < globalProducts.count - 1 {
                                        EORowSeparator()
                                    }
                                }
                            }
                            .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                            .padding(.horizontal, EOTheme.Metrics.screenInset)
                        } else if localProducts.isEmpty {
                            emptyStateRow(title: noProductsTitle)
                        } else {
                            emptyStateRow(title: noMoreGlobalProductsTitle)
                        }
                    }

                    if let errorText = searchErrorText {
                        emptyStateListPlaceholder(title: errorText)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var favoriteProductsTab: some View {
        if normalizedQuery.isEmpty && favoriteProducts.isEmpty {
            favoriteProductsPlaceholderView
        } else if !normalizedQuery.isEmpty && favoriteProducts.isEmpty {
            emptyStatePlaceholder(title: noProductsTitle)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Spacer().frame(height: 12)
                    if !favoriteProducts.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(favoriteProducts.enumerated()), id: \.element.id) { index, product in
                                productRow(product)
                                if index < favoriteProducts.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                        .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                        .padding(.horizontal, EOTheme.Metrics.screenInset)
                    } else {
                        emptyStateRow(title: noProductsTitle)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var recipesTab: some View {
        globalRecipesTab
    }

    @ViewBuilder
    private var globalRecipesTab: some View {
        if normalizedQuery.isEmpty && localRecipes.isEmpty {
            recipePlaceholderView
        } else if !normalizedQuery.isEmpty && localRecipes.isEmpty {
            emptyStatePlaceholder(title: noRecipesFoundTitle)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Spacer().frame(height: 12)
                    if !localRecipes.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(localRecipes.enumerated()), id: \.element.id) { index, recipe in
                                recipeRow(recipe)
                                if index < localRecipes.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                        .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                        .padding(.horizontal, EOTheme.Metrics.screenInset)
                    } else if normalizedQuery.isEmpty {
                        emptyStateRow(title: noRecipesTitle)
                    } else {
                        emptyStateRow(title: noRecipesFoundTitle)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var favoriteRecipesTab: some View {
        if favoriteRecipes.isEmpty {
            emptyStatePlaceholder(title: normalizedQuery.isEmpty ? noRecipesTitle : noRecipesFoundTitle)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Spacer().frame(height: 12)
                    VStack(spacing: 0) {
                        ForEach(Array(favoriteRecipes.enumerated()), id: \.element.id) { index, recipe in
                            recipeRow(recipe)
                            if index < favoriteRecipes.count - 1 {
                                EORowSeparator()
                            }
                        }
                    }
                    .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var mealTemplatesTab: some View {
        globalMealTemplatesTab
    }

    @ViewBuilder
    private var globalMealTemplatesTab: some View {
        if normalizedQuery.isEmpty && localMealTemplates.isEmpty {
            mealTemplatePlaceholderView
        } else if !normalizedQuery.isEmpty && localMealTemplates.isEmpty {
            emptyStatePlaceholder(title: noMealTemplatesFoundTitle)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Spacer().frame(height: 12)
                    if !localMealTemplates.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(localMealTemplates.enumerated()), id: \.element.id) { index, mealTemplate in
                                mealTemplateRow(mealTemplate)
                                if index < localMealTemplates.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                        .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                        .padding(.horizontal, EOTheme.Metrics.screenInset)
                    } else if normalizedQuery.isEmpty {
                        emptyStateRow(title: noMealTemplatesTitle)
                    } else {
                        emptyStateRow(title: noMealTemplatesFoundTitle)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var favoriteMealTemplatesTab: some View {
        if favoriteMealTemplates.isEmpty {
            emptyStatePlaceholder(title: normalizedQuery.isEmpty ? noMealTemplatesTitle : noMealTemplatesFoundTitle)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Spacer().frame(height: 12)
                    VStack(spacing: 0) {
                        ForEach(Array(favoriteMealTemplates.enumerated()), id: \.element.id) { index, mealTemplate in
                            mealTemplateRow(mealTemplate)
                            if index < favoriteMealTemplates.count - 1 {
                                EORowSeparator()
                            }
                        }
                    }
                    .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var favoritesTab: some View {
        let products = allowedScopes.contains(.products) ? favoriteProducts : []
        let recipes = allowedScopes.contains(.recipes) ? favoriteRecipes : []
        let mealTemplates = allowedScopes.contains(.mealTemplates) ? favoriteMealTemplates : []
        let isEmpty = products.isEmpty && recipes.isEmpty && mealTemplates.isEmpty

        if isEmpty {
            if normalizedQuery.isEmpty {
                favoriteProductsPlaceholderView
            } else {
                emptyStatePlaceholder(title: noFavoritesFoundTitle)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    Spacer().frame(height: 4)

                    if !products.isEmpty {
                        favoritesSection(
                            title: localizedScopeTitle(.products),
                            count: products.count
                        ) {
                            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                                productRow(product)
                                if index < products.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                    }

                    if !recipes.isEmpty {
                        favoritesSection(
                            title: localizedScopeTitle(.recipes),
                            count: recipes.count
                        ) {
                            ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                                recipeRow(recipe)
                                if index < recipes.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                    }

                    if !mealTemplates.isEmpty {
                        favoritesSection(
                            title: localizedScopeTitle(.mealTemplates),
                            count: mealTemplates.count
                        ) {
                            ForEach(Array(mealTemplates.enumerated()), id: \.element.id) { index, mealTemplate in
                                mealTemplateRow(mealTemplate)
                                if index < mealTemplates.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func favoritesSection<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 24)

            VStack(spacing: 0) {
                content()
            }
            .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private var productPlaceholderView: some View {
        VStack(spacing: 14) {
            FoodPlaceholderArtwork(kind: .grocery, width: 128, height: 128)

            VStack(spacing: 6) {
                Text(productPlaceholderTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(productPlaceholderSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .background(sheetBackgroundColor)
    }

    private var favoriteProductsPlaceholderView: some View {
        VStack(spacing: 14) {
            FoodPlaceholderArtwork(kind: .favorite, width: 128, height: 128)

            VStack(spacing: 6) {
                Text(noFavoriteProductsTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(noFavoriteProductsSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .background(sheetBackgroundColor)
    }

    private var recipePlaceholderView: some View {
        VStack(spacing: 14) {
            FoodPlaceholderArtwork(kind: .recipe, width: 128, height: 128)

            VStack(spacing: 6) {
                Text(recipePlaceholderSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .background(sheetBackgroundColor)
    }

    private var mealTemplatePlaceholderView: some View {
        VStack(spacing: 14) {
            FoodPlaceholderArtwork(kind: .meal, width: 128, height: 128)

            VStack(spacing: 6) {
                Text(mealTemplatePlaceholderSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .background(sheetBackgroundColor)
    }


    /// Mock-up header: bold black title on the left, optional grey action right.
    private func sectionHeader(_ title: String, actionTitle: LocalizedStringKey? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(EOTheme.Typography.rowValue)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, EOTheme.Metrics.screenInset + EOTheme.Metrics.cardInset)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func emptyStateRow(title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.vertical, 18)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                    .fill(rowCardBackground)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private func emptyStatePlaceholder(title: String) -> some View {
        Text(title)
            .font(.body.weight(.medium))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(sheetBackgroundColor)
    }

    @ViewBuilder
    private func emptyStateListPlaceholder(title: String) -> some View {
        Text(title)
            .font(.body.weight(.medium))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Mock-up row: name + macro line, tinted "Add +" on the right.
    @ViewBuilder
    private func productRow(_ product: ProductSummary) -> some View {
        EOListRow(
            title: Text(verbatim: product.name),
            subtitle: Text(verbatim: productSummaryText(product))
        ) {
            addAccessory { handleProductSelection(product) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            previewDestination = .product(product)
        }
    }

    @ViewBuilder
    private func recipeRow(_ recipe: RecipeSummary) -> some View {
        EOListRow(
            title: Text(verbatim: recipe.title),
            subtitle: Text(verbatim: recipeSummaryText(recipe))
        ) {
            addAccessory { handleRecipeSelection(recipe) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            previewDestination = .recipe(recipe)
        }
    }

    private func addAccessory(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("common.add")
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
            }
            .font(EOTheme.Typography.rowValue)
            .foregroundStyle(EOTheme.Palette.accent)
            .padding(.leading, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func mealTemplateRow(_ mealTemplate: MealTemplateSummary) -> some View {
        EOListRow(
            title: Text(verbatim: mealTemplate.title),
            subtitle: Text(verbatim: mealTemplateSummaryText(mealTemplate))
        ) {
            addAccessory { handleMealTemplateSelection(mealTemplate) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            previewDestination = .mealTemplate(mealTemplate)
        }
    }

    private var searchErrorText: String? {
        let text = searchService.lastErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private var addedItemsTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(effectiveTrayItems) { item in
                    Button {
                        presentEditor(for: item.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(addedTrayForeground)

                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(addedTrayForeground)
                                .lineLimit(1)

                            Text(item.summary)
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(addedTraySecondaryForeground)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(EOTheme.Palette.accent)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(addedTrayStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func localizedCatalogText(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "Food catalog lookup localized text")
    }

    private func displayTitle(for item: MealItemEntry) -> String {
        let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return NSLocalizedString("addmeal.item.product_fallback", comment: "Meal item fallback title")
        }
        return trimmedName
    }

    private func itemChipSummary(for item: MealItemEntry) -> String {
        let caloriesUnit = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        let product = catalogService.productSummary(for: item)
        let quantityText = displayFoodQuantityText(amount: item.amount, unit: item.unit, servingLabel: item.servingLabel, product: product)
        return "\(quantityText) · \(item.calories) \(caloriesUnit)"
    }

    private func amountText(for value: Double) -> String {
        formatFoodAmount(value)
    }

    private func handleProductSelection(_ product: ProductSummary) {
        frequentStore.record(product)

        if let onSelectAndEditProduct {
            Task {
                guard let itemID = await onSelectAndEditProduct(product) else { return }
                await MainActor.run {
                    presentEditorAfterSourceUpdate(for: itemID)
                }
            }
            return
        }

        onSelectProduct(product)
        dismiss()
    }

    private func handleRecipeSelection(_ recipe: RecipeSummary) {
        if let onSelectAndEditRecipe {
            Task {
                if let itemID = await onSelectAndEditRecipe(recipe) {
                    await MainActor.run {
                        presentEditorAfterSourceUpdate(for: itemID)
                    }
                }
            }
        } else {
            onSelectRecipe(recipe)
        }
    }

    private func handleMealTemplateSelection(_ mealTemplate: MealTemplateSummary) {
        if let onSelectAndEditMealTemplate {
            Task {
                if let itemID = await onSelectAndEditMealTemplate(mealTemplate) {
                    await MainActor.run {
                        presentEditorAfterSourceUpdate(for: itemID)
                    }
                }
            }
        } else {
            onSelectMealTemplate(mealTemplate)
        }
    }

    private func presentEditor(for itemID: UUID) {
        let target = AddedItemEditorTarget(itemID: itemID)
        if usesPushedCustomEditor {
            pushedCustomEditorTarget = target
        } else {
            quantityEditorBinding.wrappedValue = target
        }
    }

    private func presentEditorAfterSourceUpdate(for itemID: UUID) {
        DispatchQueue.main.async {
            presentEditor(for: itemID)
        }
    }

    private func productSummaryText(_ product: ProductSummary) -> String {
        let nutritionText = "\(product.caloriesPer100g) \(productNutritionSummaryUnit) / 100 \(product.per100UnitShortTitle) · \(proteinShortTitle) \(product.proteinPer100g) · \(fatShortTitle) \(product.fatPer100g) · \(carbsShortTitle) \(product.carbsPer100g)"
        if product.brand.isEmpty {
            return nutritionText
        }
        return "\(product.brand) · \(nutritionText)"
    }

    private func recipeSummaryText(_ recipe: RecipeSummary) -> String {
        let per100gNutrition = recipe.resolvedNutritionPer100g
        var components = [
            "\(recipe.caloriesPerServing) \(productNutritionSummaryUnit) · \(perServingTitle) · \(proteinShortTitle) \(recipe.proteinPerServing) · \(fatShortTitle) \(recipe.fatPerServing) · \(carbsShortTitle) \(recipe.carbsPerServing)"
        ]
        if per100gNutrition != .zero {
            components.append(
                "\(per100gNutrition.calories) \(productNutritionSummaryUnit) · \(nutritionPer100UnitTitle) · \(proteinShortTitle) \(per100gNutrition.protein) · \(fatShortTitle) \(per100gNutrition.fat) · \(carbsShortTitle) \(per100gNutrition.carbs)"
            )
        }
        return components.joined(separator: " · ")
    }

    private func mealTemplateSummaryText(_ mealTemplate: MealTemplateSummary) -> String {
        let itemCount = mealTemplate.items.count
        let itemsText = itemCount == 1
            ? localizedCatalogText("catalog.lookup.meal_template.single_item", fallback: "1 item")
            : String(format: localizedCatalogText("catalog.lookup.meal_template.items", fallback: "%d items"), itemCount)
        return "\(mealTemplate.calories) \(productNutritionSummaryUnit) · \(itemsText)"
    }

    private func scheduleRemoteSearch() {
        searchTask?.cancel()

        let effectiveQuery = scannedBarcode.isEmpty ? normalizedQuery : scannedBarcode
        let isBarcodeLookup = !scannedBarcode.isEmpty
        guard scope == .scope(.products), !effectiveQuery.isEmpty else {
            remoteProducts = []
            return
        }

        searchTask = Task {
            if !isBarcodeLookup {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            guard !Task.isCancelled else { return }

            let remote = await searchService.searchProducts(query: effectiveQuery, limit: 30, offset: 0)
            guard !Task.isCancelled else { return }

            let mapped = remote.map(mapRemoteProduct)
            await MainActor.run {
                remoteProducts = mapped
            }
        }
    }

    private func mapRemoteProduct(_ result: Search_ProductSearchResult) -> ProductSummary {
        if let id = UUID(uuidString: result.id), let existing = catalogService.productSummary(id: id) {
            return existing
        }

        return ProductSummary(
            id: UUID(uuidString: result.id) ?? UUID(),
            name: result.name,
            brand: result.brand,
            barcode: result.barcode,
            caloriesPer100g: Int(result.caloriesPer100G.rounded()),
            proteinPer100g: Int(result.proteinPer100G.rounded()),
            fatPer100g: Int(result.fatPer100G.rounded()),
            carbsPer100g: Int(result.carbsPer100G.rounded()),
            details: result.description_p
        )
    }
}

struct RecipeIngredientCatalogLookupSheet: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let recipeID: UUID?
    let onDismiss: (() -> Void)?

    @Binding var ingredients: [RecipeIngredientDraft]

    @State private var query = ""
    @State private var scope: SearchScope = .products
    @StateObject private var searchService = FoodSearchService(authService: FoodAuthService.shared)
    @State private var remoteProducts: [ProductSummary] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var previewDestination: FoodCatalogPreviewDestination?
    @State private var quantityEditorTarget: AddedIngredientEditorTarget?
    @State private var errorMessage: String?
    @State private var pendingIngredientIDs: Set<UUID> = []
    @State private var isBarcodeScannerPresented = false

    init(
        title: String,
        recipeID: UUID?,
        ingredients: Binding<[RecipeIngredientDraft]>,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.recipeID = recipeID
        self._ingredients = ingredients
        self.onDismiss = onDismiss
    }

    private enum FoodCatalogPreviewDestination: Identifiable, Hashable {
        case product(ProductSummary)
        case recipe(RecipeSummary)

        var id: String {
            switch self {
            case .product(let product):
                return "product-\(product.id.uuidString)"
            case .recipe(let recipe):
                return "recipe-\(recipe.id.uuidString)"
            }
        }
    }

    private struct AddedIngredientEditorTarget: Identifiable, Hashable {
        let ingredientID: UUID
        var id: UUID { ingredientID }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localProducts: [ProductSummary] {
        catalogService.search(query: query, scope: .products).products
    }

    private var localRecipes: [RecipeSummary] {
        catalogService.search(query: query, scope: .recipes).recipes
    }

    private var favoriteProducts: [ProductSummary] {
        []
    }

    private var globalProducts: [ProductSummary] {
        guard !normalizedQuery.isEmpty else { return [] }
        let localIDs = Set(localProducts.map(\.id))
        return remoteProducts.filter { !localIDs.contains($0.id) }
    }

    private var shouldShowPlaceholder: Bool {
        normalizedQuery.isEmpty && localProducts.isEmpty && localRecipes.isEmpty
    }

    private var committedIngredients: [RecipeIngredientDraft] {
        ingredients.filter { !pendingIngredientIDs.contains($0.id) }
    }

    private var sheetBackgroundColor: Color {
        EOTheme.Palette.pageBackground
    }

    private var rowCardBackground: Color {
        EOTheme.Palette.card
    }

    private var addedTrayForeground: Color {
        colorScheme == .dark ? Color.black.opacity(0.88) : .white
    }

    private var addedTraySecondaryForeground: Color {
        colorScheme == .dark ? Color.black.opacity(0.68) : .white.opacity(0.85)
    }

    private var addedTrayStroke: Color {
        colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.25)
    }

    private var favoritesSectionTitle: String {
        localizedCatalogText("catalog.lookup.section.favorites", fallback: "Favorites")
    }

    private var localProductsSectionTitle: String {
        localizedCatalogText("catalog.lookup.section.local_products", fallback: "My products")
    }

    private var globalSearchSectionTitle: String {
        localizedCatalogText("catalog.lookup.section.global_search", fallback: "Global search")
    }

    private var loadingProductsTitle: String {
        localizedCatalogText("catalog.lookup.loading_products", fallback: "Searching products...")
    }

    private var noProductsTitle: String {
        localizedCatalogText("catalog.lookup.no_products", fallback: "No products found")
    }

    private var noMoreGlobalProductsTitle: String {
        localizedCatalogText("catalog.lookup.no_more_global_products", fallback: "Nothing else found globally")
    }

    private var noRecipesTitle: String {
        localizedCatalogText("catalog.lookup.no_recipes", fallback: "You don't have any recipes yet")
    }

    private var noRecipesFoundTitle: String {
        localizedCatalogText("catalog.lookup.no_recipes_found", fallback: "No recipes found")
    }

    private var productPlaceholderTitle: String {
        localizedCatalogText("catalog.lookup.placeholder.products.title", fallback: "My products and global search")
    }

    private var productPlaceholderSubtitle: String {
        localizedCatalogText("catalog.lookup.placeholder.products.subtitle", fallback: "Search your library or the global product database.")
    }

    private var recipePlaceholderSubtitle: String {
        localizedCatalogText("catalog.lookup.placeholder.recipes.subtitle", fallback: "Choose a recipe from your library.")
    }

    private var productNutritionSummaryUnit: String {
        NSLocalizedString("diary.kcal", comment: "Calories suffix")
    }

    private var gramsShortTitle: String {
        NSLocalizedString("unit.grams.short", comment: "Grams unit short title")
    }

    private var proteinShortTitle: String {
        NSLocalizedString("recipe.detail.protein_short", comment: "Protein short")
    }

    private var fatShortTitle: String {
        NSLocalizedString("recipe.detail.fat_short", comment: "Fat short")
    }

    private var carbsShortTitle: String {
        NSLocalizedString("recipe.detail.carbs_short", comment: "Carbs short")
    }

    private var perServingTitle: String {
        NSLocalizedString("recipe.editor.per_serving", comment: "Per serving")
    }

    private var nutritionPer100UnitTitle: String {
        String(
            format: NSLocalizedString("recipe.editor.nutrition_per_100_unit", comment: "Per 100 unit nutrition title"),
            gramsShortTitle
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EOSegmentedPicker(selection: $scope, segments: scopeSegments)
                    .padding(.horizontal, EOTheme.Metrics.screenInset)
                    .padding(.bottom, 8)

                switch scope {
                case .products:
                    productsTab
                case .recipes:
                    recipesTab
                case .mealTemplates:
                    recipesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(sheetBackgroundColor)
            .eoSheetChrome(
                title: Text(verbatim: title),
                trailing: .confirm(isEnabled: true) {
                    onDismiss?()
                    dismiss()
                },
                onClose: {
                    discardPendingIngredients()
                    onDismiss?()
                    dismiss()
                }
            )
            .dismissesKeyboardInteractively()
            .onAppear {
                scheduleRemoteSearch()
            }
            .onChange(of: query) { _, _ in
                scheduleRemoteSearch()
            }
            .onDisappear {
                searchTask?.cancel()
            }
            .alert("recipe.editor.save_error_title", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("common.ok", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                VStack(spacing: 10) {
                    addedItemsTray
                        .opacity(committedIngredients.isEmpty ? 0 : 1)
                        .frame(height: committedIngredients.isEmpty ? 0 : nil)
                        .clipped()

                    EOSearchBar(
                        text: $query,
                        showsScanner: true,
                        onScan: { isBarcodeScannerPresented = true }
                    )
                }
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $isBarcodeScannerPresented) {
            BarcodeScannerSheet { code in
                let digits = code.filter { $0.isNumber }
                scope = .products
                query = digits.count >= 6 ? digits : code
            }
        }
        .sheet(item: $previewDestination) { destination in
            NavigationStack {
                switch destination {
                case .product(let product):
                    ProductDetailView(productID: product.id, initialProduct: product, showsDismissButton: true)
                case .recipe(let recipe):
                    RecipeDetailView(recipeID: recipe.id, initialRecipe: recipe, showsDismissButton: true)
                }
            }
            .environmentObject(catalogService)
        }
        .sheet(item: $quantityEditorTarget) { target in
            if let ingredientBinding = ingredientBinding(for: target.ingredientID) {
                RecipeIngredientQuantityEditorSheet(
                    ingredient: ingredientBinding,
                    catalogService: catalogService,
                    onDelete: {
                        removeIngredient(withID: target.ingredientID)
                    },
                    onCancel: {
                        discardPendingIngredient(withID: target.ingredientID)
                        quantityEditorTarget = nil
                    },
                    onConfirm: {
                        commitPendingIngredient(withID: target.ingredientID)
                        quantityEditorTarget = nil
                    },
                    onClose: {
                        discardPendingIngredient(withID: target.ingredientID)
                        quantityEditorTarget = nil
                    },
                    usesOwnNavigationContainer: true
                )
            }
        }
    }

    @ViewBuilder
    private var productsTab: some View {
        if normalizedQuery.isEmpty && localProducts.isEmpty && favoriteProducts.isEmpty {
            productPlaceholderView
        } else if !normalizedQuery.isEmpty && searchService.isLoading && localProducts.isEmpty && favoriteProducts.isEmpty && globalProducts.isEmpty {
            emptyStatePlaceholder(title: loadingProductsTitle)
        } else if let errorText = searchErrorText, localProducts.isEmpty && favoriteProducts.isEmpty && globalProducts.isEmpty {
            emptyStatePlaceholder(title: errorText)
        } else if !normalizedQuery.isEmpty && localProducts.isEmpty && favoriteProducts.isEmpty && globalProducts.isEmpty && !searchService.isLoading {
            emptyStatePlaceholder(title: noProductsTitle)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !favoriteProducts.isEmpty {
                        sectionHeader(favoritesSectionTitle)
                        VStack(spacing: 0) {
                            ForEach(Array(favoriteProducts.enumerated()), id: \.element.id) { index, product in
                                productRow(product)
                                if index < favoriteProducts.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                        .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                        .padding(.horizontal, EOTheme.Metrics.screenInset)
                    }

                    if !localProducts.isEmpty {
                        sectionHeader(localProductsSectionTitle)
                        VStack(spacing: 0) {
                            ForEach(Array(localProducts.enumerated()), id: \.element.id) { index, product in
                                productRow(product)
                                if index < localProducts.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                        .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                        .padding(.horizontal, EOTheme.Metrics.screenInset)
                    }

                    if !normalizedQuery.isEmpty {
                        if !localProducts.isEmpty || !favoriteProducts.isEmpty {
                            Spacer().frame(height: 12)
                        }
                        sectionHeader(globalSearchSectionTitle)
                        if searchService.isLoading {
                            emptyStateListPlaceholder(title: loadingProductsTitle)
                        } else if !globalProducts.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(globalProducts.enumerated()), id: \.element.id) { index, product in
                                    productRow(product)
                                    if index < globalProducts.count - 1 {
                                        EORowSeparator()
                                    }
                                }
                            }
                            .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                            .padding(.horizontal, EOTheme.Metrics.screenInset)
                        } else if localProducts.isEmpty {
                            emptyStateRow(title: noProductsTitle)
                        } else {
                            emptyStateRow(title: noMoreGlobalProductsTitle)
                        }
                    }

                    if let errorText = searchErrorText {
                        emptyStateListPlaceholder(title: errorText)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var recipesTab: some View {
        if normalizedQuery.isEmpty && localRecipes.isEmpty {
            recipePlaceholderView
        } else if !normalizedQuery.isEmpty && localRecipes.isEmpty {
            emptyStatePlaceholder(title: noRecipesFoundTitle)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Spacer().frame(height: 12)
                    if !localRecipes.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(localRecipes.enumerated()), id: \.element.id) { index, recipe in
                                recipeRow(recipe)
                                if index < localRecipes.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                        .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                        .padding(.horizontal, EOTheme.Metrics.screenInset)
                    } else if normalizedQuery.isEmpty {
                        emptyStateRow(title: noRecipesTitle)
                    } else {
                        emptyStateRow(title: noRecipesFoundTitle)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private var productPlaceholderView: some View {
        VStack(spacing: 14) {
            FoodPlaceholderArtwork(kind: .grocery, width: 128, height: 128)

            VStack(spacing: 6) {
                Text(productPlaceholderTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(productPlaceholderSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .background(sheetBackgroundColor)
    }

    private var recipePlaceholderView: some View {
        VStack(spacing: 14) {
            FoodPlaceholderArtwork(kind: .recipe, width: 128, height: 128)

            VStack(spacing: 6) {
                Text(recipePlaceholderSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .background(sheetBackgroundColor)
    }


    /// Mock-up header: bold black title on the left, optional grey action right.
    private func sectionHeader(_ title: String, actionTitle: LocalizedStringKey? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(EOTheme.Typography.rowValue)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, EOTheme.Metrics.screenInset + EOTheme.Metrics.cardInset)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func emptyStateRow(title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.vertical, 18)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                    .fill(rowCardBackground)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private func emptyStatePlaceholder(title: String) -> some View {
        Text(title)
            .font(.body.weight(.medium))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(sheetBackgroundColor)
    }

    @ViewBuilder
    private func emptyStateListPlaceholder(title: String) -> some View {
        Text(title)
            .font(.body.weight(.medium))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Mock-up row: name + macro line, tinted "Add +" on the right.
    @ViewBuilder
    private func productRow(_ product: ProductSummary) -> some View {
        EOListRow(
            title: Text(verbatim: product.name),
            subtitle: Text(verbatim: productSummaryText(product))
        ) {
            addAccessory { handleProductSelection(product) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            previewDestination = .product(product)
        }
    }

    @ViewBuilder
    private func recipeRow(_ recipe: RecipeSummary) -> some View {
        EOListRow(
            title: Text(verbatim: recipe.title),
            subtitle: Text(verbatim: recipeSummaryText(recipe))
        ) {
            addAccessory { handleRecipeSelection(recipe) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            previewDestination = .recipe(recipe)
        }
    }

    private func addAccessory(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("common.add")
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
            }
            .font(EOTheme.Typography.rowValue)
            .foregroundStyle(EOTheme.Palette.accent)
            .padding(.leading, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scopeSegments: [EOSegmentedPicker<SearchScope>.Segment] {
        [SearchScope.products, SearchScope.recipes].map { searchScope in
            EOSegmentedPicker<SearchScope>.Segment(
                searchScope,
                title: Text(verbatim: searchScope.title)
            )
        }
    }

    private var addedItemsTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(committedIngredients) { ingredient in
                    Button {
                        quantityEditorTarget = AddedIngredientEditorTarget(ingredientID: ingredient.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(addedTrayForeground)

                            Text(displayName(for: ingredient))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(addedTrayForeground)
                                .lineLimit(1)

                            Text(ingredientSummary(for: ingredient))
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(addedTraySecondaryForeground)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(EOTheme.Palette.accent)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(addedTrayStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func ingredientBinding(for ingredientID: UUID) -> Binding<RecipeIngredientDraft>? {
        guard let currentIngredient = ingredients.first(where: { $0.id == ingredientID }) else { return nil }

        return Binding(
            get: {
                ingredients.first(where: { $0.id == ingredientID }) ?? currentIngredient
            },
            set: { updatedIngredient in
                guard let index = ingredients.firstIndex(where: { $0.id == ingredientID }) else { return }
                ingredients[index] = updatedIngredient
            }
        )
    }

    private func removeIngredient(withID ingredientID: UUID) {
        guard let index = ingredients.firstIndex(where: { $0.id == ingredientID }) else { return }
        ingredients.remove(at: index)
        pendingIngredientIDs.remove(ingredientID)
        if quantityEditorTarget?.ingredientID == ingredientID {
            quantityEditorTarget = nil
        }
    }

    private func commitPendingIngredient(withID ingredientID: UUID) {
        pendingIngredientIDs.remove(ingredientID)
    }

    private func discardPendingIngredient(withID ingredientID: UUID) {
        guard pendingIngredientIDs.remove(ingredientID) != nil else { return }
        removeIngredient(withID: ingredientID)
    }

    private func discardPendingIngredients() {
        guard !pendingIngredientIDs.isEmpty else { return }
        let ingredientIDs = pendingIngredientIDs
        pendingIngredientIDs.removeAll()
        ingredients.removeAll { ingredientIDs.contains($0.id) }
    }

    private var searchErrorText: String? {
        let text = searchService.lastErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private func displayName(for ingredient: RecipeIngredientDraft) -> String {
        let resolved = catalogService.resolvedName(for: ingredient)
        return resolved.isEmpty ? NSLocalizedString("recipe.editor.new_ingredient", comment: "New ingredient") : resolved
    }

    private func ingredientDescription(for ingredient: RecipeIngredientDraft) -> String {
        if ingredient.productID != nil {
            return NSLocalizedString("products.title", comment: "Product")
        }
        if ingredient.nestedRecipeID != nil {
            return NSLocalizedString("recipes.title", comment: "Recipe")
        }
        return NSLocalizedString("recipe.editor.not_selected", comment: "Not selected")
    }

    private func ingredientSummary(for ingredient: RecipeIngredientDraft) -> String {
        let product = catalogService.productSummary(for: ingredient)
        let amount = displayFoodQuantityText(amount: ingredient.amount, unit: ingredient.unit, servingLabel: ingredient.servingLabel, product: product)
        let source = ingredientDescription(for: ingredient)
        return "\(amount) · \(source)"
    }

    private func amountText(for value: Double) -> String {
        formatFoodAmount(value)
    }

    private func resolvedUnit(for ingredient: RecipeIngredientDraft) -> MealItemUnit {
        if let product = catalogService.productSummary(for: ingredient) {
            return product.servingUnit
        }
        if ingredient.nestedRecipeID != nil {
            return ingredient.unit == .milliliters ? .grams : ingredient.unit
        }
        return ingredient.unit
    }

    private func defaultAmount(for product: ProductSummary) -> Double {
        max(100, 1)
    }

    private func handleProductSelection(_ product: ProductSummary) {
        Task {
            let resolved = await catalogService.fetchProductSnapshot(id: product.id) ?? product
            let baseUnit = resolved.baseNutritionUnit
            let ingredient = RecipeIngredientDraft(
                name: resolved.name,
                productID: resolved.id,
                nestedRecipeID: nil,
                amount: defaultAmount(for: resolved),
                unit: baseUnit,
                servingLabel: "",
                productSnapshot: resolved
            )

            await MainActor.run {
                ingredients.append(ingredient)
                pendingIngredientIDs.insert(ingredient.id)
                quantityEditorTarget = AddedIngredientEditorTarget(ingredientID: ingredient.id)
            }
        }
    }

    private func handleRecipeSelection(_ recipe: RecipeSummary) {
        guard recipe.id != recipeID else {
            errorMessage = NSLocalizedString("recipe.editor.self_reference_error", comment: "Nested self recipe error")
            return
        }

        Task {
            let resolved = await catalogService.fetchRecipeSnapshot(id: recipe.id) ?? recipe
            let ingredient = RecipeIngredientDraft(
                name: resolved.title,
                productID: nil,
                nestedRecipeID: resolved.id,
                amount: 1,
                unit: .serving,
                nestedRecipeSnapshot: resolved
            )

            await MainActor.run {
                ingredients.append(ingredient)
                pendingIngredientIDs.insert(ingredient.id)
                quantityEditorTarget = AddedIngredientEditorTarget(ingredientID: ingredient.id)
            }
        }
    }

    private func localizedCatalogText(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "Food catalog lookup localized text")
    }

    private func productSummaryText(_ product: ProductSummary) -> String {
        let nutritionText = "\(product.caloriesPer100g) \(productNutritionSummaryUnit) / 100 \(product.per100UnitShortTitle) · \(proteinShortTitle) \(product.proteinPer100g) · \(fatShortTitle) \(product.fatPer100g) · \(carbsShortTitle) \(product.carbsPer100g)"
        if product.brand.isEmpty {
            return nutritionText
        }
        return "\(product.brand) · \(nutritionText)"
    }

    private func recipeSummaryText(_ recipe: RecipeSummary) -> String {
        let per100gNutrition = recipe.resolvedNutritionPer100g
        var components = [
            "\(recipe.caloriesPerServing) \(productNutritionSummaryUnit) · \(perServingTitle) · \(proteinShortTitle) \(recipe.proteinPerServing) · \(fatShortTitle) \(recipe.fatPerServing) · \(carbsShortTitle) \(recipe.carbsPerServing)"
        ]
        if per100gNutrition != .zero {
            components.append(
                "\(per100gNutrition.calories) \(productNutritionSummaryUnit) · \(nutritionPer100UnitTitle) · \(proteinShortTitle) \(per100gNutrition.protein) · \(fatShortTitle) \(per100gNutrition.fat) · \(carbsShortTitle) \(per100gNutrition.carbs)"
            )
        }
        return components.joined(separator: " · ")
    }

    private func scheduleRemoteSearch() {
        searchTask?.cancel()

        let query = normalizedQuery
        guard !query.isEmpty else {
            remoteProducts = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            let remote = await searchService.searchProducts(query: query, limit: 30, offset: 0)
            guard !Task.isCancelled else { return }

            let mapped = remote.map(mapRemoteProduct)
            await MainActor.run {
                remoteProducts = mapped
            }
        }
    }

    private func mapRemoteProduct(_ result: Search_ProductSearchResult) -> ProductSummary {
        if let id = UUID(uuidString: result.id), let existing = catalogService.productSummary(id: id) {
            return existing
        }

        return ProductSummary(
            id: UUID(uuidString: result.id) ?? UUID(),
            name: result.name,
            brand: result.brand,
            barcode: result.barcode,
            caloriesPer100g: Int(result.caloriesPer100G.rounded()),
            proteinPer100g: Int(result.proteinPer100G.rounded()),
            fatPer100g: Int(result.fatPer100G.rounded()),
            carbsPer100g: Int(result.carbsPer100G.rounded()),
            details: result.description_p
        )
    }
}

struct FoodShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let payload: FoodSharePayload

    private var isRecipeShare: Bool {
        payload.isRecipeShare
    }

    private var resolvedShareURL: String {
        payload.resolvedShareLink ?? payload.shareCode
    }

    private var previewShareURL: URL? {
        payload.resolvedShareURL
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(payload.title)
                        .font(.title2.weight(.bold))
                    Text(LocalizedStringKey(isRecipeShare ? "meal.share.recipe_message" : "meal.share.message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !isRecipeShare {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("meal.share.code")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(payload.shareCode)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.platformSecondarySystemBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                            .onTapGesture {
                                PlatformSupport.copyToClipboard(payload.shareCode)
                            }

                        Text("meal.share.code_hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("meal.share.link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(resolvedShareURL)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.platformSecondarySystemBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                }

                HStack(spacing: 12) {
                    Button("common.copy") {
                        PlatformSupport.copyToClipboard(resolvedShareURL)
                    }
                    .buttonStyle(.bordered)

                    // A ShareLink, not a button raising a share sheet: this
                    // view is itself a sheet, and SwiftUI presents one at a
                    // time — the second was dropped and nothing happened.
                    if let previewShareURL {
                        ShareLink(item: previewShareURL, subject: Text(payload.title.isEmpty ? "" : payload.title)) {
                            Label("common.share", systemImage: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("common.share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    PressableIconButton(action: { dismiss() }) {
                        Label("common.close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 48, height: 48)
                    }
                }
            }
        }
    }

}

final class ProductEditorState: ObservableObject, Identifiable {
    let id = UUID()
    let initialDraft: ProductDraft
    let initialBarcode: String
    let initialBarcodeFormat: String
    let submissionContext: ProductSubmissionSummary?
    let visibilityOptions: [FoodVisibilityOption]
    @Published var draft: ProductDraft
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var servingAmountText: String
    @Published var caloriesText: String
    @Published var proteinText: String
    @Published var fatText: String
    @Published var saturatedFatText: String
    @Published var unsaturatedFatText: String
    @Published var carbsText: String
    @Published var fiberText: String
    @Published var sugarText: String
    @Published var sodiumText: String

    // Submission-only fields (used when visibility == .publicVisibility)
    @Published var barcode: String = ""
    @Published var barcodeFormat: String = "EAN13"
    @Published var nutritionImage: UIImage?
    @Published var ocrCalories: String = ""
    @Published var ocrProtein: String = ""
    @Published var ocrFat: String = ""
    @Published var ocrCarbs: String = ""
    @Published var ocrRawText: String = ""
    @Published var isRecognizing = false

    init(
        draft: ProductDraft,
        submissionContext: ProductSubmissionSummary? = nil,
        visibilityOptions: [FoodVisibilityOption] = [.privateVisibility, .friendsVisibility, .publicVisibility]
    ) {
        self.submissionContext = submissionContext
        self.visibilityOptions = visibilityOptions
        let draftBarcode = draft.barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let reviewBarcode = submissionContext?.barcode.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedBarcode = reviewBarcode.isEmpty ? draftBarcode : reviewBarcode
        var resolvedDraft = Self.normalizedDraftForEditor(draft)
        resolvedDraft.barcode = resolvedBarcode
        self.initialDraft = resolvedDraft
        self.initialBarcode = resolvedBarcode
        let initialFormat = submissionContext?.barcodeFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        self.initialBarcodeFormat = initialFormat?.isEmpty == false ? initialFormat! : "EAN13"
        self.draft = resolvedDraft
        self.servingAmountText = Self.decimalFieldText(resolvedDraft.servingAmount)
        self.caloriesText = Self.decimalFieldText(resolvedDraft.caloriesPer100g)
        self.proteinText = Self.decimalFieldText(resolvedDraft.proteinPer100g)
        self.fatText = Self.decimalFieldText(resolvedDraft.fatPer100g)
        self.saturatedFatText = Self.decimalFieldText(resolvedDraft.saturatedFatPer100g)
        self.unsaturatedFatText = Self.decimalFieldText(resolvedDraft.unsaturatedFatPer100g)
        self.carbsText = Self.decimalFieldText(resolvedDraft.carbsPer100g)
        self.fiberText = Self.decimalFieldText(resolvedDraft.fiberPer100g)
        self.sugarText = Self.decimalFieldText(resolvedDraft.sugarPer100g)
        self.sodiumText = Self.decimalFieldText(resolvedDraft.sodiumMgPer100g)
        self.barcode = self.initialBarcode
        self.barcodeFormat = self.initialBarcodeFormat
    }

    private static func normalizedDraftForEditor(_ draft: ProductDraft) -> ProductDraft {
        var normalized = draft
        if let explicitServing = normalized.servingOptions.first(where: { $0.unit == .serving }) {
            let metricUnit = explicitServing.effectiveMetricUnit
            normalized.servingUnit = metricUnit == .serving ? .grams : metricUnit
            normalized.servingAmount = max(explicitServing.effectiveMetricAmount, 1)
        } else if let explicitMetric = normalized.servingOptions.first(where: {
            abs($0.effectiveMetricAmount - 100) >= 0.0001
                || $0.effectiveMetricUnit != normalized.servingUnit
        }) {
            let metricUnit = explicitMetric.effectiveMetricUnit
            normalized.servingUnit = metricUnit == .serving ? .grams : metricUnit
            normalized.servingAmount = max(explicitMetric.effectiveMetricAmount, 1)
        }
        if normalized.servingUnit == .serving {
            let fallbackUnit = normalized.servingOptions.first?.effectiveMetricUnit ?? .grams
            normalized.servingUnit = fallbackUnit == .serving ? .grams : fallbackUnit
            normalized.servingAmount = max(normalized.servingAmount, 100)
        }
        if normalized.servingAmount <= 0 {
            normalized.servingAmount = 100
        }
        normalized.servingOptions = deduplicatedServingOptions(
            normalized.servingOptions,
            baseUnit: normalized.servingUnit,
            baselineAmount: normalized.servingAmount
        )
        return normalized
    }

    private static func deduplicatedServingOptions(
        _ options: [ProductServingOption],
        baseUnit: MealItemUnit,
        baselineAmount: Double
    ) -> [ProductServingOption] {
        let servingOptionsCount = options.filter { $0.unit == .serving }.count
        var seen = Set<String>()
        var deduplicated: [ProductServingOption] = []

        for option in options {
            let trimmedLabel = option.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedMetricAmount = option.metricAmount > 0 ? option.metricAmount : max(option.amount, 1)

            let isLegacyBaselineServing = option.unit == .serving
                && servingOptionsCount > 1
                && trimmedLabel.isEmpty
                && option.metricUnit == baseUnit
                && abs(normalizedMetricAmount - baselineAmount) < 0.0001

            if isLegacyBaselineServing {
                continue
            }

            let key = [
                String(describing: option.unit),
                trimmedLabel.lowercased(),
                String(format: "%.4f", max(option.amount, 0)),
                String(describing: option.metricUnit),
                String(format: "%.4f", max(normalizedMetricAmount, 0))
            ].joined(separator: "|")

            if seen.insert(key).inserted {
                deduplicated.append(option)
            }
        }

        return deduplicated
    }

    static func integerFieldText(_ value: Int) -> String {
        value == 0 ? "" : String(value)
    }

    static func decimalFieldText(_ value: Double) -> String {
        value == 0 ? "" : formatFoodAmount(value)
    }
}

struct ProductEditorSheet: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @EnvironmentObject private var userService: UserService
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var state: ProductEditorState
    @FocusState private var focusedField: ProductEditorField?

    private enum ProductEditorField: Hashable {
        case servingAmount
        case calories
        case protein
        case fat
        case saturatedFat
        case unsaturatedFat
        case carbs
        case fiber
        case sugar
        case sodium
    }

    init(state: ProductEditorState) {
        self._state = ObservedObject(wrappedValue: state)
    }

    private var hasPendingSubmission: Bool {
        state.submissionContext?.status == .pending
    }

    private var hasExistingSubmissionPhoto: Bool {
        !(state.submissionContext?.nutritionPhotoKey.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    private var isAdminUser: Bool {
        userService.currentUser?.role == .admin
    }

    private var requiresNutritionPhotoForNewProduct: Bool {
        state.draft.productID == nil && !isAdminUser
    }

    private var shouldShowNutritionPhotoSection: Bool {
        state.draft.visibility == .publicVisibility || requiresNutritionPhotoForNewProduct
    }

    private var shouldShowBarcodeRow: Bool {
        state.draft.visibility == .publicVisibility
    }

    private var shouldShowProductReviewSection: Bool {
        shouldShowBarcodeRow || shouldShowNutritionPhotoSection
    }

    private var shouldShowVisibilityPicker: Bool {
        state.visibilityOptions.count > 1
    }

    private var existingReviewNutritionPhotoURL: URL? {
        guard state.nutritionImage == nil else { return nil }
        let rawValue = state.submissionContext?.nutritionPhotoURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawValue.isEmpty else { return nil }
        return URL(string: rawValue)
    }

    private var hasChanges: Bool {
        let resolved = resolvedDraftForSave()
        let trimmedBarcode = state.barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved != state.initialDraft
            || trimmedBarcode != state.initialBarcode
            || state.barcodeFormat != state.initialBarcodeFormat
            || state.nutritionImage != nil
    }

    private var canSave: Bool {
        let resolved = resolvedDraftForSave()
        return !resolved.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasChanges
    }

    @State private var showBarcodeScanner = false
    @State private var showPhotoSourceDialog = false
    @State private var photoPickerSource: UIImagePickerController.SourceType?
    @State private var servingEditorTarget: ProductServingEditorTarget?

    private var productBaseUnitOptions: [MealItemUnit] {
        [.grams, .milliliters]
    }

    private var nutritionBaseUnitShortTitle: String {
        state.draft.servingUnit.shortTitle
    }

    private var nutritionPer100SectionTitle: String {
        "100 \(nutritionBaseUnitShortTitle)"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                    identityCard
                    servingOptionsCard
                    nutritionFactsCard
                }
                .eoCardInsets()
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .dismissesKeyboardInteractively()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .eoPageBackground()
            .overlay {
                if state.isSaving {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .eoSheetChrome(
                "product.editor.sheet_title",
                trailing: .confirm(isEnabled: canSave && !state.isSaving) {
                    saveTapped()
                },
                onClose: { dismiss() }
            )
        }
        .alert("product.editor.save_error.title", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { Task { @MainActor in state.errorMessage = nil } } }
        )) {
            Button("common.ok", role: .cancel) {
                Task { @MainActor in
                    state.errorMessage = nil
                }
            }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .sheet(isPresented: $showBarcodeScanner) {
            BarcodeScannerSheet { code in
                state.barcode = code
            }
        }
        .sheet(item: $servingEditorTarget) { target in
            if let index = state.draft.servingOptions.firstIndex(where: { $0.id == target.id }) {
                ProductServingOptionEditorSheet(
                    option: state.draft.servingOptions[index],
                    baseUnit: state.draft.servingUnit,
                    onSave: { option in
                        state.draft.servingOptions[index] = option
                        state.objectWillChange.send()
                        servingEditorTarget = nil
                    },
                    onCancel: { servingEditorTarget = nil },
                    onDelete: {
                        removeServingOption(id: target.id)
                        servingEditorTarget = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showPhotoSourceDialog) {
            PhotoSourcePickerSheet(
                onCamera: {
                    showPhotoSourceDialog = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        photoPickerSource = .camera
                    }
                },
                onLibrary: {
                    showPhotoSourceDialog = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        photoPickerSource = .photoLibrary
                    }
                },
                onCancel: { showPhotoSourceDialog = false }
            )
            .presentationDetents([.height(220)])
        }
        .sheet(item: photoPickerSourceBinding) { source in
            ImagePicker(
                sourceType: source.value,
                onPick: { image in
                    photoPickerSource = nil
                    Task { await handlePickedImage(image) }
                },
                onCancel: { photoPickerSource = nil }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Cards (mock-up layout)

    private var identityCard: some View {
        EOCard {
            EOTextFieldRow("product.editor.name", text: $state.draft.name)
            EORowSeparator()

            EOTextFieldRow("product.editor.brand", text: $state.draft.brand)
            EORowSeparator()

            EOListRow(title: Text("addmeal.unit")) {
                Menu {
                    Picker("", selection: servingUnitBinding) {
                        ForEach(productBaseUnitOptions) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .labelsHidden()
                } label: {
                    HStack(spacing: 6) {
                        Text(state.draft.servingUnit.title)
                            .font(EOTheme.Typography.rowValue)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
            }
            EORowSeparator()

            Button {
                showBarcodeScanner = true
            } label: {
                EOListRow(
                    title: Text("barcode.scanner.title"),
                    accessory: .symbol(name: "barcode.viewfinder", color: EOTheme.Palette.accent)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var servingOptionsCard: some View {
        EOCard {
            Button {
                addServingOption()
                if let index = editableServingOptionIndices.last {
                    servingEditorTarget = ProductServingEditorTarget(id: state.draft.servingOptions[index].id)
                }
            } label: {
                EOListRow(
                    title: Text("product.editor.serving_option.add"),
                    accessory: .symbol(name: "plus", color: EOTheme.Palette.accent)
                )
            }
            .buttonStyle(.plain)

            ForEach(editableServingOptionIndices, id: \.self) { index in
                EORowSeparator()

                Button {
                    servingEditorTarget = ProductServingEditorTarget(id: state.draft.servingOptions[index].id)
                } label: {
                    EOListRow(
                        title: Text(verbatim: state.draft.servingOptions[index].displayTitle),
                        subtitle: Text(verbatim: state.draft.servingOptions[index].metricDescription ?? "-"),
                        accessory: .valueChevron(Text("common.edit"))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var nutritionFactsCard: some View {
        EOCard {
            Text("nutrition.facts.title")
                .font(EOTheme.Typography.rowTitle)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, EOTheme.Metrics.cardInset)
                .padding(.vertical, EOTheme.Metrics.rowVerticalPadding)
                .frame(minHeight: EOTheme.Metrics.rowMinHeight)
            EORowSeparator()

            productNutritionEditorCard
        }
    }

    private var photoPickerSourceBinding: Binding<IdentifiedSource?> {
        Binding(
            get: { photoPickerSource.map(IdentifiedSource.init(value:)) },
            set: { newValue in photoPickerSource = newValue?.value }
        )
    }

    private struct IdentifiedSource: Identifiable {
        let value: UIImagePickerController.SourceType
        var id: Int { value.rawValue }
    }

    private func handlePickedImage(_ image: UIImage) async {
        await MainActor.run { state.nutritionImage = image }
        await runOCR(on: image)
    }

    private func saveTapped() {
        state.isSaving = true
        let draftForSave = resolvedDraftForSave()
        Task {
            let saved = await catalogService.saveProduct(draftForSave)
            await MainActor.run {
                state.isSaving = false
                if saved != nil {
                    dismiss()
                } else {
                    state.errorMessage = catalogService.lastErrorMessage ?? NSLocalizedString("food.service.generic_error", comment: "Generic food service error")
                }
            }
        }
    }

    private func loadPickedImage(_ image: UIImage?) async {
        guard let image else { return }
        await MainActor.run { state.nutritionImage = image }
        await runOCR(on: image)
    }

    private func runOCR(on image: UIImage) async {
        await MainActor.run { state.isRecognizing = true }
        defer { Task { @MainActor in state.isRecognizing = false } }
        guard let cgImage = image.cgImage else { return }
        let recognizedText = await Task.detached { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["ru-RU", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                return lines.joined(separator: "\n")
            } catch {
                return ""
            }
        }.value
        let parsed = NutritionLabelParser.parse(text: recognizedText)
        await MainActor.run {
            state.ocrRawText = recognizedText
            if let v = parsed.calories {
                state.ocrCalories = Self.formatOcr(v)
                if state.caloriesText.isEmpty { state.caloriesText = Self.formatOcr(v) }
            }
            if let v = parsed.protein {
                state.ocrProtein = Self.formatOcr(v)
                if state.proteinText.isEmpty { state.proteinText = Self.formatOcr(v) }
            }
            if let v = parsed.fat {
                state.ocrFat = Self.formatOcr(v)
                if state.fatText.isEmpty { state.fatText = Self.formatOcr(v) }
            }
            if let v = parsed.carbs {
                state.ocrCarbs = Self.formatOcr(v)
                if state.carbsText.isEmpty { state.carbsText = Self.formatOcr(v) }
            }
        }
    }

    private static func formatOcr(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    private static func parseDouble(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private static func detectBarcodeFormat(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        switch digits.count {
        case 8: return "EAN8"
        case 12: return "UPCA"
        case 13: return "EAN13"
        case 6: return "UPCE"
        default: return "EAN13"
        }
    }

    private func productEditorSectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, -14)
    }

    @ViewBuilder
    private var productReviewSection: some View {
        if shouldShowProductReviewSection {
            Section {
                if shouldShowBarcodeRow {
                    if shouldShowNutritionPhotoSection {
                        barcodeInputRowWithSeparator
                    } else {
                        barcodeInputRow
                    }
                }

                if shouldShowNutritionPhotoSection {
                    nutritionPhotoRows
                }
            } header: {
                productEditorSectionTitle(productReviewSectionTitle)
            }
        }
    }

    private var productReviewSectionTitle: LocalizedStringKey {
        if shouldShowBarcodeRow {
            return "submit_review.section.barcode"
        }
        return "submit_review.section.photo"
    }

    private var barcodeInputRow: some View {
        HStack {
            TextField("submit_review.barcode.placeholder", text: $state.barcode)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                showBarcodeScanner = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .imageScale(.large)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }

    private var barcodeInputRowWithSeparator: some View {
        barcodeInputRow
            .listRowSeparator(.visible, edges: .bottom)
            .listRowSeparatorTint(Color.primary.opacity(0.12))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                dimensions.width
            }
    }

    @ViewBuilder
    private var nutritionPhotoRows: some View {
        if let nutritionImage = state.nutritionImage {
            Image(uiImage: nutritionImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if let existingReviewNutritionPhotoURL {
            AsyncImage(url: existingReviewNutritionPhotoURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .tint(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                case .failure:
                    EmptyView()
                @unknown default:
                    EmptyView()
                }
            }
        }

        Button {
            showPhotoSourceDialog = true
        } label: {
            Label(state.nutritionImage == nil ? "submit_review.photo.choose" : "submit_review.photo.replace", systemImage: "photo.on.rectangle")
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)

        if state.isRecognizing {
            HStack {
                ProgressView()
                    .tint(.secondary)
                Text("submit_review.ocr.running")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var productNutritionEditorCard: some View {
        VStack(spacing: 0) {
            productNutritionStepper(
                titleKey: "addmeal.total.calories",
                text: $state.caloriesText,
                field: .calories,
                unit: NSLocalizedString("diary.kcal", comment: "Calories suffix"),
                step: 10
            )
            EORowSeparator()
            productNutritionStepper(
                titleKey: "addmeal.total.protein",
                text: $state.proteinText,
                field: .protein,
                unit: NSLocalizedString("unit.grams.short", comment: "Short grams unit"),
                step: 1
            )
            EORowSeparator()
            productNutritionStepper(
                titleKey: "addmeal.total.carbs",
                text: $state.carbsText,
                field: .carbs,
                unit: NSLocalizedString("unit.grams.short", comment: "Short grams unit"),
                step: 1
            )
            EORowSeparator()
            productNutritionStepper(
                titleKey: "addmeal.total.fat",
                text: $state.fatText,
                field: .fat,
                unit: NSLocalizedString("unit.grams.short", comment: "Short grams unit"),
                step: 1
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mock-up layout: "Calories, kcal" on the left, then the value and the
    /// `−  |  +` capsule.
    ///
    /// The number is a field rather than part of the title. A label off a packet
    /// is read, not arrived at — 247 kcal in steps of ten is not reachable at
    /// all — so the steppers stay for rounding and the keypad does the rest. The
    /// unit is named in the label so the four figures line up in a column.
    ///
    /// Written as its own row instead of reusing `EOStepperFieldRow`, which is
    /// integral: these values are decimal and are already held as text, so the
    /// field binds straight to the state and there is no draft to keep in step.
    private func productNutritionStepper(
        titleKey: String,
        text: Binding<String>,
        field: ProductEditorField,
        unit: String,
        step: Double
    ) -> some View {
        let value = Self.resolvedDoubleValue(from: text.wrappedValue)

        let label = EOStepperFieldRow.title(
            NSLocalizedString(titleKey, comment: "Nutrition field"),
            unit: unit
        )

        return EOListRow(title: Text(verbatim: label)) {
            HStack(spacing: 10) {
                // Zero is stored as an empty string by `decimalFieldText`, so
                // the prompt shows on its own and there is no "0" to delete
                // before typing.
                TextField("", text: text, prompt: Text(verbatim: "0").foregroundStyle(.secondary))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(EOTheme.Typography.rowValue.monospacedDigit())
                    .focused($focusedField, equals: field)
                    .frame(maxWidth: 96, alignment: .trailing)
                    .accessibilityLabel(Text(verbatim: label))

                EOStepperControl(
                    canDecrement: value > 0,
                    canIncrement: value < 100_000,
                    onDecrement: {
                        text.wrappedValue = ProductEditorState.decimalFieldText(max(0, value - step))
                    },
                    onIncrement: {
                        text.wrappedValue = ProductEditorState.decimalFieldText(min(100_000, value + step))
                    }
                )
            }
        }
    }

    private func editableNutritionRow(
        title: String,
        text: Binding<String>,
        field: ProductEditorField,
        unit: String,
        isIndented: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(title) (\(unit))")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.leading, isIndented ? 14 : 0)

            Spacer(minLength: 0)

            TextField(
                NSLocalizedString("common.zero_placeholder", comment: "Zero placeholder"),
                text: decimalFieldBinding(for: text)
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: field)
            .font(.body.weight(.semibold).monospacedDigit())
            .frame(minWidth: 52, maxWidth: 90, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = field
        }
        .padding(.vertical, 10)
    }

    private var productNutritionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    @ViewBuilder
    private func nutritionIntegerField(title: String, text: Binding<String>, field: ProductEditorField) -> some View {
        numericInputRow(title: title, field: field) {
            TextField(
                NSLocalizedString("common.zero_placeholder", comment: "Zero placeholder"),
                text: integerFieldBinding(for: text)
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: field)
        }
    }

    @ViewBuilder
    private func nutritionDecimalField(title: String, text: Binding<String>, field: ProductEditorField) -> some View {
        numericInputRow(title: title, field: field) {
            TextField(
                NSLocalizedString("common.zero_placeholder", comment: "Zero placeholder"),
                text: decimalFieldBinding(for: text)
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: field)
        }
    }

    @ViewBuilder
    private func numericInputRow<Content: View>(title: String, field: ProductEditorField, @ViewBuilder input: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            input()
                .frame(maxWidth: 96)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = field
        }
    }

    private var visibilityBinding: Binding<FoodVisibilityOption> {
        Binding(
            get: { state.draft.visibility },
            set: { newValue in
                state.draft.visibility = newValue
                state.objectWillChange.send()
            }
        )
    }

    private var servingUnitBinding: Binding<MealItemUnit> {
        Binding(
            get: { state.draft.servingUnit },
            set: { newValue in
                guard state.draft.servingUnit != newValue else { return }
                state.draft.servingUnit = newValue
                for index in state.draft.servingOptions.indices {
                    if state.draft.servingOptions[index].unit == .serving {
                        state.draft.servingOptions[index].metricUnit = newValue
                    }
                }
                state.servingAmountText = ProductEditorState.decimalFieldText(defaultServingAmount(for: newValue))
                state.objectWillChange.send()
            }
        )
    }

    private var editableServingOptionIndices: [Int] {
        state.draft.servingOptions.indices
            .filter { state.draft.servingOptions[$0].unit == .serving }
            .sorted {
                let lhs = state.draft.servingOptions[$0]
                let rhs = state.draft.servingOptions[$1]
                if lhs.sortOrder == rhs.sortOrder {
                    return $0 < $1
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private func servingOptionLabelBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard state.draft.servingOptions.indices.contains(index) else { return "" }
                return state.draft.servingOptions[index].label
            },
            set: { newValue in
                guard state.draft.servingOptions.indices.contains(index) else { return }
                state.draft.servingOptions[index].label = newValue
                state.objectWillChange.send()
            }
        )
    }

    private func servingOptionAmountBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard state.draft.servingOptions.indices.contains(index) else { return "" }
                let option = state.draft.servingOptions[index]
                if option.metricAmount == 0 { return "0" }
                return ProductEditorState.decimalFieldText(option.metricAmount)
            },
            set: { newValue in
                guard state.draft.servingOptions.indices.contains(index) else { return }
                let sanitized = Self.sanitizedDecimalText(newValue)
                let parsed = Self.resolvedDoubleValue(from: sanitized)
                let resolved = parsed > 0 ? parsed : 1
                state.draft.servingOptions[index].amount = 1
                state.draft.servingOptions[index].unit = .serving
                state.draft.servingOptions[index].metricAmount = resolved
                state.draft.servingOptions[index].metricUnit = state.draft.servingUnit
                state.objectWillChange.send()
            }
        )
    }

    /// Drops a serving option from the draft. Items already logged with it keep
    /// their own copy of the label, so removing it only affects future picks.
    private func removeServingOption(id: String) {
        var updated = state.draft
        updated.servingOptions.removeAll { $0.id == id }
        state.draft = updated
        state.objectWillChange.send()
    }

    private func addServingOption() {
        let nextSortOrder = (state.draft.servingOptions.map(\.sortOrder).max() ?? -1) + 1
        let defaultLabel = String(
            format: NSLocalizedString(
                "product.editor.serving_option.default_name_format",
                value: "Portion %d",
                comment: "Default serving option name"
            ),
            editableServingOptionIndices.count + 1
        )
        var updated = state.draft
        updated.servingOptions.append(
            ProductServingOption(
                id: "draft-serving-option-new-\(UUID().uuidString)",
                label: defaultLabel,
                amount: 1,
                unit: .serving,
                metricAmount: 0,
                metricUnit: state.draft.servingUnit,
                sortOrder: nextSortOrder
            )
        )
        state.draft = updated
    }

    private func removeServingOption(at index: Int) {
        guard state.draft.servingOptions.indices.contains(index) else { return }
        var updated = state.draft
        updated.servingOptions.remove(at: index)
        for itemIndex in updated.servingOptions.indices {
            if updated.servingOptions[itemIndex].sortOrder < 0 {
                updated.servingOptions[itemIndex].sortOrder = itemIndex
            }
        }
        state.draft = updated
    }

    private func defaultServingAmount(for unit: MealItemUnit) -> Double {
        switch unit {
        case .grams, .milliliters:
            return 100
        case .serving:
            return 100
        }
    }

    private func resolvedDraftForSave() -> ProductDraft {
        var resolved = state.draft
        let enteredServingAmount = Self.resolvedDoubleValue(from: state.servingAmountText)
        let servingAmount = enteredServingAmount > 0 ? enteredServingAmount : 100
        resolved.servingAmount = servingAmount
        resolved.caloriesPer100g = Self.resolvedDoubleValue(from: state.caloriesText)
        resolved.proteinPer100g = Self.resolvedDoubleValue(from: state.proteinText)
        resolved.fatPer100g = Self.resolvedDoubleValue(from: state.fatText)
        resolved.saturatedFatPer100g = Self.resolvedDoubleValue(from: state.saturatedFatText)
        resolved.unsaturatedFatPer100g = Self.resolvedDoubleValue(from: state.unsaturatedFatText)
        resolved.carbsPer100g = Self.resolvedDoubleValue(from: state.carbsText)
        resolved.fiberPer100g = Self.resolvedDoubleValue(from: state.fiberText)
        resolved.sugarPer100g = Self.resolvedDoubleValue(from: state.sugarText)
        resolved.sodiumMgPer100g = Self.resolvedDoubleValue(from: state.sodiumText)
        resolved.barcode = state.barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved
    }


    private func integerFieldBinding(for text: Binding<String>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { newValue in
                text.wrappedValue = Self.sanitizedIntegerText(newValue)
            }
        )
    }

    private func decimalFieldBinding(for text: Binding<String>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { newValue in
                text.wrappedValue = Self.sanitizedDecimalText(newValue)
            }
        )
    }

    private static func resolvedIntegerValue(from text: String) -> Int {
        Int(sanitizedIntegerText(text)) ?? 0
    }

    private static func resolvedDoubleValue(from text: String) -> Double {
        let sanitized = sanitizedDecimalText(text)
        guard !sanitized.isEmpty else { return 0 }

        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: sanitized) {
            return number.doubleValue
        }

        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let normalized = sanitized
            .replacingOccurrences(of: decimalSeparator, with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix(".") {
            return Double("0\(normalized)") ?? 0
        }
        return Double(normalized) ?? 0
    }

    private static func sanitizedIntegerText(_ text: String) -> String {
        String(text.filter(\.isNumber))
    }

    private static func sanitizedDecimalText(_ text: String) -> String {
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
}

private struct ProductServingEditorTarget: Identifiable {
    let id: String
}

private struct ProductServingOptionEditorSheet: View {
    let baseUnit: MealItemUnit
    let onSave: (ProductServingOption) -> Void
    let onCancel: () -> Void
    /// `nil` while the option is still being created — nothing to delete yet.
    let onDelete: (() -> Void)?

    @State private var option: ProductServingOption

    init(
        option: ProductServingOption,
        baseUnit: MealItemUnit,
        onSave: @escaping (ProductServingOption) -> Void,
        onCancel: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        var normalized = option
        normalized.amount = 1
        normalized.unit = .serving
        normalized.metricAmount = max(option.metricAmount, 1)
        normalized.metricUnit = baseUnit
        _option = State(initialValue: normalized)
        self.baseUnit = baseUnit
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
    }

    private var trimmedLabel: String {
        option.label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: EOTheme.Metrics.sectionSpacing) {
                EOCard {
                    EOTextFieldRow("product.editor.serving_option.label", text: $option.label)
                    EORowSeparator()

                    EOStepperRow(
                        title: Text(
                            verbatim: "\(NSLocalizedString("addmeal.amount", comment: "Amount")): \(formatFoodAmount(option.metricAmount)) \(baseUnit.shortTitle)"
                        ),
                        canDecrement: option.metricAmount > 1,
                        canIncrement: option.metricAmount < 10_000,
                        onDecrement: { option.metricAmount = max(1, option.metricAmount - 1) },
                        onIncrement: { option.metricAmount = min(10_000, option.metricAmount + 1) }
                    )
                }

                if onDelete != nil {
                    EOCard {
                        EOInlineActionRow("product.editor.serving_option.remove", tint: EOTheme.Palette.destructive) {
                            onDelete?()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .eoCardInsets()
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .eoPageBackground()
            .eoSheetChrome(
                "product.editor.section.serving",
                trailing: .confirm(isEnabled: !trimmedLabel.isEmpty) {
                    onSave(option)
                },
                onClose: onCancel
            )
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct RecipeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: RecipeEditorDraftStore
    @State private var isSaving = false
    @State private var errorMessage: String?

    let catalogService: FoodCatalogService

    private var draft: RecipeDraft {
        get { store.draft }
        nonmutating set { store.draft = newValue }
    }

    private var stepFields: [RecipeStepField] {
        get { store.stepFields }
        nonmutating set { store.stepFields = newValue }
    }

    private var initialDraft: RecipeDraft {
        store.initialDraft
    }

    private var nutritionPreview: RecipeNutritionPreview {
        catalogService.computedNutrition(for: draft)
    }

    private var effectiveOutputWeight: Double {
        catalogService.effectiveOutputWeight(for: draft)
    }

    private var ingredientWeightEstimate: Double {
        catalogService.ingredientWeightEstimate(for: draft)
    }

    private var portionWeight: Double {
        let servings = max(draft.servings, 1)
        guard effectiveOutputWeight > 0 else { return 0 }
        return effectiveOutputWeight / Double(servings)
    }

    private var hasInvalidOutputWeight: Bool {
        draft.outputWeightGrams > 0
            && ingredientWeightEstimate > 0
            && draft.outputWeightGrams > ingredientWeightEstimate
    }

    private var stepPlaceholderText: String {
        NSLocalizedString(
            "recipe.editor.step_placeholder",
            tableName: nil,
            bundle: .main,
            value: "Step description",
            comment: "Recipe step field placeholder"
        )
    }

    private var addStepTitle: String {
        NSLocalizedString(
            "recipe.editor.add_step",
            tableName: nil,
            bundle: .main,
            value: "Add step",
            comment: "Add recipe step button title"
        )
    }

    private var hasSelectedIngredientsForCalculation: Bool {
        draft.ingredients.contains { $0.productID != nil || $0.nestedRecipeID != nil }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasSelectedIngredientsForCalculation
            && !hasInvalidOutputWeight
            && hasChanges
    }

    private var categoryBinding: Binding<RecipeCategory> {
        Binding(
            get: { RecipeCategory(rawString: draft.category) },
            set: { newValue in
                var updated = store.draft
                updated.category = newValue.rawValue
                store.draft = updated
            }
        )
    }

    private var hasChanges: Bool {
        draft != initialDraft || stepFields.map(\.text) != initialDraft.steps
    }

    private var outputWeightText: Binding<String> {
        Binding(
            get: {
                if draft.outputWeightGrams <= 0 {
                    return ""
                }
                let rounded = draft.outputWeightGrams.rounded()
                if abs(draft.outputWeightGrams - rounded) < 0.0001 {
                    return String(Int(rounded))
                }
                return String(draft.outputWeightGrams)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                draft.outputWeightGrams = Double(trimmed) ?? 0
            }
        )
    }

    private var gramsShortTitle: String {
        NSLocalizedString("unit.grams.short", comment: "Grams unit short title")
    }

    private var nutritionTotalTitle: String {
        NSLocalizedString("recipe.editor.nutrition_total", comment: "Total nutrition title")
    }

    private func stepFieldBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                store.stepFields.first(where: { $0.id == id })?.text ?? ""
            },
            set: { newValue in
                guard let index = store.stepFields.firstIndex(where: { $0.id == id }) else { return }
                store.stepFields[index].text = newValue
            }
        )
    }

    private func removeStepField(withID id: UUID) {
        guard let index = store.stepFields.firstIndex(where: { $0.id == id }) else { return }
        store.stepFields.remove(at: index)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                    EOCard {
                        EOTextFieldRow("recipe.editor.name", text: $store.draft.title)
                        EORowSeparator()
                        servingsControl
                    }

                    EOCard {
                        EOCardHeaderRow("recipe.editor.add_ingredient", systemImage: "magnifyingglass") {
                            store.isIngredientPickerPresented = true
                        }

                        ForEach(Array(draft.ingredients.indices), id: \.self) { index in
                            EORowSeparator()
                            ingredientRow(at: index)
                        }
                    }

                    EOCard {
                        EOCardTitleRow("nutrition.facts.title")
                        EORowSeparator()
                        recipeNutritionFactsCard
                    }
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
                "recipe.editor.sheet_title",
                trailing: .confirm(isEnabled: canSave && !isSaving) {
                    saveRecipe()
                },
                onClose: { dismiss() }
            )
        }
        .onAppear {
            synchronizeIngredientUnits()
            if store.stepFields.isEmpty {
                store.stepFields = [RecipeStepField(text: "")]
            }
        }
        .alert("recipe.editor.save_error_title", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { Task { @MainActor in errorMessage = nil } } }
        )) {
            Button("common.ok", role: .cancel) {
                Task { @MainActor in
                    errorMessage = nil
                }
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $store.isIngredientPickerPresented) {
            RecipeIngredientCatalogLookupSheet(
                title: NSLocalizedString("recipe.editor.pick_ingredient", comment: "Choose ingredient"),
                recipeID: draft.recipeID,
                ingredients: $store.draft.ingredients,
                onDismiss: {
                    synchronizeIngredientUnits()
                }
            )
            .environmentObject(catalogService)
        }
        .sheet(item: $store.ingredientEditorTarget) { target in
            if let ingredientBinding = ingredientBinding(for: target.ingredientID) {
                RecipeIngredientQuantityEditorSheet(
                    ingredient: ingredientBinding,
                    catalogService: catalogService,
                    onDelete: {
                        removeIngredient(withID: target.ingredientID)
                    },
                    onClose: {
                        store.ingredientEditorTarget = nil
                    },
                    usesOwnNavigationContainer: true
                )
            }
        }
    }

    private func saveRecipe() {
        isSaving = true
        Task {
            let saved = await catalogService.saveRecipe(draft)
            await MainActor.run {
                isSaving = false
                if saved != nil {
                    dismiss()
                } else {
                    errorMessage = catalogService.lastErrorMessage
                        ?? NSLocalizedString("food.service.generic_error", comment: "Generic food service error")
                }
            }
        }
    }

    private func displayName(for ingredient: RecipeIngredientDraft) -> String {
        let resolved = catalogService.resolvedName(for: ingredient)
        return resolved.isEmpty ? NSLocalizedString("recipe.editor.new_ingredient", comment: "New ingredient") : resolved
    }

    private func ingredientDescription(for ingredient: RecipeIngredientDraft) -> String {
        if ingredient.productID != nil {
            return NSLocalizedString("products.title", comment: "Product")
        }
        if ingredient.nestedRecipeID != nil {
            return NSLocalizedString("recipes.title", comment: "Recipe")
        }
        return NSLocalizedString("recipe.editor.not_selected", comment: "Not selected")
    }

    @ViewBuilder
    private func ingredientRow(at index: Int) -> some View {
        Button {
            store.ingredientEditorTarget = RecipeIngredientEditorTarget(ingredientID: draft.ingredients[index].id)
        } label: {
            EOListRow(
                title: Text(verbatim: displayName(for: draft.ingredients[index])),
                subtitle: Text(verbatim: ingredientSummary(for: draft.ingredients[index])),
                accessory: .valueChevron(Text("common.edit"))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func amountStepper(value: Binding<String>, onDecrease: @escaping () -> Void, onIncrease: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            PressableIconButton(action: onDecrease) {
                Label("recipe.editor.decrease", systemImage: "minus")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            TextField(text: value) {
                Text("common.zero_placeholder")
            }
                .font(.body.monospacedDigit())
                .multilineTextAlignment(.center)
                .keyboardType(.decimalPad)
                .frame(width: 64)

            PressableIconButton(action: onIncrease) {
                Label("recipe.editor.increase", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    /// Mock-up row: "Portion: 12" on the left, `−  |  +` capsule on the right.
    private var servingsControl: some View {
        EOStepperRow(
            title: Text(
                verbatim: "\(NSLocalizedString("recipe.editor.servings", comment: "Servings")): \(max(draft.servings, 1))"
            ),
            canDecrement: draft.servings > 1,
            onDecrement: { draft.servings = max(1, draft.servings - 1) },
            onIncrement: { draft.servings = max(1, draft.servings) + 1 }
        )
    }

    private var servingsTextBinding: Binding<String> {
        Binding(
            get: { String(max(draft.servings, 1)) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                draft.servings = max(1, Int(digits) ?? 1)
            }
        )
    }

    private func ingredientBinding(for ingredientID: UUID) -> Binding<RecipeIngredientDraft>? {
        guard let currentIngredient = draft.ingredients.first(where: { $0.id == ingredientID }) else { return nil }

        return Binding(
            get: {
                draft.ingredients.first(where: { $0.id == ingredientID }) ?? currentIngredient
            },
            set: { updatedIngredient in
                guard let index = draft.ingredients.firstIndex(where: { $0.id == ingredientID }) else { return }
                draft.ingredients[index] = updatedIngredient
            }
        )
    }

    private func removeIngredient(withID ingredientID: UUID) {
        guard let index = draft.ingredients.firstIndex(where: { $0.id == ingredientID }) else { return }
        draft.ingredients.remove(at: index)
        if store.ingredientEditorTarget?.ingredientID == ingredientID {
            store.ingredientEditorTarget = nil
        }
    }

    private func editorSectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, -14)
    }

    private func amountText(for value: Double) -> String {
        formatFoodAmount(value)
    }

    private func ingredientSummary(for ingredient: RecipeIngredientDraft) -> String {
        let product = catalogService.productSummary(for: ingredient)
        let amount = displayFoodQuantityText(amount: ingredient.amount, unit: ingredient.unit, servingLabel: ingredient.servingLabel, product: product)
        let source = ingredientDescription(for: ingredient)
        return "\(amount) · \(source)"
    }

    private func resolvedUnit(for ingredient: RecipeIngredientDraft) -> MealItemUnit {
        if let product = catalogService.productSummary(for: ingredient) {
            return product.servingUnit
        }
        if ingredient.nestedRecipeID != nil {
            return ingredient.unit == .milliliters ? .grams : ingredient.unit
        }
        return ingredient.unit
    }

    private func defaultAmount(for product: ProductSummary) -> Double {
        switch product.servingUnit {
        case .serving:
            return 1
        case .grams, .milliliters:
            return max(product.servingAmount, 1)
        }
    }

    private func synchronizeIngredientUnits() {
        for index in draft.ingredients.indices {
            if let product = catalogService.productSummary(for: draft.ingredients[index]) {
                let resolved = product.actualAmount(
                    for: draft.ingredients[index].amount,
                    unit: draft.ingredients[index].unit,
                    servingLabel: draft.ingredients[index].servingLabel
                )
                draft.ingredients[index].amount = max(resolved.amount, 1)
                draft.ingredients[index].unit = resolved.unit
            } else if draft.ingredients[index].nestedRecipeID != nil {
                if draft.ingredients[index].unit == .milliliters {
                    draft.ingredients[index].unit = .grams
                }
                let minimumAmount = draft.ingredients[index].unit == .serving ? 1.0 : 0.01
                draft.ingredients[index].amount = max(draft.ingredients[index].amount, minimumAmount)
            }
        }
    }

    @ViewBuilder
    private func statRow(title: String, value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.footnote.monospacedDigit())
    }

    private func formattedRecipeWeight(_ value: Double, approximate: Bool = false) -> String {
        let prefix = approximate ? "≈ " : ""
        return prefix + String(format: NSLocalizedString("recipe.grams_value", comment: "Grams value"), Int(value.rounded()))
    }

    private var recipeWeightMetricsCard: some View {
        VStack(spacing: 0) {
            nutritionValueRow(
                title: NSLocalizedString("recipe.editor.total_weight", comment: "Total weight"),
                value: effectiveOutputWeight > 0
                    ? formattedRecipeWeight(effectiveOutputWeight, approximate: draft.outputWeightGrams <= 0)
                    : ""
            )

            nutritionDivider

            nutritionValueRow(
                title: NSLocalizedString("recipe.editor.portion_weight", comment: "Portion weight"),
                value: portionWeight > 0
                    ? formattedRecipeWeight(portionWeight, approximate: true)
                    : ""
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private var recipeNutritionComparisonCard: some View {
        NutritionFactsTableCard(
            leftHeaderTitle: NSLocalizedString("recipe.editor.per_100g", comment: "Per 100g"),
            rightHeaderTitle: NSLocalizedString("recipe.editor.per_serving", comment: "Per serving"),
            leftSummary: nutritionPreview.per100g,
            rightSummary: nutritionPreview.perServing
        )
    }

    private var recipeNutritionFactsCard: some View {
        VStack(spacing: 0) {
            nutritionValueRow(
                title: NSLocalizedString("addmeal.total.calories", comment: "Calories"),
                value: "\(nutritionPreview.perServing.calories) \(NSLocalizedString("diary.kcal", comment: "Kilocalories"))"
            )
            EORowSeparator()
            nutritionValueRow(
                title: NSLocalizedString("addmeal.total.protein", comment: "Protein"),
                value: "\(nutritionPreview.perServing.protein) \(gramsShortTitle)"
            )
            EORowSeparator()
            nutritionValueRow(
                title: NSLocalizedString("addmeal.total.carbs", comment: "Carbohydrates"),
                value: "\(nutritionPreview.perServing.carbs) \(gramsShortTitle)"
            )
            EORowSeparator()
            nutritionValueRow(
                title: NSLocalizedString("addmeal.total.fat", comment: "Fat"),
                value: "\(nutritionPreview.perServing.fat) \(gramsShortTitle)"
            )
        }
    }

    private var nutritionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private func nutritionHeaderRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }

    private func nutritionValueRow(title: String, value: String) -> some View {
        EOListRow(
            title: Text(verbatim: title),
            accessory: .value(Text(verbatim: value))
        )
    }
}

struct RecipeIngredientQuantityEditorSheet: View {
    @Binding var ingredient: RecipeIngredientDraft

    let catalogService: FoodCatalogService
    let onDelete: (() -> Void)?
    let onCancel: (() -> Void)?
    let onConfirm: (() -> Void)?
    let onClose: () -> Void
    let usesOwnNavigationContainer: Bool
    @FocusState private var isAmountFieldFocused: Bool

    init(
        ingredient: Binding<RecipeIngredientDraft>,
        catalogService: FoodCatalogService,
        onDelete: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onConfirm: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        usesOwnNavigationContainer: Bool
    ) {
        self._ingredient = ingredient
        self.catalogService = catalogService
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.onClose = onClose
        self.usesOwnNavigationContainer = usesOwnNavigationContainer
    }

    private var linkedProduct: ProductSummary? {
        catalogService.productSummary(for: ingredient)
    }

    private var linkedRecipe: RecipeSummary? {
        catalogService.recipeSummary(for: ingredient)
    }

    private var selectedServingOption: ProductServingOption? {
        guard let linkedProduct else { return nil }
        let trimmedLabel = ingredient.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return linkedProduct.selectableServingOption(matching: trimmedLabel)
        }
        return nil
    }

    private var productMetricUnits: [MealItemUnit] {
        guard let linkedProduct else { return [] }

        var seen = Set<MealItemUnit>()
        return linkedProduct.resolvedServingOptions.compactMap { option in
            let unit = option.effectiveMetricUnit
            guard unit != .serving, !seen.contains(unit) else { return nil }
            seen.insert(unit)
            return unit
        }
    }

    private var resolvedName: String {
        let name = catalogService.resolvedName(for: ingredient).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? NSLocalizedString("recipe.editor.new_ingredient", comment: "New ingredient") : name
    }

    private var sourceDescription: String {
        if ingredient.productID != nil {
            return NSLocalizedString("products.title", comment: "Product")
        }
        if ingredient.nestedRecipeID != nil {
            return NSLocalizedString("recipes.title", comment: "Recipe")
        }
        return NSLocalizedString("recipe.editor.not_selected", comment: "Not selected")
    }

    /// Human-readable label of the unit currently selected in the menu.
    private var selectedUnitTitle: String {
        if let option = selectedServingOption {
            return option.pickerTitle
        }
        return resolvedUnit.title
    }

    private var resolvedUnit: MealItemUnit {
        if ingredient.nestedRecipeID != nil {
            return ingredient.unit == .milliliters ? .grams : ingredient.unit
        }
        return ingredient.unit
    }

    private var recipeAllowedUnits: [MealItemUnit] {
        [.serving, .grams]
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
        } else if linkedRecipe != nil {
            ForEach(recipeAllowedUnits) { unit in
                Text(unit.title).tag("recipe_\(unit.rawValue)")
            }
        } else {
            Text(resolvedUnit.title).tag("unit_\(resolvedUnit.rawValue)")
        }
    }

    private var canDecrease: Bool {
        if linkedProduct != nil {
            return displayAmount > minimumDisplayAmount
        }
        return ingredient.amount > minimumAmount(for: resolvedUnit)
    }

    private var displayAmount: Double {
        displayFoodQuantityValue(amount: ingredient.amount, unit: ingredient.unit, servingLabel: ingredient.servingLabel, product: linkedProduct)
    }

    private var minimumDisplayAmount: Double {
        selectedServingOption == nil ? 0.01 : 1
    }

    private var doneTitle: String {
        NSLocalizedString("common.done", tableName: nil, bundle: .main, value: "Done", comment: "Done button title")
    }

    private var presentationHeight: CGFloat {
        onDelete == nil ? 390 : 450
    }

    private var quantitySummaryText: String {
        let amount = displayFoodQuantityText(
            amount: ingredient.amount,
            unit: ingredient.unit,
            servingLabel: ingredient.servingLabel,
            product: linkedProduct
        )
        return "\(amount) · \(sourceDescription)"
    }

    private var unitPickerTag: String {
        if linkedProduct != nil {
            if let option = selectedServingOption {
                return "serving_\(option.id)"
            }
            return "metric_\(ingredient.unit.rawValue)"
        }
        if linkedRecipe != nil {
            return "recipe_\(resolvedUnit.rawValue)"
        }
        return "unit_\(ingredient.unit.rawValue)"
    }

    private var unitPickerBinding: Binding<String> {
        Binding(
            get: { unitPickerTag },
            set: { tag in
                if tag.hasPrefix("serving_") {
                    let optionID = String(tag.dropFirst("serving_".count))
                    if let product = linkedProduct,
                       let option = product.selectableServingOptions.first(where: { $0.id == optionID }) {
                        selectServingOption(option)
                    }
                } else if tag.hasPrefix("metric_") {
                    let rawValue = String(tag.dropFirst("metric_".count))
                    if let unit = MealItemUnit(rawValue: rawValue) {
                        selectDirectMetricUnit(unit)
                    }
                } else if tag.hasPrefix("recipe_") {
                    let rawValue = String(tag.dropFirst("recipe_".count))
                    if let unit = MealItemUnit(rawValue: rawValue),
                       let recipe = linkedRecipe {
                        selectRecipeUnit(unit, recipe: recipe)
                    }
                }
            }
        )
    }

    private var amountTextBinding: Binding<String> {
        Binding(
            get: {
                amountText(for: displayAmount)
            },
            set: { newValue in
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                applyAmount(Double(normalized) ?? minimumDisplayAmount)
            }
        )
    }

    var body: some View {
        Group {
            if usesOwnNavigationContainer {
                NavigationStack {
                    editorContent
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            } else {
                editorContent
            }
        }
    }

    private var editorContent: some View {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                EOCard {
                    EOListRow(title: Text(verbatim: resolvedName))
                    EORowSeparator()

                    EOListRow(title: Text("recipe.editor.unit")) {
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

                    EOStepperRow(
                        title: Text(verbatim: formatFoodAmount(displayAmount)),
                        canDecrement: canDecrease,
                        onDecrement: { adjustAmount(by: -amountStep(for: resolvedUnit)) },
                        onIncrement: { adjustAmount(by: amountStep(for: resolvedUnit)) }
                    )
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

                Text(quantitySummaryText)
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
            .onAppear {
                normalizeDefaultMetricUnitIfNeeded()
            }
    }

    private func adjustAmount(by delta: Double) {
        if let selectedServingOption {
            let nextAmount = max(minimumDisplayAmount, displayAmount + delta)
            ingredient.amount = nextAmount * selectedServingOption.effectiveMetricAmount
            ingredient.unit = selectedServingOption.effectiveMetricUnit
            ingredient.servingLabel = selectedServingOption.selectionLabel
            return
        }

        let nextAmount = ingredient.amount + delta
        ingredient.amount = max(minimumAmount(for: resolvedUnit), nextAmount)
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
        case .serving:
            return 1
        case .grams, .milliliters:
            return 0.01
        }
    }

    private func amountText(for value: Double) -> String {
        formatFoodAmount(value)
    }

    private func dismissKeyboard() {
        isAmountFieldFocused = false
    }

    private func applyAmount(_ nextDisplayAmount: Double) {
        let resolvedAmount = max(minimumDisplayAmount, nextDisplayAmount)
        if let selectedServingOption {
            ingredient.amount = resolvedAmount * selectedServingOption.effectiveMetricAmount
            ingredient.unit = selectedServingOption.effectiveMetricUnit
            ingredient.servingLabel = selectedServingOption.selectionLabel
            return
        }

        ingredient.amount = max(minimumAmount(for: resolvedUnit), resolvedAmount)
    }

    private func selectRecipeUnit(_ unit: MealItemUnit, recipe: RecipeSummary) {
        guard resolvedUnit != unit else { return }

        let currentAmount = ingredient.amount
        let portionWeight = recipePortionWeight(for: recipe)

        switch (resolvedUnit, unit) {
        case (.serving, .grams):
            ingredient.amount = defaultAmount(for: unit)
        case (.grams, .serving):
            ingredient.amount = max(minimumAmount(for: unit), currentAmount / portionWeight)
        default:
            ingredient.amount = max(minimumAmount(for: unit), currentAmount)
        }

        ingredient.unit = unit
        ingredient.servingLabel = ""
    }

    private func recipePortionWeight(for recipe: RecipeSummary) -> Double {
        let portionWeight = catalogService.portionWeight(for: recipe)
        return portionWeight > 0 ? portionWeight : 100
    }

    private func selectDirectMetricUnit(_ unit: MealItemUnit) {
        let previousServingOption = selectedServingOption
        let previousUnit = ingredient.unit
        let previousAmount = ingredient.amount

        ingredient.unit = unit
        ingredient.servingLabel = ""

        if previousServingOption != nil {
            ingredient.amount = defaultAmount(for: unit)
            return
        }

        if previousUnit == unit {
            ingredient.amount = max(minimumAmount(for: unit), previousAmount)
            return
        }

        if previousUnit != .serving {
            ingredient.amount = max(minimumAmount(for: unit), previousAmount)
            return
        }

        ingredient.amount = defaultAmount(for: unit)
    }

    private func selectServingOption(_ option: ProductServingOption) {
        ingredient.unit = option.effectiveMetricUnit
        ingredient.amount = option.effectiveMetricAmount
        ingredient.servingLabel = option.selectionLabel
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
        let trimmedLabel = ingredient.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLabel.isEmpty, ingredient.unit == .serving else { return }

        let fallbackUnit = linkedProduct.baseNutritionUnit
        ingredient.unit = fallbackUnit
        ingredient.amount = max(minimumAmount(for: fallbackUnit), defaultAmount(for: fallbackUnit))
    }
}

struct SharedRecipeImportConfirmationSheet: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    let shareReference: String
    let onImportComplete: (() -> Void)?

    @State private var preview: RecipeSummary?
    @State private var existingRecipe: RecipeSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var recipeAlreadyExistsMessage: String {
	    NSLocalizedString("recipe.import.already_exists", comment: "Shared recipe already imported")
    }

    init(shareReference: String, onImportComplete: (() -> Void)? = nil) {
        self.shareReference = shareReference
        self.onImportComplete = onImportComplete
    }

    var body: some View {
        NavigationStack {
            Group {
                if let preview {
                    recipeContent(preview)
                } else if isLoading {
                    loadingPlaceholder
                } else {
                    loadingPlaceholder
                }
            }
            .background(Color.appPageBackground.ignoresSafeArea())
            .navigationTitle(Text("recipe.import.nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: shareReference) {
                loadPreview()
            }
            .alert("common.error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { Task { @MainActor in errorMessage = nil } } }
            )) {
                Button("common.ok", role: .cancel) {
                    Task { @MainActor in
                        errorMessage = nil
                    }
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    PressableIconButton(action: { dismiss() }) {
                        Label("common.close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 48, height: 48)
                    }
                }
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("recipe.import.loading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func recipeContent(_ recipe: RecipeSummary) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if RecipeCategory(rawString: recipe.category) != .none {
                    HStack(spacing: 6) {
                        Text(RecipeCategory(rawString: recipe.category).title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.appCardBackground, in: Capsule())
                    }
                }

                if !recipe.details.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(recipe.details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                }

                if !recipe.ingredients.isEmpty {
                    recipeIngredientsSection(recipe)
                }

                if !recipe.steps.isEmpty {
                    recipeStepsSection(recipe)
                }

                recipeNutritionSection(recipe)

                statusSection

                importButtonSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func recipeIngredientsSection(_ recipe: RecipeSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            importSectionTitle("recipe.editor.section.ingredients")

            VStack(spacing: 0) {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                    importIngredientRow(ingredient)

                    if index < recipe.ingredients.count - 1 {
                        importDivider
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private func recipeStepsSection(_ recipe: RecipeSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            importSectionTitle("recipe.editor.section.steps")

            VStack(spacing: 0) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
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

                    if index < recipe.steps.count - 1 {
                        importDivider
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private func recipeNutritionSection(_ recipe: RecipeSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            importSectionTitle("recipe.detail.nutrition")

            NutritionFactsTableCard(
                leftHeaderTitle: NSLocalizedString("recipe.editor.per_100g", comment: "Per 100g"),
                rightHeaderTitle: NSLocalizedString("recipe.editor.per_serving", comment: "Per serving"),
                leftSummary: recipe.resolvedNutritionPer100g,
                rightSummary: recipe.nutritionPerServing,
                footnote: String(
                    format: "%@: %d",
                    NSLocalizedString("recipe.editor.servings", comment: "Servings title"),
                    recipe.servings
                )
            )
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if existingRecipe != nil {
            Label("recipe.import.already_exists", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        } else {
            Text("recipe.import.message")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var importButtonSection: some View {
        if existingRecipe == nil {
            PressableIconButton(disabled: isLoading, action: importRecipe) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                } else {
                    Label("recipe.import.add_button", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
            }
            .foregroundStyle(.white)
            .background(.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isLoading ? 0.6 : 1)
        }
    }

    private func importIngredientRow(_ ingredient: RecipeIngredientSummary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(importIngredientName(for: ingredient))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            Text(importAmountText(for: ingredient))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(minWidth: 72, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func importIngredientName(for ingredient: RecipeIngredientSummary) -> String {
        if let productName = catalogService.productSummary(for: ingredient)?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !productName.isEmpty {
            return productName
        }

        if let recipeTitle = catalogService.recipeSummary(for: ingredient)?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !recipeTitle.isEmpty {
            return recipeTitle
        }

        let fallbackName = ingredient.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackName.isEmpty {
            return fallbackName
        }

        return NSLocalizedString("recipe.editor.new_ingredient", comment: "Ingredient fallback")
    }

    private func importAmountText(for ingredient: RecipeIngredientSummary) -> String {
        let amount = ingredient.amount
        let unitText: String
        switch ingredient.unit {
        case .grams:
            unitText = NSLocalizedString("unit.grams.short", comment: "Grams short")
        case .milliliters:
            unitText = NSLocalizedString("unit.milliliters.short", comment: "ml short")
        case .serving:
            unitText = NSLocalizedString("unit.servings.short", comment: "Servings short")
        }
        if amount == amount.rounded() {
            return "\(Int(amount)) \(unitText)"
        }
        return String(format: "%.1f \(unitText)", amount)
    }

    private func importNutritionRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var importDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 8)
    }

    private func importSectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private func importGramsText(_ value: Int) -> String {
        "\(value)"
    }

    private func loadPreview() {
        guard !shareReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = NSLocalizedString("recipe.import.invalid_link", comment: "Invalid recipe link")
            return
        }

        isLoading = true
        existingRecipe = nil
        Task {
            let recipe = await catalogService.previewSharedRecipe(code: shareReference)
            await MainActor.run {
                isLoading = false
                preview = recipe
                existingRecipe = recipe.flatMap(matchingExistingRecipe)
                if recipe == nil {
                    errorMessage = catalogService.lastErrorMessage ?? NSLocalizedString("recipe.import.invalid_link", comment: "Invalid recipe link")
                }
            }
        }
    }

    private func importRecipe() {
        guard existingRecipe == nil else { return }

        isLoading = true
        Task {
            let recipe = await catalogService.importSharedRecipe(code: shareReference)
            await MainActor.run {
                isLoading = false
                if recipe != nil {
                    onImportComplete?()
                    dismiss()
                } else if catalogService.lastErrorMessage == recipeAlreadyExistsMessage {
                    existingRecipe = preview.flatMap(matchingExistingRecipe) ?? preview
                    errorMessage = nil
                } else {
                    errorMessage = catalogService.lastErrorMessage ?? NSLocalizedString("recipe.import.import_failed", comment: "Recipe import failed")
                }
            }
        }
    }

    private func matchingExistingRecipe(_ recipe: RecipeSummary) -> RecipeSummary? {
        if let exactMatch = catalogService.recipeSummary(id: recipe.id) {
            return exactMatch
        }

        let fingerprint = recipeFingerprint(recipe)
        return catalogService.recipes.first(where: { recipeFingerprint($0) == fingerprint })
    }

    private func recipeFingerprint(_ recipe: RecipeSummary) -> String {
        let ingredientSignature = recipe.ingredients.map { ingredient in
            [
                String(format: "%.3f", ingredient.amount),
                ingredient.unit.rawValue,
                ingredientReferenceSignature(for: ingredient)
            ].joined(separator: "|")
        }.joined(separator: ";")

        let stepSignature = recipe.steps
            .map(normalizedRecipeText)
            .joined(separator: "|")

        let nutrition100Signature = [
            String(recipe.nutritionPer100g.calories),
            String(recipe.nutritionPer100g.protein),
            String(recipe.nutritionPer100g.fat),
            String(recipe.nutritionPer100g.carbs)
        ].joined(separator: ",")

        return [
            normalizedRecipeText(recipe.title),
            normalizedRecipeText(recipe.details),
            String(recipe.servings),
            String(recipe.caloriesPerServing),
            String(recipe.proteinPerServing),
            String(recipe.fatPerServing),
            String(recipe.carbsPerServing),
            String(recipe.cookTimeMinutes),
            String(format: "%.3f", recipe.outputWeightGrams),
            nutrition100Signature,
            ingredientSignature,
            stepSignature
        ].joined(separator: "||")
    }

    private func ingredientReferenceSignature(for ingredient: RecipeIngredientSummary) -> String {
        if ingredient.productID != nil {
            return "product"
        }

        if ingredient.nestedRecipeID != nil {
            return "recipe"
        }

        return "note:\(normalizedRecipeText(ingredient.note))"
    }

    private func normalizedRecipeText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct SharedMealImportSheet: View {
    @EnvironmentObject private var diaryService: FoodDiaryService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let shareCode: String

    @State private var preview: MealEntry?
    @State private var selectedDate = Date()
    @State private var selectedCategoryID = ""
    @State private var isLoading = false
    @State private var alreadyImported = false
    @State private var errorMessage: String?

    private var mealImportButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : .black
    }

    private var mealImportButtonForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var mealImportButtonBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }

    private var mealAlreadyExistsMessage: String {
        NSLocalizedString(
            "meal.import.already_exists",
            tableName: nil,
            bundle: .main,
            value: "You already have this meal.",
            comment: "Shared meal already imported"
        )
    }

    private var mealNutritionFactsTitle: String {
        NSLocalizedString(
            "nutrition.facts.title",
            tableName: nil,
            bundle: .main,
            value: "Nutrition Facts",
            comment: "Nutrition facts table title"
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let preview {
                    mealContent(preview)
                } else if isLoading {
                    mealLoadingPlaceholder
                } else {
                    mealLoadingPlaceholder
                }
            }
            .background(Color.appPageBackground.ignoresSafeArea())
            .navigationTitle("meal.import.title")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: shareCode) {
                loadPreview()
            }
            .alert("common.error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { Task { @MainActor in errorMessage = nil } } }
            )) {
                Button("common.ok", role: .cancel) {
                    Task { @MainActor in
                        errorMessage = nil
                    }
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    PressableIconButton(action: { dismiss() }) {
                        Label("common.close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 48, height: 48)
                    }
                }
            }
        }
    }

    private var mealLoadingPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("meal.import.loading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func mealContent(_ meal: MealEntry) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if !meal.items.isEmpty {
                    mealItemsSection(meal)
                }

                mealNutritionSection(meal)

                mealDestinationSection

                mealStatusSection

                mealImportButtonSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func mealItemsSection(_ meal: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            mealSectionTitle("meal.import.items_section")

            VStack(spacing: 0) {
                ForEach(Array(meal.items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(verbatim: "\(Int(item.amount)) \(item.unit.shortTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(format: NSLocalizedString("today.kcal_value", comment: "Calories value"), item.calories))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 4)

                    if index < meal.items.count - 1 {
                        mealDivider
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private func mealNutritionSection(_ meal: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            mealSectionTitle(Text(mealNutritionFactsTitle))

            NutritionFactsTableCard(
                headerTitle: NSLocalizedString("addmeal.section.total", comment: "Total nutrition card title"),
                summary: NutritionSummary(
                    calories: meal.calories,
                    protein: meal.protein,
                    fat: meal.fat,
                    carbs: meal.carbs
                )
            )
        }
    }

    private var mealDestinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            mealSectionTitle("meal.import.destination_section")

            VStack(spacing: 0) {
                DatePicker("meal.import.date", selection: $selectedDate)
                    .padding(.vertical, 8)

                mealDivider

                Picker("meal.import.meal", selection: $selectedCategoryID) {
                    ForEach(diaryService.visibleMealCategories) { category in
                        Label(category.displayTitle, systemImage: category.symbolName)
                            .tag(category.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var mealStatusSection: some View {
        if alreadyImported {
            Label(mealAlreadyExistsMessage, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var mealImportButtonSection: some View {
        if !alreadyImported {
            PressableIconButton(disabled: isLoading, action: importMeal) {
                if isLoading {
                    ProgressView()
                        .tint(mealImportButtonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Label("meal.import.submit", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                        .foregroundStyle(mealImportButtonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .background(mealImportButtonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                    .stroke(mealImportButtonBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
            .opacity(isLoading ? 0.6 : 1)
        }
    }

    private func mealNutritionRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            NutritionValueText(value: value)
        }
        .padding(.vertical, 10)
    }

    private var mealDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 8)
    }

    private var mealNutritionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private func mealSectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private func mealSectionTitle(_ title: Text) -> some View {
        title
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private func mealGramsText(_ value: Int) -> String {
        "\(value)"
    }

    private func loadPreview() {
        isLoading = true
        alreadyImported = false
        Task {
            let meal = await diaryService.previewSharedMeal(code: shareCode)
            await MainActor.run {
                isLoading = false
                preview = meal
                if let meal {
                    selectedDate = meal.scheduledAt
                    let availableCategories = diaryService.visibleMealCategories
                    let defaultCategoryID = availableCategories.first(where: { $0.id == meal.mealCategoryID })?.id ?? availableCategories.first?.id ?? ""
                    selectedCategoryID = defaultCategoryID
                    alreadyImported = diaryService.isKnownImportedSharedMeal(code: shareCode, preview: meal)
                }
                if meal == nil {
                    errorMessage = diaryService.lastErrorMessage ?? NSLocalizedString("meal.import.load_failed", comment: "Shared meal load failed")
                }
            }
        }
    }

    private func importMeal() {
        guard let preview else { return }
        isLoading = true
        Task {
            let targetCategoryID: String = {
                let availableCategories = diaryService.visibleMealCategories
                if availableCategories.contains(where: { $0.id == selectedCategoryID }) {
                    return selectedCategoryID
                }
                return availableCategories.first?.id ?? preview.mealCategoryID
            }()

            let importedMeal = await diaryService.importSharedMeal(
                code: shareCode,
                scheduledAt: selectedDate,
                mealCategoryID: targetCategoryID
            )
            await MainActor.run {
                isLoading = false
                if importedMeal != nil {
                    dismiss()
                } else if diaryService.lastSharedMealImportAlreadyExists {
                    alreadyImported = true
                    errorMessage = nil
                } else {
                    errorMessage = diaryService.lastErrorMessage ?? NSLocalizedString("meal.import.import_failed", comment: "Shared meal import failed")
                }
            }
        }
    }
}

private struct PhotoSourcePickerSheet: View {
    let onCamera: () -> Void
    let onLibrary: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        sourceButton(
                            title: "submit_review.photo.source.camera",
                            systemImage: "camera.fill",
                            action: onCamera
                        )
                        Divider().padding(.leading, 56)
                    }
                    sourceButton(
                        title: "submit_review.photo.source.library",
                        systemImage: "photo.on.rectangle.angled",
                        action: onLibrary
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
                )
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .presentationBackground(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    PressableIconButton(action: onCancel) {
                        Label("common.close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 48, height: 48)
                    }
                }
            }
        }
    }

    private func sourceButton(title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(.tint)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
