import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var catalogService: FoodCatalogService
    @ObservedObject var topSearchVM: TopSearchViewModel
    @StateObject private var searchService = FoodSearchService(authService: FoodAuthService.shared)
    @State private var selectedScope: SearchScope = .products
    @State private var remoteProductResults: [ProductSummary] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearchActive = false
    @State private var recentItems: [SearchRecentItem] = []
    @State private var showRecentClearConfirm = false
    @State private var previewProduct: ProductSummary?
    @State private var previewRecipe: RecipeSummary?
    @State private var previewMealTemplate: MealTemplateSummary?
    @State private var mainHeaderScrollOffset: CGFloat = 0

    private static let recentSearchLimit = 10

    private var normalizedQuery: String {
        topSearchVM.debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localProducts: [ProductSummary] {
        catalogService.search(query: topSearchVM.debouncedQuery, scope: .products).products
    }

    private var localRecipes: [RecipeSummary] {
        catalogService.search(query: topSearchVM.debouncedQuery, scope: .recipes).recipes
    }

    private var localMealTemplates: [MealTemplateSummary] {
        catalogService.mealTemplatesMatching(query: topSearchVM.debouncedQuery)
    }

    private var results: (products: [ProductSummary], recipes: [RecipeSummary]) {
        let products: [ProductSummary]
        if normalizedQuery.isEmpty {
            products = localProducts
        } else {
            products = remoteProductResults
        }

        return (products: products, recipes: localRecipes)
    }

    private var shouldShowPlaceholder: Bool {
        !isSearchActive && normalizedQuery.isEmpty && results.products.isEmpty && results.recipes.isEmpty
    }

    private var shouldShowRecentSearches: Bool {
        isSearchActive && normalizedQuery.isEmpty && results.products.isEmpty && results.recipes.isEmpty
    }

    private var shouldShowEmptyResults: Bool {
        !normalizedQuery.isEmpty && results.products.isEmpty && results.recipes.isEmpty
    }

    private var compactHeaderProgress: CGFloat {
        min(1, max(0, (mainHeaderScrollOffset - 30) / 30))
    }

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                if isSearchActive {
                    activeSearchContent(proxy: proxy)
                } else {
                    browseContent(proxy: proxy)
                }
            }

            if !isSearchActive {
                MainHeaderCompactOverlay(
                    title: "search.title",
                    username: authService.currentUsername,
                    onProfileTap: { authService.showProfile = true },
                    progress: compactHeaderProgress
                )
            }
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .navigationTitle("tab.search")
        .toolbar(.hidden, for: .navigationBar)
        .searchable(text: $topSearchVM.query, isPresented: $isSearchActive, prompt: "search.prompt")
        .dismissesKeyboardInteractively()
        .onAppear {
            loadRecentSearches()
            scheduleRemoteSearch()
        }
        .onChange(of: topSearchVM.debouncedQuery) { _, _ in
            scheduleRemoteSearch()
        }
        .onChange(of: selectedScope) { _, _ in
            loadRecentSearches()
            scheduleRemoteSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onChange(of: authService.currentUsername) { _, _ in
            loadRecentSearches()
        }
        .onChange(of: isSearchActive) { _, isActive in
            if isActive {
                mainHeaderScrollOffset = 0
            } else if normalizedQuery.isEmpty {
                remoteProductResults = []
            }
        }
        .onSubmit(of: .search) {
            rememberRecentSearch(topSearchVM.query)
        }
        .sheet(item: $previewProduct) { product in
            NavigationStack {
                ProductDetailView(productID: product.id, initialProduct: product, showsDismissButton: true)
            }
            .environmentObject(catalogService)
        }
        .sheet(item: $previewRecipe) { recipe in
            NavigationStack {
                RecipeDetailView(recipeID: recipe.id, initialRecipe: recipe, showsDismissButton: true)
            }
            .environmentObject(catalogService)
        }
        .sheet(item: $previewMealTemplate) { mealTemplate in
            NavigationStack {
                MealTemplateDetailView(mealTemplateID: mealTemplate.id, initialMealTemplate: mealTemplate, showsDismissButton: true)
            }
            .environmentObject(catalogService)
        }
        .confirmationDialog("search.recent.clear.title", isPresented: $showRecentClearConfirm, titleVisibility: .visible) {
            Button("search.recent.clear.action", role: .destructive) {
                clearRecentSearches()
            }
            Button("common.cancel", role: .cancel) { }
        }
    }

    private func browseContent(proxy: GeometryProxy) -> some View {
        List {
            MainHeaderView(
                title: "search.title",
                username: authService.currentUsername,
                onProfileTap: { authService.showProfile = true }
            )
            .opacity(1 - compactHeaderProgress)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            scopePickerRow(top: 0)

            scopeContent(proxy: proxy)
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newValue in
            mainHeaderScrollOffset = newValue
        }
    }

    private func activeSearchContent(proxy: GeometryProxy) -> some View {
        List {
            scopePickerRow(top: 10)

            scopeContent(proxy: proxy)
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(Color.appPageBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func scopeContent(proxy: GeometryProxy) -> some View {
        switch selectedScope {
        case .products:
            productsContent(proxy: proxy)
        case .recipes:
            recipesContent(proxy: proxy)
        case .mealTemplates:
            mealTemplatesContent(proxy: proxy)
        }
    }

    private func scopePickerRow(top: CGFloat) -> some View {
        Picker("search.scope.title", selection: $selectedScope) {
            ForEach(SearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func recentSearchesOrPlaceholderSection(proxy: GeometryProxy) -> some View {
        if recentItems.isEmpty {
            placeholderSection(minHeight: max(320, proxy.size.height - 280))
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            VStack(spacing: 8) {
                HStack {
                    Text("search.recent.title")
                        .font(.system(size: 26, weight: .bold))

                    Spacer()

                    Button("search.recent.clear.action") {
                        showRecentClearConfirm = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            ForEach(recentItems, id: \.id) { item in
                recentItemRow(item)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparatorTint(Color.primary.opacity(0.08))
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func recentItemRow(_ item: SearchRecentItem) -> some View {
        Button {
            handleRecentSelection(item)
        } label: {
            SearchResultRow(
                iconName: item.systemImageName,
                iconTint: item.iconColor,
                title: item.title,
                subtitle: item.subtitle ?? ""
            )
        }
        .buttonStyle(.plain)
    }

    private func placeholderSection(minHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            FoodPlaceholderArtwork(kind: placeholderArtworkKind, width: 128, height: 128)

            VStack(spacing: 6) {
                Text(placeholderTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(placeholderSubtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }

    private var emptyResultsSection: some View {
        Text(emptyResultsTitle)
            .font(.body.weight(.medium))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var emptyResultsTitle: String {
        if let error = searchErrorText {
            return error
        }

        let key = searchService.isLoading ? "search.loading" : "search.empty"
        return NSLocalizedString(key, comment: "Search empty state")
    }

    @ViewBuilder
    private func productsContent(proxy: GeometryProxy) -> some View {
        if isSearchActive && normalizedQuery.isEmpty {
            recentSearchesOrPlaceholderSection(proxy: proxy)
        } else if !results.products.isEmpty {
            ForEach(results.products, id: \.id) { product in
                SearchProductRow(
                    product: product,
                    detailText: productDetailText(product),
                    showsDisclosureIndicator: true
                ) {
                    openProduct(product)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparatorTint(Color.primary.opacity(0.08))
                .listRowBackground(Color.clear)
            }
        } else if !isSearchActive && normalizedQuery.isEmpty && results.products.isEmpty {
            placeholderSection(minHeight: max(320, proxy.size.height - 280))
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else if !normalizedQuery.isEmpty && results.products.isEmpty {
            emptyResultsSection
                .frame(maxWidth: .infinity, minHeight: max(240, proxy.size.height - 280), alignment: .center)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func recipesContent(proxy: GeometryProxy) -> some View {
        if !results.recipes.isEmpty {
            ForEach(results.recipes, id: \.id) { recipe in
                SearchRecipeRow(
                    recipe: recipe,
                    detailText: recipeDetailText(recipe),
                    showsDisclosureIndicator: true
                ) {
                    openRecipe(recipe)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparatorTint(Color.primary.opacity(0.08))
                .listRowBackground(Color.clear)
            }
        } else if isSearchActive && normalizedQuery.isEmpty {
            recentSearchesOrPlaceholderSection(proxy: proxy)
        } else if !isSearchActive && normalizedQuery.isEmpty {
            placeholderSection(minHeight: max(320, proxy.size.height - 280))
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else if !normalizedQuery.isEmpty {
            emptyResultsSection
                .frame(maxWidth: .infinity, minHeight: max(240, proxy.size.height - 280), alignment: .center)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func mealTemplatesContent(proxy: GeometryProxy) -> some View {
        if !localMealTemplates.isEmpty {
            ForEach(localMealTemplates, id: \.id) { mealTemplate in
                SearchMealTemplateRow(
                    mealTemplate: mealTemplate,
                    detailText: mealTemplateDetailText(mealTemplate),
                    showsDisclosureIndicator: true
                ) {
                    previewMealTemplate = mealTemplate
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparatorTint(Color.primary.opacity(0.08))
                .listRowBackground(Color.clear)
            }
        } else if isSearchActive && normalizedQuery.isEmpty {
            recentSearchesOrPlaceholderSection(proxy: proxy)
        } else if !isSearchActive && normalizedQuery.isEmpty {
            placeholderSection(minHeight: max(320, proxy.size.height - 280))
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else if !normalizedQuery.isEmpty {
            emptyResultsSection
                .frame(maxWidth: .infinity, minHeight: max(240, proxy.size.height - 280), alignment: .center)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private var placeholderArtworkKind: FoodPlaceholderKind {
        switch selectedScope {
        case .products:
            return .grocery
        case .recipes:
            return .recipe
        case .mealTemplates:
            return .meal
        }
    }

    private var placeholderTitle: String {
        switch selectedScope {
        case .products:
            return NSLocalizedString("search.placeholder.products.title", value: "Find groceries", comment: "Product search placeholder title")
        case .recipes:
            return NSLocalizedString("search.placeholder.recipes.title", value: "Find recipes", comment: "Recipe search placeholder title")
        case .mealTemplates:
            return NSLocalizedString("search.placeholder.meals.title", value: "Rations", comment: "Ration search placeholder title")
        }
    }

    private var placeholderSubtitle: String {
        switch selectedScope {
        case .products:
            return NSLocalizedString("search.placeholder.products.subtitle", value: "Quickly find groceries from your library and add them to your diary.", comment: "Product search placeholder subtitle")
        case .recipes:
            return NSLocalizedString("search.placeholder.recipes.subtitle", value: "Pick recipes from your library for quick meals.", comment: "Recipe search placeholder subtitle")
        case .mealTemplates:
            return NSLocalizedString("search.placeholder.meals.subtitle", value: "Search the rations you saved to reuse later.", comment: "Ration search placeholder subtitle")
        }
    }

    private var searchErrorText: String? {
        guard selectedScope == .products else { return nil }
        let error = searchService.lastErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return error.isEmpty ? nil : error
    }

    private func scheduleRemoteSearch() {
        searchTask?.cancel()

        let query = normalizedQuery
        guard selectedScope == .products, !query.isEmpty else {
            remoteProductResults = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            let remote = await searchService.searchProducts(query: query, limit: 40, offset: 0)
            guard !Task.isCancelled else { return }

            let mapped = remote.map(mapRemoteProduct)
            await MainActor.run {
                guard normalizedQuery == query else { return }
                remoteProductResults = mapped
                if !mapped.isEmpty {
                    rememberRecentSearch(query)
                }
            }
        }
    }

    private func loadRecentSearches() {
        guard let data = UserDefaults.standard.data(forKey: recentSearchesKey) else {
            if selectedScope == .products,
               let legacyData = UserDefaults.standard.data(forKey: legacyRecentSearchesKey) {
                let decoder = JSONDecoder()
                recentItems = (try? decoder.decode([SearchRecentItem].self, from: legacyData)) ?? []
                return
            }
            recentItems = []
            return
        }

        let decoder = JSONDecoder()
        recentItems = (try? decoder.decode([SearchRecentItem].self, from: data)) ?? []
    }

    private func rememberRecentSearch(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }

        let item = SearchRecentItem.query(query)
        var updated = recentItems.filter { $0 != item }
        updated.insert(item, at: 0)
        if updated.count > Self.recentSearchLimit {
            updated = Array(updated.prefix(Self.recentSearchLimit))
        }

        recentItems = updated
        saveRecentSearches(updated)
    }

    private func rememberOpenedProduct(_ product: ProductSummary) {
        let item = SearchRecentItem.product(SearchRecentProduct(product: product))
        var updated = recentItems.filter {
            switch ($0, item) {
            case (.product(let existing), .product(let incoming)):
                return existing.id != incoming.id
            default:
                return $0 != item
            }
        }
        updated.insert(item, at: 0)
        if updated.count > Self.recentSearchLimit {
            updated = Array(updated.prefix(Self.recentSearchLimit))
        }

        recentItems = updated
        saveRecentSearches(updated)
    }

    private func openProduct(_ product: ProductSummary) {
        rememberOpenedProduct(product)
        previewProduct = product
    }

    private func openRecipe(_ recipe: RecipeSummary) {
        previewRecipe = recipe
    }

    private func handleRecentSelection(_ item: SearchRecentItem) {
        switch item {
        case .query(let query):
            topSearchVM.query = query
            topSearchVM.debouncedQuery = query
        case .product(let recentProduct):
            let product = recentProduct.asProductSummary
            rememberOpenedProduct(product)
            previewProduct = product
        }
    }

    private func clearRecentSearches() {
        searchTask?.cancel()
        recentItems = []
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }

    private func saveRecentSearches(_ values: [SearchRecentItem]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(values) else { return }
        UserDefaults.standard.set(data, forKey: recentSearchesKey)
    }

    private var recentSearchesKey: String {
        let username = authService.currentUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Eatometer.search.recent_items_v3_\(selectedScope.rawValue)_\(username.isEmpty ? "anon" : username.lowercased())"
    }

    private var legacyRecentSearchesKey: String {
        let username = authService.currentUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Eatometer.search.recent_items_v2_\(username.isEmpty ? "anon" : username.lowercased())"
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

    private func productNutritionSummary(_ product: ProductSummary) -> String? {
        let hasNutrition = product.caloriesPer100g != 0
            || product.proteinPer100g != 0
            || product.fatPer100g != 0
            || product.carbsPer100g != 0

        guard hasNutrition else { return nil }

        let caloriesUnit = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        let proteinShort = NSLocalizedString("recipe.detail.protein_short", comment: "Protein short title")
        let fatShort = NSLocalizedString("recipe.detail.fat_short", comment: "Fat short title")
        let carbsShort = NSLocalizedString("recipe.detail.carbs_short", comment: "Carbs short title")

        return [
            "\(product.caloriesPer100g) \(caloriesUnit)",
            "\(proteinShort) \(product.proteinPer100g)",
            "\(fatShort) \(product.fatPer100g)",
            "\(carbsShort) \(product.carbsPer100g)"
        ].joined(separator: " · ")
    }

    private func productDetailText(_ product: ProductSummary) -> String {
        let nutrition = productNutritionSummary(product)
        let brand = product.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = product.details.trimmingCharacters(in: .whitespacesAndNewlines)

        if !brand.isEmpty, let nutrition {
            return "\(brand) · \(nutrition)"
        }

        if let nutrition {
            return nutrition
        }

        if !brand.isEmpty {
            return brand
        }

        return details.isEmpty ? NSLocalizedString("search.nutrition.unavailable", comment: "Missing nutrition fallback text") : details
    }

    private func recipeDetailText(_ recipe: RecipeSummary) -> String {
        let caloriesUnit = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        let perServingTitle = NSLocalizedString("recipe.editor.per_serving", comment: "Per serving")
        let per100gTitle = NSLocalizedString("recipe.editor.per_100g", comment: "Per 100g")
        let per100gNutrition = recipe.resolvedNutritionPer100g

        var components = ["\(recipe.caloriesPerServing) \(caloriesUnit) · \(perServingTitle)"]
        if per100gNutrition != .zero {
            components.append("\(per100gNutrition.calories) \(caloriesUnit) · \(per100gTitle)")
        }
        return components.joined(separator: " · ")
    }

    private func mealTemplateDetailText(_ mealTemplate: MealTemplateSummary) -> String {
        let caloriesUnit = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        return [
            "\(mealTemplate.calories) \(caloriesUnit)",
            "\(mealTemplate.items.count) items"
        ].joined(separator: " · ")
    }
}

private struct SearchProductRow: View {
    let product: ProductSummary
    let detailText: String
    var showsDisclosureIndicator: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            SearchResultRow(
                iconName: productIconName,
                iconTint: iconTint,
                showsIcon: false,
                title: product.name,
                subtitle: detailText,
                showsDisclosureIndicator: showsDisclosureIndicator
            )
        }
        .buttonStyle(.plain)
    }

    private var productIconName: String {
        "shippingbox.fill"
    }

    private var iconTint: Color {
        .primary
    }
}

private struct SearchRecipeRow: View {
    let recipe: RecipeSummary
    let detailText: String
    var showsDisclosureIndicator: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            SearchResultRow(
                iconName: "fork.knife",
                iconTint: .orange,
                showsIcon: false,
                title: recipe.title,
                subtitle: detailText,
                showsDisclosureIndicator: showsDisclosureIndicator
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SearchMealTemplateRow: View {
    let mealTemplate: MealTemplateSummary
    let detailText: String
    var showsDisclosureIndicator: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            SearchResultRow(
                iconName: "square.stack.3d.up.fill",
                iconTint: .mint,
                showsIcon: false,
                title: mealTemplate.title,
                subtitle: detailText,
                showsDisclosureIndicator: showsDisclosureIndicator
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SearchResultRow: View {
    let iconName: String
    let iconTint: Color
    var emoji: String = ""
    var showsIcon: Bool = true
    let title: String
    let subtitle: String
    var showsDisclosureIndicator: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if showsIcon {
                ZStack {
                    if let trimmedEmoji {
                        Text(trimmedEmoji)
                            .font(.title3)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(iconTint.opacity(0.12))

                        Image(systemName: iconName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(iconTint)
                    }
                }
                .frame(width: 52, height: 52)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if let trimmedSubtitle {
                    Text(trimmedSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 12)
    }

    private var trimmedEmoji: String? {
        let value = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var trimmedSubtitle: String? {
        let value = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct SearchRecentProduct: Codable, Hashable {
    let id: UUID
    let name: String
    let brand: String
    let barcode: String?
    let caloriesPer100g: Int
    let proteinPer100g: Int
    let fatPer100g: Int
    let carbsPer100g: Int
    let details: String
    let servingAmount: Double
    let servingUnitRawValue: String

    init(product: ProductSummary) {
        self.id = product.id
        self.name = product.name
        self.brand = product.brand
        self.barcode = product.barcode
        self.caloriesPer100g = product.caloriesPer100g
        self.proteinPer100g = product.proteinPer100g
        self.fatPer100g = product.fatPer100g
        self.carbsPer100g = product.carbsPer100g
        self.details = product.details
        self.servingAmount = product.servingAmount
        self.servingUnitRawValue = product.servingUnit.rawValue
    }

    var asProductSummary: ProductSummary {
        ProductSummary(
            id: id,
            name: name,
            brand: brand,
            barcode: barcode,
            caloriesPer100g: caloriesPer100g,
            proteinPer100g: proteinPer100g,
            fatPer100g: fatPer100g,
            carbsPer100g: carbsPer100g,
            details: details,
            servingAmount: servingAmount,
            servingUnit: MealItemUnit(rawValue: servingUnitRawValue) ?? .grams
        )
    }

    var subtitleText: String {
        let caloriesUnit = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        let proteinShort = NSLocalizedString("recipe.detail.protein_short", comment: "Protein short title")
        let fatShort = NSLocalizedString("recipe.detail.fat_short", comment: "Fat short title")
        let carbsShort = NSLocalizedString("recipe.detail.carbs_short", comment: "Carbs short title")

        let nutrition = [
            "\(caloriesPer100g) \(caloriesUnit)",
            "\(proteinShort) \(proteinPer100g)",
            "\(fatShort) \(fatPer100g)",
            "\(carbsShort) \(carbsPer100g)"
        ].joined(separator: " · ")

        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedBrand.isEmpty ? nutrition : "\(trimmedBrand) · \(nutrition)"
    }
}

private enum SearchRecentItem: Codable, Hashable, Identifiable {
    case query(String)
    case product(SearchRecentProduct)

    var id: String {
        switch self {
        case .query(let query):
            return "query-\(query.lowercased())"
        case .product(let product):
            return "product-\(product.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .query(let query):
            return query
        case .product(let product):
            return product.name
        }
    }

    var subtitle: String? {
        switch self {
        case .query:
            return NSLocalizedString("search.recent.repeat", comment: "Recent query subtitle")
        case .product(let product):
            return product.subtitleText
        }
    }

    var systemImageName: String {
        switch self {
        case .query:
            return "clock.arrow.circlepath"
        case .product:
            return "shippingbox"
        }
    }

    var trailingSystemImageName: String {
        switch self {
        case .query:
            return "arrow.up.left"
        case .product:
            return "chevron.right"
        }
    }

    var iconColor: Color {
        switch self {
        case .query:
            return .secondary
        case .product:
            return .accentColor
        }
    }
}
