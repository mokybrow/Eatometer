import Combine
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import SwiftProtobuf

struct FriendVisibleCatalog: Hashable {
    var products: [ProductSummary] = []
    var recipes: [RecipeSummary] = []
    var mealTemplates: [MealTemplateSummary] = []

    var isEmpty: Bool {
        products.isEmpty && recipes.isEmpty && mealTemplates.isEmpty
    }

    func filtered(allowFriendsVisibility: Bool) -> FriendVisibleCatalog {
        let allowed: Set<FoodVisibilityOption> = allowFriendsVisibility
            ? [.friendsVisibility, .publicVisibility]
            : [.publicVisibility]

        return FriendVisibleCatalog(
            products: products.filter { allowed.contains($0.visibility) },
            recipes: recipes.filter { allowed.contains($0.visibility) },
            mealTemplates: mealTemplates.filter { allowed.contains($0.visibility) }
        )
    }
}

@MainActor
final class FoodCatalogService: ObservableObject {
    @Published private(set) var recipes: [RecipeSummary]
    @Published private(set) var products: [ProductSummary]
    @Published private(set) var mealTemplates: [MealTemplateSummary]
    @Published private(set) var recipeEditorStore: RecipeEditorDraftStore?
    @Published private(set) var isLoading = false
    @Published var lastErrorMessage: String?
    @Published private(set) var favoriteProductIDs: Set<UUID> = []
    @Published private(set) var favoriteProductSummaries: [ProductSummary] = []
    @Published private(set) var favoriteRecipeIDs: Set<UUID> = []
    @Published private(set) var favoriteMealTemplateIDs: Set<UUID> = []

    let authService: FoodAuthService?
    private let serverHost: String
    private let serverPort: Int
    private let useTLS: Bool
    @Published private var cachedProductDetails: [UUID: ProductSummary] = [:]
    var cachedMyProductSubmissions: [ProductSubmissionSummary] = []
    var cachedMyProductSubmissionsAt: Date?
    private var myProductSubmissionsWarmupTask: Task<Void, Never>?
    private var productSharePayloads: [UUID: FoodSharePayload] = [:]
    private var recipeSharePayloads: [UUID: FoodSharePayload] = [:]
    private var mealTemplateSharePayloads: [UUID: FoodSharePayload] = [:]
    private var productShareTasks: [UUID: Task<FoodSharePayload?, Never>] = [:]
    private var recipeShareTasks: [UUID: Task<FoodSharePayload?, Never>] = [:]
    private var mealTemplateShareTasks: [UUID: Task<FoodSharePayload?, Never>] = [:]
    private var cacheScopeID: String
    private var messagesPickerRefreshTask: Task<Void, Never>?
    private var shareWarmupTask: Task<Void, Never>?
    private var shareWarmupSignature: String?
    static let myProductSubmissionsCacheTTL: TimeInterval = 120

    private struct CatalogCacheSnapshot: Codable {
        var products: [ProductSummary]
        var recipes: [RecipeSummary]
        var mealTemplates: [MealTemplateSummary]
        var knownProducts: [ProductSummary]

        private enum CodingKeys: String, Swift.CodingKey {
            case products
            case recipes
            case mealTemplates
            case knownProducts
        }

        init(
            products: [ProductSummary],
            recipes: [RecipeSummary],
            mealTemplates: [MealTemplateSummary],
            knownProducts: [ProductSummary]
        ) {
            self.products = products
            self.recipes = recipes
            self.mealTemplates = mealTemplates
            self.knownProducts = knownProducts
        }

        init(from decoder: any Swift.Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            products = try container.decodeIfPresent([ProductSummary].self, forKey: .products) ?? []
            recipes = try container.decodeIfPresent([RecipeSummary].self, forKey: .recipes) ?? []
            mealTemplates = try container.decodeIfPresent([MealTemplateSummary].self, forKey: .mealTemplates) ?? []
            knownProducts = try container.decodeIfPresent([ProductSummary].self, forKey: .knownProducts) ?? []
        }

        func encode(to encoder: any Swift.Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(products, forKey: .products)
            try container.encode(recipes, forKey: .recipes)
            try container.encode(mealTemplates, forKey: .mealTemplates)
            try container.encode(knownProducts, forKey: .knownProducts)
        }
    }

    private static let catalogCacheKeyPrefix = "Eatometer.catalog.snapshot."
    private static let favoritesCacheKeyPrefix = "Eatometer.favorites."
    private static let favoriteRecipesCacheKeyPrefix = "Eatometer.favorites.recipes."
    private static let favoriteMealTemplatesCacheKeyPrefix = "Eatometer.favorites.mealTemplates."
    private static let sharedAppGroupID = "group.com.goeatometer.Eatometer.shared"
    private static let messagesPickerSnapshotKey = "Eatometer.messages.picker.snapshot"
    private static let messagesPickerSnapshotSignatureKey = "Eatometer.messages.picker.snapshot.signature"
    private static let messagesPickerItemLimit = 8

    private struct MessagesPickerShareItem: Codable {
        let kind: String
        let id: String
        let title: String
        let subtitle: String
        let shareURL: String
        let shareSubject: String
        let emoji: String?
    }

    private struct MessagesPickerSnapshot: Codable {
        let products: [MessagesPickerShareItem]
        let recipes: [MessagesPickerShareItem]
        let meals: [MessagesPickerShareItem]
        let updatedAt: Date
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: sharedAppGroupID)
    }

	init() {
        self.authService = nil
        self.serverHost = ""
        self.serverPort = 0
        self.useTLS = false
	    self.cacheScopeID = "preview"
	    self.recipes = FoodCatalogService.sampleRecipes
	    self.products = FoodCatalogService.sampleProducts
        self.mealTemplates = FoodCatalogService.sampleMealTemplates
        self.recipeEditorStore = nil
	    self.cachedProductDetails = [:]
	}

    init(authService: FoodAuthService) {
        let config = ConfigLoader.loadFoodAPIConfig()
        let cacheScopeID = FoodCatalogService.normalizeCacheScope(authService.currentUsername)
        let snapshot = FoodCatalogService.loadCatalogSnapshot(scopeID: cacheScopeID)
        self.authService = authService
        self.serverHost = config.host
        self.serverPort = config.port
        self.useTLS = config.useTLS
        self.cacheScopeID = cacheScopeID
        self.recipes = FoodCatalogService.sortedRecipes(snapshot?.recipes ?? [], sort: .addedNewest)
        self.products = FoodCatalogService.sortedProducts(snapshot?.products ?? [], sort: .addedNewest)
        self.mealTemplates = FoodCatalogService.sortedMealTemplates(snapshot?.mealTemplates ?? [], sort: .addedNewest)
        self.recipeEditorStore = nil
        self.cachedProductDetails = FoodCatalogService.knownProducts(from: snapshot)
        self.favoriteProductIDs = []
        self.favoriteProductSummaries = []
        self.favoriteRecipeIDs = []
        self.favoriteMealTemplateIDs = []
        scheduleMessagesPickerSnapshotRefresh(force: true)
        scheduleSharePayloadWarmup(force: true)
        scheduleMyProductSubmissionsWarmup()
    }

    var featuredRecipes: [RecipeSummary] {
        Array(recipes.prefix(4))
    }

    func restoreCachedCatalogIfAvailable() {
        guard authService != nil else { return }

        let resolvedScope = Self.normalizeCacheScope(authService?.currentUsername)
        let didChangeScope = resolvedScope != cacheScopeID
        if didChangeScope {
            cacheScopeID = resolvedScope
            resetMyProductSubmissionCache()
            resetSharePayloadCache()
        }

        if didChangeScope {
            favoriteProductIDs = []
            favoriteProductSummaries = []
            favoriteRecipeIDs = []
            favoriteMealTemplateIDs = []
            scheduleMyProductSubmissionsWarmup(force: true)
        }

        guard didChangeScope || recipes.isEmpty || products.isEmpty || cachedProductDetails.isEmpty else {
            return
        }

        applyCatalogSnapshot(Self.loadCatalogSnapshot(scopeID: cacheScopeID), resetWhenMissing: didChangeScope)
        scheduleSharePayloadWarmup(force: didChangeScope)
    }

    func search(query: String, scope: SearchScope) -> (products: [ProductSummary], recipes: [RecipeSummary]) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let productResults = scope == .recipes ? [] : products.filter {
            normalized.isEmpty
            || $0.name.lowercased().contains(normalized)
            || $0.brand.lowercased().contains(normalized)
        }

        let recipeResults = scope == .products ? [] : recipes.filter {
            normalized.isEmpty || $0.title.lowercased().contains(normalized)
        }

        return (productResults, recipeResults)
    }

    func mealTemplatesMatching(query: String) -> [MealTemplateSummary] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return mealTemplates }

        return mealTemplates.filter { mealTemplate in
            mealTemplate.title.lowercased().contains(normalized)
                || mealTemplate.details.lowercased().contains(normalized)
                || mealTemplate.items.contains { $0.name.lowercased().contains(normalized) }
        }
    }

    func presentRecipeEditor(draft: RecipeDraft) {
        recipeEditorStore = RecipeEditorDraftStore(draft: draft)
    }

    func dismissRecipeEditor() {
        recipeEditorStore = nil
    }

    func resolvedName(for ingredient: RecipeIngredientDraft) -> String {
        if let product = productSummary(for: ingredient) {
            return product.name
        }
        if let recipe = recipeSummary(for: ingredient) {
            return recipe.title
        }
        return ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func productSummary(for item: MealItemEntry) -> ProductSummary? {
        guard let productID = item.productID else { return item.linkedProductSummary }
        return productSummary(id: productID) ?? item.linkedProductSummary
    }

    func recipeSummary(for item: MealItemEntry) -> RecipeSummary? {
        guard let recipeID = item.recipeID else { return item.linkedRecipeSummary }
        return recipeSummary(id: recipeID) ?? item.linkedRecipeSummary
    }

    func productSummary(for ingredient: RecipeIngredientSummary) -> ProductSummary? {
        guard let productID = ingredient.productID else { return ingredient.linkedProductSummary }
        return productSummary(id: productID) ?? ingredient.linkedProductSummary
    }

    func recipeSummary(for ingredient: RecipeIngredientSummary) -> RecipeSummary? {
        guard let recipeID = ingredient.nestedRecipeID else { return ingredient.linkedRecipeSummary }
        return recipeSummary(id: recipeID) ?? ingredient.linkedRecipeSummary
    }

    func productSummary(for ingredient: RecipeIngredientDraft) -> ProductSummary? {
        guard let productID = ingredient.productID else { return ingredient.linkedProductSummary }
        return productSummary(id: productID) ?? ingredient.linkedProductSummary
    }

    func recipeSummary(for ingredient: RecipeIngredientDraft) -> RecipeSummary? {
        guard let recipeID = ingredient.nestedRecipeID else { return ingredient.linkedRecipeSummary }
        return recipeSummary(id: recipeID) ?? ingredient.linkedRecipeSummary
    }

    func computedNutrition(for draft: RecipeDraft) -> RecipeNutritionPreview {
        let total = draft.ingredients.reduce(into: NutritionSummary.zero) { partial, ingredient in
            let ingredientNutrition = nutrition(for: ingredient)
            partial = NutritionSummary(
                calories: partial.calories + ingredientNutrition.calories,
                protein: partial.protein + ingredientNutrition.protein,
                fat: partial.fat + ingredientNutrition.fat,
                carbs: partial.carbs + ingredientNutrition.carbs
            )
        }

        let servings = max(draft.servings, 1)
        let perServing = NutritionSummary(
            calories: Int((Double(total.calories) / Double(servings)).rounded()),
            protein: Int((Double(total.protein) / Double(servings)).rounded()),
            fat: Int((Double(total.fat) / Double(servings)).rounded()),
            carbs: Int((Double(total.carbs) / Double(servings)).rounded())
        )

        let outputWeight = max(effectiveOutputWeight(for: draft), 1)
        let factor = 100.0 / outputWeight
        let per100g = total.scaled(by: factor)

        return RecipeNutritionPreview(total: total, perServing: perServing, per100g: per100g)
    }

    func effectiveOutputWeight(for draft: RecipeDraft) -> Double {
        let explicitWeight = max(draft.outputWeightGrams, 0)
        if explicitWeight > 0 {
            return explicitWeight
        }

        return estimatedOutputWeight(for: draft)
    }

    func ingredientWeightEstimate(for draft: RecipeDraft) -> Double {
        estimatedOutputWeight(for: draft)
    }

    func effectiveOutputWeight(for recipe: RecipeSummary) -> Double {
        let explicitWeight = max(recipe.outputWeightGrams, 0)
        if explicitWeight > 0 {
            return explicitWeight
        }

        return estimatedOutputWeight(for: recipe)
    }

    func portionWeight(for recipe: RecipeSummary) -> Double {
        let servings = max(recipe.servings, 1)
        let totalWeight = effectiveOutputWeight(for: recipe)
        guard totalWeight > 0 else { return 0 }
        return totalWeight / Double(servings)
    }

    func nutritionPreview(for recipe: RecipeSummary) -> RecipeNutritionPreview {
        let servings = max(recipe.servings, 1)
        let perServing = NutritionSummary(
            calories: recipe.caloriesPerServing,
            protein: recipe.proteinPerServing,
            fat: recipe.fatPerServing,
            carbs: recipe.carbsPerServing
        )

        let total = perServing.scaled(by: Double(servings))
        let totalWeight = effectiveOutputWeight(for: recipe)
        let storedPer100g = recipe.nutritionPer100g

        let per100g: NutritionSummary
        if storedPer100g != .zero {
            per100g = storedPer100g
        } else if totalWeight > 0 {
            per100g = total.scaled(by: 100.0 / totalWeight)
        } else {
            per100g = .zero
        }

        return RecipeNutritionPreview(total: total, perServing: perServing, per100g: per100g)
    }

    func nutritionSummary(for recipe: RecipeSummary, unit: MealItemUnit) -> NutritionSummary {
        switch unit {
        case .serving:
            return recipe.nutritionPerServing
        case .grams, .milliliters:
            return nutritionPreview(for: recipe).per100g
        }
    }

    func makeMealItem(
        from recipe: RecipeSummary,
        id: UUID = UUID(),
        amount: Double = 1,
        unit: MealItemUnit = .serving,
        note: String = "",
        servingLabel: String = ""
    ) -> MealItemEntry {
        let nutrition = nutritionSummary(for: recipe, unit: unit)
        return MealItemEntry(
            id: id,
            name: recipe.title,
            amount: amount,
            unit: unit,
            note: note,
            servingLabel: servingLabel,
            caloriesPer100g: nutrition.calories,
            proteinPer100g: nutrition.protein,
            fatPer100g: nutrition.fat,
            carbsPer100g: nutrition.carbs,
            productID: nil,
            recipeID: recipe.id,
            productSnapshot: nil,
            recipeSnapshot: recipe
        )
    }

    func reloadCatalog() async {
        guard authService != nil else { return }

        restoreCachedCatalogIfAvailable()

        isLoading = true
        defer { isLoading = false }

        do {
            let (productsResponse, recipesResponse, remoteMealTemplates) = try await withAuthenticatedMetadata { metadata in
                async let remoteProducts: Food_ListUserProductsResponse = withFoodClient { client in
                    let request = Food_ListUserProductsRequest()
                    return try await client.listUserProducts(request, metadata: metadata)
                }
                async let remoteRecipes: Food_ListUserRecipesResponse = withFoodClient { client in
                    let request = Food_ListUserRecipesRequest()
                    return try await client.listUserRecipes(request, metadata: metadata)
                }
                async let remoteMealTemplates: Food_ListUserMealTemplatesResponse = withFoodClient { client in
                    let request = Food_ListUserMealTemplatesRequest()
                    return try await client.listUserMealTemplates(request, metadata: metadata)
                }

                return try await (remoteProducts, remoteRecipes, remoteMealTemplates)
            }
            let knownProducts = cachedProductDetails
            products = sortedProducts(productsResponse.products.compactMap(Self.makeProductSummary))
            recipes = sortedRecipes(recipesResponse.recipes.compactMap(Self.makeRecipeSummary))
            mealTemplates = sortedMealTemplates(remoteMealTemplates.mealTemplates.compactMap(Self.makeMealTemplateSummary))
            cachedProductDetails = knownProducts
            for product in products {
                cachedProductDetails[product.id] = product
            }
            persistCatalogSnapshot()
            lastErrorMessage = nil
            scheduleMyProductSubmissionsWarmup()
            scheduleSharePayloadWarmup()
        } catch {
            if authService?.isAuthenticated == false {
                recipes = []
                products = []
                mealTemplates = []
                cachedProductDetails = [:]
                resetMyProductSubmissionCache()
                resetSharePayloadCache()
            }
            storeLastError(error)
        }
    }

    func loadVisibleCatalog(for userID: String) async -> FriendVisibleCatalog? {
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authService != nil, !trimmedUserID.isEmpty else { return nil }

        do {
            let (productsResponse, recipesResponse, mealTemplatesResponse) = try await withAuthenticatedMetadata { metadata in
                async let remoteProducts: Food_ListUserProductsResponse = withFoodClient { client in
                    var request = Food_ListUserProductsRequest()
                    request.userID = trimmedUserID
                    return try await client.listUserProducts(request, metadata: metadata)
                }
                async let remoteRecipes: Food_ListUserRecipesResponse = withFoodClient { client in
                    var request = Food_ListUserRecipesRequest()
                    request.userID = trimmedUserID
                    return try await client.listUserRecipes(request, metadata: metadata)
                }
                async let remoteMealTemplates: Food_ListUserMealTemplatesResponse = withFoodClient { client in
                    var request = Food_ListUserMealTemplatesRequest()
                    request.userID = trimmedUserID
                    return try await client.listUserMealTemplates(request, metadata: metadata)
                }

                return try await (remoteProducts, remoteRecipes, remoteMealTemplates)
            }

            let products = sortedProducts(productsResponse.products.compactMap(Self.makeProductSummary))
            for product in products {
                cachedProductDetails[product.id] = product
            }
            persistCatalogSnapshot()

            lastErrorMessage = nil
            return FriendVisibleCatalog(
                products: products,
                recipes: sortedRecipes(recipesResponse.recipes.compactMap(Self.makeRecipeSummary)),
                mealTemplates: sortedMealTemplates(mealTemplatesResponse.mealTemplates.compactMap(Self.makeMealTemplateSummary))
            )
        } catch {
            storeLastError(error)
            return nil
        }
    }

    private func scheduleMyProductSubmissionsWarmup(force: Bool = false) {
        guard authService != nil else { return }

        if !force,
           let cachedAt = cachedMyProductSubmissionsAt,
           Date().timeIntervalSince(cachedAt) < Self.myProductSubmissionsCacheTTL {
            return
        }

        if let existingTask = myProductSubmissionsWarmupTask {
            if force {
                existingTask.cancel()
                myProductSubmissionsWarmupTask = nil
            } else {
                return
            }
        }

        myProductSubmissionsWarmupTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.listMyProductSubmissions(forceRefresh: force)
            if !Task.isCancelled {
                self.myProductSubmissionsWarmupTask = nil
            }
        }
    }

    private func resetMyProductSubmissionCache() {
        myProductSubmissionsWarmupTask?.cancel()
        myProductSubmissionsWarmupTask = nil
        cachedMyProductSubmissions = []
        cachedMyProductSubmissionsAt = nil
    }

    private func resetSharePayloadCache() {
        shareWarmupTask?.cancel()
        shareWarmupTask = nil
        shareWarmupSignature = nil
        productShareTasks.values.forEach { $0.cancel() }
        recipeShareTasks.values.forEach { $0.cancel() }
        mealTemplateShareTasks.values.forEach { $0.cancel() }
        productShareTasks = [:]
        recipeShareTasks = [:]
        mealTemplateShareTasks = [:]
        productSharePayloads = [:]
        recipeSharePayloads = [:]
        mealTemplateSharePayloads = [:]
    }

    private func scheduleSharePayloadWarmup(force: Bool = false) {
        guard authService != nil else { return }

        let productIDs = products.map(\.id)
        let recipeIDs = recipes.map(\.id)
        let mealTemplateIDs = mealTemplates.map(\.id)
        guard !productIDs.isEmpty || !recipeIDs.isEmpty || !mealTemplateIDs.isEmpty else {
            shareWarmupTask?.cancel()
            shareWarmupTask = nil
            shareWarmupSignature = nil
            return
        }

        let signature = shareWarmupSourceSignature(productIDs: productIDs, recipeIDs: recipeIDs, mealTemplateIDs: mealTemplateIDs)
        if !force, shareWarmupSignature == signature {
            let hasMissingPayloads = hasMissingSharePayloads(
                productIDs: productIDs,
                recipeIDs: recipeIDs,
                mealTemplateIDs: mealTemplateIDs
            )
            if shareWarmupTask != nil || !hasMissingPayloads {
                return
            }
        }

        shareWarmupTask?.cancel()
        shareWarmupSignature = signature
        shareWarmupTask = Task { [weak self, productIDs, recipeIDs, mealTemplateIDs, signature] in
            guard let self else { return }

            for id in productIDs {
                guard !Task.isCancelled else { return }
                _ = await self.silentlyShareUserProduct(id: id)
            }
            for id in recipeIDs {
                guard !Task.isCancelled else { return }
                _ = await self.silentlyShareRecipe(id: id)
            }
            for id in mealTemplateIDs {
                guard !Task.isCancelled else { return }
                _ = await self.silentlyShareMealTemplate(id: id)
            }

            if !Task.isCancelled, self.shareWarmupSignature == signature {
                self.shareWarmupTask = nil
            }
        }
    }

    private func shareWarmupSourceSignature(productIDs: [UUID], recipeIDs: [UUID], mealTemplateIDs: [UUID]) -> String {
        let productPart = productIDs.map(\.uuidString).joined(separator: "|")
        let recipePart = recipeIDs.map(\.uuidString).joined(separator: "|")
        let mealTemplatePart = mealTemplateIDs.map(\.uuidString).joined(separator: "|")
        return "products=\(productPart);recipes=\(recipePart);mealTemplates=\(mealTemplatePart)"
    }

    private func hasMissingSharePayloads(productIDs: [UUID], recipeIDs: [UUID], mealTemplateIDs: [UUID]) -> Bool {
        productIDs.contains { productSharePayloads[$0] == nil }
            || recipeIDs.contains { recipeSharePayloads[$0] == nil }
            || mealTemplateIDs.contains { mealTemplateSharePayloads[$0] == nil }
    }

    @discardableResult
    func saveProduct(_ draft: ProductDraft) async -> ProductSummary? {
        guard authService != nil else { return nil }

        do {
            let response: Food_Product = try await withAuthenticatedMetadata { metadata in
                let product = makeProduct(from: draft)
                return try await withFoodClient { client in
                    if draft.productID != nil {
                        var request = Food_UpdateCustomProductRequest()
                        request.product = product
                        return try await client.updateCustomProduct(request, metadata: metadata).product
                    }

                    var request = Food_CreateCustomProductRequest()
                    request.product = product
                    return try await client.createCustomProduct(request, metadata: metadata).product
                }
            }

            lastErrorMessage = nil
            return ingest(product: response)
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func deleteProduct(id: UUID) async -> Bool {
        guard authService != nil else { return false }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_DeleteCustomProductRequest()
                request.productID = id.uuidString
                return try await withFoodClient { client in
                    try await client.deleteCustomProduct(request, metadata: metadata)
                }
            }
            if response.success {
                products.removeAll(where: { $0.id == id })
                cachedProductDetails.removeValue(forKey: id)
                productSharePayloads.removeValue(forKey: id)
                productShareTasks[id]?.cancel()
                productShareTasks.removeValue(forKey: id)
                persistCatalogSnapshot()
            }
            lastErrorMessage = nil
            return response.success
        } catch {
            storeLastError(error)
            return false
        }
    }

    @discardableResult
    func saveRecipe(_ draft: RecipeDraft) async -> RecipeSummary? {
        guard authService != nil else { return nil }

        do {
            let summary = try await withAuthenticatedMetadata { metadata in
                let payload = makeRecipe(from: draft)
                let saved: Food_Recipe = try await withFoodClient { client in
                    if draft.recipeID != nil {
                        var request = Food_UpdateRecipeRequest()
                        request.recipe = payload
                        return try await client.updateRecipe(request, metadata: metadata).recipe
                    }

                    var request = Food_CreateRecipeRequest()
                    request.recipe = payload
                    return try await client.createRecipe(request, metadata: metadata).recipe
                }

                guard let summary = ingest(recipe: saved) else {
                    throw NSError(domain: "FoodCatalogService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Food service вернул некорректный рецепт."])
                }
                return summary
            }

            lastErrorMessage = nil
            return summary
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func deleteRecipe(id: UUID) async -> Bool {
        guard authService != nil else { return false }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_DeleteRecipeRequest()
                request.recipeID = id.uuidString
                return try await withFoodClient { client in
                    try await client.deleteRecipe(request, metadata: metadata)
                }
            }
            if response.success {
                recipes.removeAll(where: { $0.id == id })
                recipeSharePayloads.removeValue(forKey: id)
                recipeShareTasks[id]?.cancel()
                recipeShareTasks.removeValue(forKey: id)
                persistCatalogSnapshot()
            }
            lastErrorMessage = nil
            return response.success
        } catch {
            storeLastError(error)
            return false
        }
    }

    func shareRecipe(id: UUID) async -> FoodSharePayload? {
        if let payload = recipeSharePayloads[id] {
            return payload
        }
        if let task = recipeShareTasks[id] {
            return await task.value
        }

        let scopeID = cacheScopeID
		let task: Task<FoodSharePayload?, Never> = Task { [weak self] in
            guard let self else { return nil }
            let payload = await self.fetchRecipeSharePayload(id: id)
            guard !Task.isCancelled, self.cacheScopeID == scopeID else { return payload }
            if let payload {
                self.recipeSharePayloads[id] = payload
            }
            self.recipeShareTasks[id] = nil
            return payload
        }
        recipeShareTasks[id] = task
        return await task.value
    }

    private func fetchRecipeSharePayload(id: UUID) async -> FoodSharePayload? {
        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ShareRecipeRequest()
                request.recipeID = id.uuidString
                return try await withFoodClient { client in
                    try await client.shareRecipe(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return FoodSharePayload(
                title: recipeSummary(id: id)?.title ?? NSLocalizedString("recipe.fallback_title", comment: "Fallback recipe title"),
                shareCode: response.shareCode,
                shareURL: response.shareURL
            )
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func previewSharedRecipe(code: String) async -> RecipeSummary? {
        guard authService != nil else { return nil }

        do {
            guard let normalizedCode = sharedRecipeReference(from: code) else {
                lastErrorMessage = NSLocalizedString("recipe.import.invalid_reference", comment: "Invalid shared recipe reference")
                return nil
            }
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetSharedRecipeRequest()
                request.shareCode = normalizedCode
                return try await withFoodClient { client in
                    try await client.getSharedRecipe(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return Self.makeRecipeSummary(response.recipe)
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func importSharedRecipe(code: String) async -> RecipeSummary? {
        guard authService != nil else { return nil }

        do {
            guard let normalizedCode = sharedRecipeReference(from: code) else {
                lastErrorMessage = NSLocalizedString("recipe.import.invalid_reference", comment: "Invalid shared recipe reference")
                return nil
            }
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_SaveSharedRecipeRequest()
                request.shareCode = normalizedCode
                return try await withFoodClient { client in
                    try await client.saveSharedRecipe(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return ingest(recipe: response.recipe)
        } catch let error as RPCError {
            if error.code == .alreadyExists {
                lastErrorMessage = NSLocalizedString("recipe.import.already_exists", comment: "Shared recipe already imported")
            } else {
                storeLastError(error)
            }
            return nil
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func shareUserProduct(id: UUID) async -> FoodSharePayload? {
        if let payload = productSharePayloads[id] {
            return payload
        }
        if let task = productShareTasks[id] {
            return await task.value
        }

        let scopeID = cacheScopeID
		let task: Task<FoodSharePayload?, Never> = Task { [weak self] in
            guard let self else { return nil }
            let payload = await self.fetchUserProductSharePayload(id: id)
            guard !Task.isCancelled, self.cacheScopeID == scopeID else { return payload }
            if let payload {
                self.productSharePayloads[id] = payload
            }
            self.productShareTasks[id] = nil
            return payload
        }
        productShareTasks[id] = task
        return await task.value
    }

    private func fetchUserProductSharePayload(id: UUID) async -> FoodSharePayload? {
        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ShareUserProductRequest()
                request.productID = id.uuidString
                return try await withFoodClient { client in
                    try await client.shareUserProduct(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return FoodSharePayload(
                title: productSummary(id: id)?.name ?? NSLocalizedString("product.fallback_title", value: "Product", comment: "Fallback product title"),
                shareCode: response.shareCode,
                shareURL: response.shareURL
            )
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func previewSharedUserProduct(code: String) async -> ProductSummary? {
        guard authService != nil else { return nil }

        do {
            guard let normalizedCode = sharedUserProductReference(from: code) else {
                lastErrorMessage = NSLocalizedString("product.import.invalid_reference", value: "Invalid shared product reference", comment: "Invalid shared product reference")
                return nil
            }
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetSharedUserProductRequest()
                request.shareCode = normalizedCode
                return try await withFoodClient { client in
                    try await client.getSharedUserProduct(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return Self.makeProductSummary(response.product)
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func importSharedUserProduct(code: String) async -> ProductSummary? {
        guard authService != nil else { return nil }

        do {
            guard let normalizedCode = sharedUserProductReference(from: code) else {
                lastErrorMessage = NSLocalizedString("product.import.invalid_reference", value: "Invalid shared product reference", comment: "Invalid shared product reference")
                return nil
            }
            let sharedProduct = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetSharedUserProductRequest()
                request.shareCode = normalizedCode
                return try await withFoodClient { client in
                    try await client.getSharedUserProduct(request, metadata: metadata).product
                }
            }
            let sharedSummary = Self.makeProductSummary(sharedProduct)
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_SaveSharedUserProductRequest()
                request.shareCode = normalizedCode
                return try await withFoodClient { client in
                    try await client.saveSharedUserProduct(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            let responseSummary = response.hasProduct ? ingest(product: response.product) : nil
            await reloadCatalog()

            if let responseSummary,
               let importedProduct = productSummary(id: responseSummary.id) ?? matchingLibraryProduct(for: responseSummary) {
                return importedProduct
            }

            if let sharedSummary,
               let importedProduct = matchingLibraryProduct(for: sharedSummary) {
                return importedProduct
            }

            if let responseSummary {
                upsertProduct(responseSummary)
                return responseSummary
            }

            lastErrorMessage = NSLocalizedString("product.import.failed", value: "Could not add this product to your library.", comment: "Shared product import failed")
            return nil
        } catch let error as RPCError {
            if error.code == .alreadyExists {
                lastErrorMessage = NSLocalizedString("product.import.already_exists", value: "Product already imported", comment: "Shared product already imported")
            } else {
                storeLastError(error)
            }
            return nil
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func saveMealTemplate(_ draft: MealTemplateDraft) async -> MealTemplateSummary? {
        guard authService != nil else { return nil }

        do {
            let summary = try await withAuthenticatedMetadata { metadata in
                let payload = makeMealTemplate(from: draft)
                let saved: Food_MealTemplate = try await withFoodClient { client in
                    if draft.mealTemplateID != nil {
                        var request = Food_UpdateMealTemplateRequest()
                        request.mealTemplate = payload
                        return try await client.updateMealTemplate(request, metadata: metadata).mealTemplate
                    }

                    var request = Food_CreateMealTemplateRequest()
                    request.mealTemplate = payload
                    return try await client.createMealTemplate(request, metadata: metadata).mealTemplate
                }

                guard let summary = ingest(mealTemplate: saved) else {
                    throw NSError(domain: "FoodCatalogService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Food service returned an invalid ration."])
                }
                return summary
            }

            lastErrorMessage = nil
            return summary
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func deleteMealTemplate(id: UUID) async -> Bool {
        guard authService != nil else { return false }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_DeleteMealTemplateRequest()
                request.mealTemplateID = id.uuidString
                return try await withFoodClient { client in
                    try await client.deleteMealTemplate(request, metadata: metadata)
                }
            }
            if response.success {
                mealTemplates.removeAll(where: { $0.id == id })
                mealTemplateSharePayloads.removeValue(forKey: id)
                mealTemplateShareTasks[id]?.cancel()
                mealTemplateShareTasks.removeValue(forKey: id)
                persistCatalogSnapshot()
            }
            lastErrorMessage = nil
            return response.success
        } catch {
            storeLastError(error)
            return false
        }
    }

    func shareMealTemplate(id: UUID) async -> FoodSharePayload? {
        if let payload = mealTemplateSharePayloads[id] {
            return payload
        }
        if let task = mealTemplateShareTasks[id] {
            return await task.value
        }

        let scopeID = cacheScopeID
		let task: Task<FoodSharePayload?, Never> = Task { [weak self] in
            guard let self else { return nil }
            let payload = await self.fetchMealTemplateSharePayload(id: id)
            guard !Task.isCancelled, self.cacheScopeID == scopeID else { return payload }
            if let payload {
                self.mealTemplateSharePayloads[id] = payload
            }
            self.mealTemplateShareTasks[id] = nil
            return payload
        }
        mealTemplateShareTasks[id] = task
        return await task.value
    }

    private func fetchMealTemplateSharePayload(id: UUID) async -> FoodSharePayload? {
        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ShareMealTemplateRequest()
                request.mealTemplateID = id.uuidString
                return try await withFoodClient { client in
                    try await client.shareMealTemplate(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return FoodSharePayload(
                title: mealTemplateSummary(id: id)?.title ?? "Ration",
                shareCode: response.shareCode,
                shareURL: response.shareURL
            )
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func previewSharedMealTemplate(code: String) async -> MealTemplateSummary? {
        guard authService != nil else { return nil }

        do {
            guard let normalizedCode = sharedMealTemplateReference(from: code) else {
                lastErrorMessage = NSLocalizedString("mealtemplate.import.invalid_reference", tableName: nil, bundle: .main, value: "Invalid ration link", comment: "Invalid ration reference")
                return nil
            }
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetSharedMealTemplateRequest()
                request.shareCode = normalizedCode
                return try await withFoodClient { client in
                    try await client.getSharedMealTemplate(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return Self.makeMealTemplateSummary(response.mealTemplate)
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func importSharedMealTemplate(code: String) async -> MealTemplateSummary? {
        guard authService != nil else { return nil }

        do {
            guard let normalizedCode = sharedMealTemplateReference(from: code) else {
                lastErrorMessage = NSLocalizedString("mealtemplate.import.invalid_reference", tableName: nil, bundle: .main, value: "Invalid ration link", comment: "Invalid ration reference")
                return nil
            }
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_SaveSharedMealTemplateRequest()
                request.shareCode = normalizedCode
                return try await withFoodClient { client in
                    try await client.saveSharedMealTemplate(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return ingest(mealTemplate: response.mealTemplate)
        } catch let error as RPCError {
            if error.code == .alreadyExists {
                lastErrorMessage = NSLocalizedString(
                    "mealtemplate.import.already_exists",
                    tableName: nil,
                    bundle: .main,
                    value: "You already have this ration.",
                    comment: "Shared ration already imported"
                )
            } else {
                storeLastError(error)
            }
            return nil
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func clear() {
        recipes = []
        products = []
        mealTemplates = []
        recipeEditorStore = nil
        cachedProductDetails = [:]
        resetSharePayloadCache()
        favoriteProductIDs = []
        favoriteProductSummaries = []
        favoriteRecipeIDs = []
        favoriteMealTemplateIDs = []
        CachedJSONStore.remove(key: Self.favoritesCacheKeyPrefix + cacheScopeID)
        CachedJSONStore.remove(key: Self.favoriteRecipesCacheKeyPrefix + cacheScopeID)
        CachedJSONStore.remove(key: Self.favoriteMealTemplatesCacheKeyPrefix + cacheScopeID)
        lastErrorMessage = nil
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func loadFavoriteProducts() async {
        guard authService != nil else { return }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                return try await withFoodClient { client in
                    try await client.listFavoriteProducts(Food_ListFavoriteProductsRequest(), metadata: metadata)
                }
            }
            let summaries = response.products.compactMap(Self.makeProductSummary)
            let ids = Set(summaries.map(\.id))
            favoriteProductIDs = ids
            favoriteProductSummaries = sortedProducts(summaries)
            for product in summaries {
                cachedProductDetails[product.id] = product
            }
            persistFavorites()
            lastErrorMessage = nil
        } catch {
            storeLastError(error)
        }
    }

    func toggleFavorite(productID: UUID) async {
        guard authService != nil else { return }
        let isFavorite = favoriteProductIDs.contains(productID)
        let previousSummaries = favoriteProductSummaries
        if isFavorite {
            favoriteProductIDs.remove(productID)
            favoriteProductSummaries.removeAll { $0.id == productID }
        } else {
            favoriteProductIDs.insert(productID)
            if let summary = productSummary(id: productID) {
                favoriteProductSummaries = sortedProducts(favoriteProductSummaries + [summary])
            }
        }
        persistFavorites()
        do {
            if isFavorite {
                _ = try await withAuthenticatedMetadata { metadata in
                    return try await withFoodClient { client in
                        var request = Food_RemoveFavoriteProductRequest()
                        request.productID = productID.uuidString
                        return try await client.removeFavoriteProduct(request, metadata: metadata)
                    }
                }
            } else {
                _ = try await withAuthenticatedMetadata { metadata in
                    return try await withFoodClient { client in
                        var request = Food_AddFavoriteProductRequest()
                        request.productID = productID.uuidString
                        return try await client.addFavoriteProduct(request, metadata: metadata)
                    }
                }
            }
            lastErrorMessage = nil
        } catch {
            if isFavorite {
                favoriteProductIDs.insert(productID)
            } else {
                favoriteProductIDs.remove(productID)
            }
            favoriteProductSummaries = previousSummaries
            persistFavorites()
            storeLastError(error)
        }
    }

    func isFavorite(_ productID: UUID) -> Bool {
        favoriteProductIDs.contains(productID)
    }

    var favoriteRecipeSummaries: [RecipeSummary] {
        sortedRecipes(recipes.filter { favoriteRecipeIDs.contains($0.id) })
    }

    var favoriteMealTemplateSummaries: [MealTemplateSummary] {
        sortedMealTemplates(mealTemplates.filter { favoriteMealTemplateIDs.contains($0.id) })
    }

    func isFavoriteRecipe(_ recipeID: UUID) -> Bool {
        favoriteRecipeIDs.contains(recipeID)
    }

    func isFavoriteMealTemplate(_ mealTemplateID: UUID) -> Bool {
        favoriteMealTemplateIDs.contains(mealTemplateID)
    }

    func toggleFavoriteRecipe(_ recipeID: UUID) async {
        guard authService != nil else { return }
        let isFavorite = favoriteRecipeIDs.contains(recipeID)
        if isFavorite {
            favoriteRecipeIDs.remove(recipeID)
        } else {
            favoriteRecipeIDs.insert(recipeID)
        }
        persistFavoriteIDs(favoriteRecipeIDs, keyPrefix: Self.favoriteRecipesCacheKeyPrefix)
        do {
            if isFavorite {
                _ = try await withAuthenticatedMetadata { metadata in
                    return try await withFoodClient { client in
                        var request = Food_RemoveFavoriteRecipeRequest()
                        request.recipeID = recipeID.uuidString
                        return try await client.removeFavoriteRecipe(request, metadata: metadata)
                    }
                }
            } else {
                _ = try await withAuthenticatedMetadata { metadata in
                    return try await withFoodClient { client in
                        var request = Food_AddFavoriteRecipeRequest()
                        request.recipeID = recipeID.uuidString
                        return try await client.addFavoriteRecipe(request, metadata: metadata)
                    }
                }
            }
            lastErrorMessage = nil
        } catch {
            if isFavorite {
                favoriteRecipeIDs.insert(recipeID)
            } else {
                favoriteRecipeIDs.remove(recipeID)
            }
            persistFavoriteIDs(favoriteRecipeIDs, keyPrefix: Self.favoriteRecipesCacheKeyPrefix)
            storeLastError(error)
        }
    }

    func toggleFavoriteMealTemplate(_ mealTemplateID: UUID) async {
        guard authService != nil else { return }
        let isFavorite = favoriteMealTemplateIDs.contains(mealTemplateID)
        if isFavorite {
            favoriteMealTemplateIDs.remove(mealTemplateID)
        } else {
            favoriteMealTemplateIDs.insert(mealTemplateID)
        }
        persistFavoriteIDs(favoriteMealTemplateIDs, keyPrefix: Self.favoriteMealTemplatesCacheKeyPrefix)
        do {
            if isFavorite {
                _ = try await withAuthenticatedMetadata { metadata in
                    return try await withFoodClient { client in
                        var request = Food_RemoveFavoriteMealTemplateRequest()
                        request.mealTemplateID = mealTemplateID.uuidString
                        return try await client.removeFavoriteMealTemplate(request, metadata: metadata)
                    }
                }
            } else {
                _ = try await withAuthenticatedMetadata { metadata in
                    return try await withFoodClient { client in
                        var request = Food_AddFavoriteMealTemplateRequest()
                        request.mealTemplateID = mealTemplateID.uuidString
                        return try await client.addFavoriteMealTemplate(request, metadata: metadata)
                    }
                }
            }
            lastErrorMessage = nil
        } catch {
            if isFavorite {
                favoriteMealTemplateIDs.insert(mealTemplateID)
            } else {
                favoriteMealTemplateIDs.remove(mealTemplateID)
            }
            persistFavoriteIDs(favoriteMealTemplateIDs, keyPrefix: Self.favoriteMealTemplatesCacheKeyPrefix)
            storeLastError(error)
        }
    }

    func loadFavoriteRecipes() async {
        guard authService != nil else { return }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                return try await withFoodClient { client in
                    try await client.listFavoriteRecipeIDs(Food_ListFavoriteRecipeIDsRequest(), metadata: metadata)
                }
            }
            let ids = Set(response.recipeIds.compactMap { UUID(uuidString: $0) })
            favoriteRecipeIDs = ids
            persistFavoriteIDs(ids, keyPrefix: Self.favoriteRecipesCacheKeyPrefix)
            lastErrorMessage = nil
        } catch {
            storeLastError(error)
        }
    }

    func loadFavoriteMealTemplates() async {
        guard authService != nil else { return }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                return try await withFoodClient { client in
                    try await client.listFavoriteMealTemplateIDs(Food_ListFavoriteMealTemplateIDsRequest(), metadata: metadata)
                }
            }
            let ids = Set(response.mealTemplateIds.compactMap { UUID(uuidString: $0) })
            favoriteMealTemplateIDs = ids
            persistFavoriteIDs(ids, keyPrefix: Self.favoriteMealTemplatesCacheKeyPrefix)
            lastErrorMessage = nil
        } catch {
            storeLastError(error)
        }
    }

    private func persistFavoriteIDs(_ ids: Set<UUID>, keyPrefix: String) {
        let sorted = ids.map(\.uuidString).sorted()
        CachedJSONStore.save(sorted, key: keyPrefix + cacheScopeID)
    }

    private static func loadCachedFavoriteIDs(keyPrefix: String, scopeID: String) -> Set<UUID> {
        guard let ids = CachedJSONStore.load([String].self, key: keyPrefix + scopeID) else {
            return []
        }
        return Set(ids.compactMap { UUID(uuidString: $0) })
    }

    private func persistFavorites() {
        let ids = favoriteProductIDs.map(\.uuidString).sorted()
        CachedJSONStore.save(ids, key: Self.favoritesCacheKeyPrefix + cacheScopeID)
    }

    private static func loadCachedFavorites(scopeID: String) -> Set<UUID> {
        guard let ids = CachedJSONStore.load([String].self, key: favoritesCacheKeyPrefix + scopeID) else {
            return []
        }
        return Set(ids.compactMap { UUID(uuidString: $0) })
    }

    func storeLastError(_ error: Error) {
        if error is CancellationError {
            lastErrorMessage = nil
            return
        }
        let msg = String(describing: error).lowercased()
        let nsError = error as NSError
        if nsError.code == 401 || msg.contains("не удалось авторизовать") || msg.contains("unauthenticated") || Task.isCancelled || msg.contains("cancelled") || msg.contains("client stopped") {
            lastErrorMessage = nil
            return
        }
        lastErrorMessage = Self.genericUserFacingErrorMessage
    }

    private static var genericUserFacingErrorMessage: String {
        NSLocalizedString(
            "food.service.generic_error",
            tableName: nil,
            bundle: .main,
            value: "Something went wrong. Try again.",
            comment: "Generic food service error"
        )
    }

    func productSummary(id: UUID) -> ProductSummary? {
        products.first(where: { $0.id == id }) ?? cachedProductDetails[id]
    }

    func recipeSummary(id: UUID) -> RecipeSummary? {
        recipes.first(where: { $0.id == id })
    }

    func mealTemplateSummary(id: UUID) -> MealTemplateSummary? {
        mealTemplates.first(where: { $0.id == id })
    }

    func fetchProductSnapshot(id: UUID) async -> ProductSummary? {
        if let ownedProduct = products.first(where: { $0.id == id }) {
            return ownedProduct
        }

        if let cachedProduct = cachedProductDetails[id] {
            return cachedProduct
        }

        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetProductRequest()
                request.productID = id.uuidString
                return try await withFoodClient { client in
                    try await client.getProduct(request, metadata: metadata).product
                }
            }

            guard let summary = Self.makeProductSummary(response) else {
                return nil
            }
            cachedProductDetails[id] = summary
            persistCatalogSnapshot()
            return summary
        } catch {
            return nil
        }
    }

    func fetchRecipeSnapshot(id: UUID) async -> RecipeSummary? {
        if let cachedRecipe = recipeSummary(id: id) {
            return cachedRecipe
        }

        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetRecipeRequest()
                request.recipeID = id.uuidString
                return try await withFoodClient { client in
                    try await client.getRecipe(request, metadata: metadata).recipe
                }
            }

            return Self.makeRecipeSummary(response)
        } catch {
            return nil
        }
    }

    func fetchMealTemplateSnapshot(id: UUID) async -> MealTemplateSummary? {
        if let cachedMealTemplate = mealTemplateSummary(id: id) {
            return cachedMealTemplate
        }

        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetMealTemplateRequest()
                request.mealTemplateID = id.uuidString
                return try await withFoodClient { client in
                    try await client.getMealTemplate(request, metadata: metadata).mealTemplate
                }
            }

            return Self.makeMealTemplateSummary(response)
        } catch {
            return nil
        }
    }

    @discardableResult
    func fetchProduct(id: UUID) async -> ProductSummary? {
        if let ownedProduct = products.first(where: { $0.id == id }) {
            return ownedProduct
        }

        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetProductRequest()
                request.productID = id.uuidString
                return try await withFoodClient { client in
                    try await client.getProduct(request, metadata: metadata).product
                }
            }

            lastErrorMessage = nil
            guard let summary = Self.makeProductSummary(response) else {
                return nil
            }
            cachedProductDetails[id] = summary
            persistCatalogSnapshot()
            return summary
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func fetchRecipe(id: UUID) async -> RecipeSummary? {
        if let cached = recipeSummary(id: id) {
            return cached
        }

        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetRecipeRequest()
                request.recipeID = id.uuidString
                return try await withFoodClient { client in
                    try await client.getRecipe(request, metadata: metadata).recipe
                }
            }

            lastErrorMessage = nil
            return ingest(recipe: response)
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func fetchMealTemplate(id: UUID) async -> MealTemplateSummary? {
        if let cached = mealTemplateSummary(id: id) {
            return cached
        }

        guard authService != nil else { return nil }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetMealTemplateRequest()
                request.mealTemplateID = id.uuidString
                return try await withFoodClient { client in
                    try await client.getMealTemplate(request, metadata: metadata).mealTemplate
                }
            }

            lastErrorMessage = nil
            return ingest(mealTemplate: response)
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func sharedRecipeReference(from rawValue: String) -> String? {
        guard let normalizedCode = normalizedShareCode(from: rawValue) else {
            return nil
        }

        return normalizedCode.lowercased().hasPrefix("rshare") ? normalizedCode : nil
    }

    /// Meal-template codes, which the service issues as `tshare_…`.
    ///
    /// This read `mtshare`, which the service has never produced — so every
    /// meal-template link fell through all four checks and opened nothing at
    /// all.
    func sharedMealTemplateReference(from rawValue: String) -> String? {
        guard let normalizedCode = normalizedShareCode(from: rawValue) else {
            return nil
        }

        return normalizedCode.lowercased().hasPrefix("tshare") ? normalizedCode : nil
    }

    func sharedMealReference(from rawValue: String) -> String? {
        guard let normalizedCode = normalizedShareCode(from: rawValue) else {
            return nil
        }

        return normalizedCode.lowercased().hasPrefix("mshare") ? normalizedCode : nil
    }

    func sharedUserProductReference(from rawValue: String) -> String? {
        guard let normalizedCode = normalizedShareCode(from: rawValue) else {
            return nil
        }

        return normalizedCode.lowercased().hasPrefix("pshare") ? normalizedCode : nil
    }

    @discardableResult
    func ingest(product: Food_Product) -> ProductSummary? {
        guard let summary = Self.makeProductSummary(product) else { return nil }
        upsertProduct(summary)
        return summary
    }

    @discardableResult
    func ingest(recipe: Food_Recipe) -> RecipeSummary? {
        guard let summary = Self.makeRecipeSummary(recipe) else { return nil }
        upsertRecipe(summary)
        return summary
    }

    @discardableResult
    func ingest(mealTemplate: Food_MealTemplate) -> MealTemplateSummary? {
        guard let summary = Self.makeMealTemplateSummary(mealTemplate) else { return nil }
        upsertMealTemplate(summary)
        return summary
    }

    private func upsertProduct(_ product: ProductSummary) {
        products.removeAll(where: { $0.id == product.id })
        products.append(product)
        products = sortedProducts(products)
        cachedProductDetails[product.id] = product
        persistCatalogSnapshot()
    }

    private func matchingLibraryProduct(for product: ProductSummary) -> ProductSummary? {
        let fingerprint = Self.productImportFingerprint(product)
        return products.first { Self.productImportFingerprint($0) == fingerprint }
    }

    private static func productImportFingerprint(_ product: ProductSummary) -> String {
        [
            normalizedImportText(product.name),
            normalizedImportText(product.brand),
            String(product.caloriesPer100g),
            String(product.proteinPer100g),
            String(product.fatPer100g),
            String(product.carbsPer100g)
        ].joined(separator: "||")
    }

    private static func normalizedImportText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func upsertRecipe(_ recipe: RecipeSummary) {
        recipes.removeAll(where: { $0.id == recipe.id })
        recipes.append(recipe)
        recipes = sortedRecipes(recipes)
        persistCatalogSnapshot()
    }

    private func upsertMealTemplate(_ mealTemplate: MealTemplateSummary) {
        mealTemplates.removeAll(where: { $0.id == mealTemplate.id })
        mealTemplates.append(mealTemplate)
        mealTemplates = sortedMealTemplates(mealTemplates)
        persistCatalogSnapshot()
    }

    private func applyCatalogSnapshot(_ snapshot: CatalogCacheSnapshot?, resetWhenMissing: Bool) {
        guard let snapshot else {
            if resetWhenMissing {
                products = []
                recipes = []
                mealTemplates = []
                cachedProductDetails = [:]
            }
            return
        }

        products = sortedProducts(snapshot.products)
        recipes = sortedRecipes(snapshot.recipes)
        mealTemplates = sortedMealTemplates(snapshot.mealTemplates)
        cachedProductDetails = Self.knownProducts(from: snapshot)
    }

    private func persistCatalogSnapshot() {
        guard authService != nil else { return }

        let snapshot = CatalogCacheSnapshot(
            products: sortedProducts(products),
            recipes: sortedRecipes(recipes),
            mealTemplates: sortedMealTemplates(mealTemplates),
            knownProducts: sortedProducts(Array(cachedProductDetails.values))
        )
        CachedJSONStore.save(snapshot, key: Self.catalogCacheKeyPrefix + cacheScopeID)
        scheduleMessagesPickerSnapshotRefresh()
        scheduleSharePayloadWarmup()
    }

    func refreshMessagesPickerSnapshot(force: Bool = false) async {
        scheduleMessagesPickerSnapshotRefresh(force: force)
        await messagesPickerRefreshTask?.value
    }

    private static func loadCatalogSnapshot(scopeID: String) -> CatalogCacheSnapshot? {
        CachedJSONStore.load(CatalogCacheSnapshot.self, key: catalogCacheKeyPrefix + scopeID)
    }

    private static func knownProducts(from snapshot: CatalogCacheSnapshot?) -> [UUID: ProductSummary] {
        guard let snapshot else { return [:] }

        var knownProducts: [UUID: ProductSummary] = [:]
        for product in snapshot.knownProducts {
            knownProducts[product.id] = product
        }
        for product in snapshot.products {
            knownProducts[product.id] = product
        }
        return knownProducts
    }

    private func sortedProducts(_ products: [ProductSummary]) -> [ProductSummary] {
        Self.sortedProducts(products, sort: .addedNewest)
    }

    private func sortedRecipes(_ recipes: [RecipeSummary]) -> [RecipeSummary] {
        Self.sortedRecipes(recipes, sort: .addedNewest)
    }

    private func sortedMealTemplates(_ mealTemplates: [MealTemplateSummary]) -> [MealTemplateSummary] {
        Self.sortedMealTemplates(mealTemplates, sort: .addedNewest)
    }

    private static func sortedProducts(_ products: [ProductSummary], sort: AppSettings.ListSort) -> [ProductSummary] {
        products.sorted { lhs, rhs in
            switch sort {
            case .titleAsc:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .titleDesc:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            case .addedNewest:
                return compareAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: true, lhsTitle: lhs.name, rhsTitle: rhs.name)
            case .addedOldest:
                return compareAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: false, lhsTitle: lhs.name, rhsTitle: rhs.name)
            }
        }
    }

    private static func sortedRecipes(_ recipes: [RecipeSummary], sort: AppSettings.ListSort) -> [RecipeSummary] {
        recipes.sorted { lhs, rhs in
            switch sort {
            case .titleAsc:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .titleDesc:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedDescending
            case .addedNewest:
                return compareAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: true, lhsTitle: lhs.title, rhsTitle: rhs.title)
            case .addedOldest:
                return compareAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: false, lhsTitle: lhs.title, rhsTitle: rhs.title)
            }
        }
    }

    private static func sortedMealTemplates(_ mealTemplates: [MealTemplateSummary], sort: AppSettings.ListSort) -> [MealTemplateSummary] {
        mealTemplates.sorted { lhs, rhs in
            switch sort {
            case .titleAsc:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .titleDesc:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedDescending
            case .addedNewest:
                return compareAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: true, lhsTitle: lhs.title, rhsTitle: rhs.title)
            case .addedOldest:
                return compareAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: false, lhsTitle: lhs.title, rhsTitle: rhs.title)
            }
        }
    }

    private static func compareAddedDate(_ lhs: Date?, _ rhs: Date?, newestFirst: Bool, lhsTitle: String, rhsTitle: String) -> Bool {
        let lhsDate = lhs ?? .distantPast
        let rhsDate = rhs ?? .distantPast
        if lhsDate != rhsDate {
            return newestFirst ? lhsDate > rhsDate : lhsDate < rhsDate
        }
        return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
    }

    private func applyCurrentSortToCatalog() {
        products = sortedProducts(products)
        recipes = sortedRecipes(recipes)
        mealTemplates = sortedMealTemplates(mealTemplates)
        favoriteProductSummaries = sortedProducts(favoriteProductSummaries)
        cachedProductDetails = Dictionary(uniqueKeysWithValues: sortedProducts(Array(cachedProductDetails.values)).map { ($0.id, $0) })
        persistCatalogSnapshot()
    }

    private func scheduleMessagesPickerSnapshotRefresh(force: Bool = false) {
        guard authService != nil, let sharedDefaults = Self.sharedDefaults else { return }

        let productCandidates = Array(products.prefix(Self.messagesPickerItemLimit))
        let recipeCandidates = Array(recipes.prefix(Self.messagesPickerItemLimit))
        let mealCandidates = Array(mealTemplates.prefix(Self.messagesPickerItemLimit))
        let signature = messagesPickerSourceSignature(products: productCandidates, recipes: recipeCandidates, meals: mealCandidates)

        if !force,
           sharedDefaults.string(forKey: Self.messagesPickerSnapshotSignatureKey) == signature {
            return
        }

        messagesPickerRefreshTask?.cancel()
        messagesPickerRefreshTask = Task { [weak self, productCandidates, recipeCandidates, mealCandidates, signature] in
            guard let self else { return }

            let productItems = await self.buildMessagesPickerProductItems(from: productCandidates)
            let recipeItems = await self.buildMessagesPickerRecipeItems(from: recipeCandidates)
            let mealItems = await self.buildMessagesPickerMealItems(from: mealCandidates)
            guard !Task.isCancelled else { return }

            let snapshot = MessagesPickerSnapshot(
                products: productItems,
                recipes: recipeItems,
                meals: mealItems,
                updatedAt: Date()
            )
            let didResolveAllItems = productItems.count == productCandidates.count && recipeItems.count == recipeCandidates.count && mealItems.count == mealCandidates.count
            self.persistMessagesPickerSnapshot(snapshot, signature: didResolveAllItems ? signature : nil)
            self.messagesPickerRefreshTask = nil
        }
    }

    private func messagesPickerSourceSignature(products: [ProductSummary], recipes: [RecipeSummary], meals: [MealTemplateSummary]) -> String {
        let productPart = products.map { "\($0.id.uuidString):\($0.name):\($0.updatedAt?.timeIntervalSince1970 ?? 0)" }.joined(separator: "|")
        let recipePart = recipes.map { "\($0.id.uuidString):\($0.title):\($0.updatedAt?.timeIntervalSince1970 ?? 0)" }.joined(separator: "|")
        let mealPart = meals.map { "\($0.id.uuidString):\($0.title):\($0.updatedAt?.timeIntervalSince1970 ?? 0)" }.joined(separator: "|")
        return "products=\(productPart);recipes=\(recipePart);meals=\(mealPart)"
    }

    private func persistMessagesPickerSnapshot(_ snapshot: MessagesPickerSnapshot, signature: String?) {
        guard let sharedDefaults = Self.sharedDefaults,
              let data = try? JSONEncoder().encode(snapshot) else { return }

        sharedDefaults.set(data, forKey: Self.messagesPickerSnapshotKey)

        if let signature {
            sharedDefaults.set(signature, forKey: Self.messagesPickerSnapshotSignatureKey)
        } else {
            sharedDefaults.removeObject(forKey: Self.messagesPickerSnapshotSignatureKey)
        }
    }

    private func buildMessagesPickerProductItems(from products: [ProductSummary]) async -> [MessagesPickerShareItem] {
        var items: [MessagesPickerShareItem] = []
        items.reserveCapacity(products.count)

        for product in products {
            guard let payload = await silentlyShareUserProduct(id: product.id),
                                    let shareURL = payload.resolvedSharePreviewLink else {
                continue
            }

            items.append(
                MessagesPickerShareItem(
                    kind: "product",
                    id: product.id.uuidString,
                    title: product.name,
                    subtitle: productMessagesSubtitle(for: product),
                    shareURL: shareURL,
                    shareSubject: payload.localizedShareSubject,
                    emoji: nil
                )
            )
        }

        return items
    }

    private func buildMessagesPickerRecipeItems(from recipes: [RecipeSummary]) async -> [MessagesPickerShareItem] {
        var items: [MessagesPickerShareItem] = []
        items.reserveCapacity(recipes.count)

        for recipe in recipes {
            guard let payload = await silentlyShareRecipe(id: recipe.id),
                                    let shareURL = payload.resolvedSharePreviewLink else {
                continue
            }

            items.append(
                MessagesPickerShareItem(
                    kind: "recipe",
                    id: recipe.id.uuidString,
                    title: recipe.title,
                    subtitle: recipeMessagesSubtitle(for: recipe),
                    shareURL: shareURL,
                    shareSubject: payload.localizedShareSubject,
                    emoji: normalizedRecipeEmoji(recipe.emoji)
                )
            )
        }

        return items
    }

    private func buildMessagesPickerMealItems(from meals: [MealTemplateSummary]) async -> [MessagesPickerShareItem] {
        var items: [MessagesPickerShareItem] = []
        items.reserveCapacity(meals.count)

        for meal in meals {
            guard let payload = await silentlyShareMealTemplate(id: meal.id),
                                    let shareURL = payload.resolvedSharePreviewLink else {
                continue
            }

            items.append(
                MessagesPickerShareItem(
                    kind: "meal",
                    id: meal.id.uuidString,
                    title: meal.title,
                    subtitle: mealMessagesSubtitle(for: meal),
                    shareURL: shareURL,
                    shareSubject: payload.localizedShareSubject,
                    emoji: nil
                )
            )
        }

        return items
    }

    private func silentlyShareUserProduct(id: UUID) async -> FoodSharePayload? {
        if let payload = productSharePayloads[id] {
            return payload
        }
        if let task = productShareTasks[id] {
            return await task.value
        }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ShareUserProductRequest()
                request.productID = id.uuidString
                return try await withFoodClient { client in
                    try await client.shareUserProduct(request, metadata: metadata)
                }
            }

            let payload = FoodSharePayload(
                title: productSummary(id: id)?.name ?? NSLocalizedString("product.fallback_title", value: "Product", comment: "Fallback product title"),
                shareCode: response.shareCode,
                shareURL: response.shareURL
            )
            productSharePayloads[id] = payload
            return payload
        } catch {
            return nil
        }
    }

    private func silentlyShareRecipe(id: UUID) async -> FoodSharePayload? {
        if let payload = recipeSharePayloads[id] {
            return payload
        }
        if let task = recipeShareTasks[id] {
            return await task.value
        }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ShareRecipeRequest()
                request.recipeID = id.uuidString
                return try await withFoodClient { client in
                    try await client.shareRecipe(request, metadata: metadata)
                }
            }

            let payload = FoodSharePayload(
                title: recipeSummary(id: id)?.title ?? NSLocalizedString("recipe.fallback_title", comment: "Fallback recipe title"),
                shareCode: response.shareCode,
                shareURL: response.shareURL
            )
            recipeSharePayloads[id] = payload
            return payload
        } catch {
            return nil
        }
    }

    private func silentlyShareMealTemplate(id: UUID) async -> FoodSharePayload? {
        if let payload = mealTemplateSharePayloads[id] {
            return payload
        }
        if let task = mealTemplateShareTasks[id] {
            return await task.value
        }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ShareMealTemplateRequest()
                request.mealTemplateID = id.uuidString
                return try await withFoodClient { client in
                    try await client.shareMealTemplate(request, metadata: metadata)
                }
            }

            let payload = FoodSharePayload(
                title: mealTemplateSummary(id: id)?.title ?? "Ration",
                shareCode: response.shareCode,
                shareURL: response.shareURL
            )
            mealTemplateSharePayloads[id] = payload
            return payload
        } catch {
            return nil
        }
    }

    private func recipeMessagesSubtitle(for recipe: RecipeSummary) -> String {
        let kcal = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        return "\(recipe.caloriesPerServing) \(kcal) • \(max(recipe.servings, 1)) servings"
    }

    private func productMessagesSubtitle(for product: ProductSummary) -> String {
        let kcal = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        let trimmedBrand = product.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let per100Text = "\(product.caloriesPer100g) \(kcal) / 100 \(product.per100UnitShortTitle)"
        if trimmedBrand.isEmpty {
            return per100Text
        }
        return "\(trimmedBrand) • \(per100Text)"
    }

    private func mealMessagesSubtitle(for meal: MealTemplateSummary) -> String {
        let kcal = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        return "\(meal.calories) \(kcal) • \(max(meal.items.count, 1)) items"
    }

    private func normalizedRecipeEmoji(_ rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func normalizeCacheScope(_ rawValue: String?) -> String {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "anon" : trimmed.lowercased()
    }

    func withFoodClient<T>(
        _ body: (Food_FoodService.Client<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T where T: Sendable {
        try await GRPCCore.withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: serverHost, port: serverPort),
                transportSecurity: useTLS ? .tls : .plaintext
            )
        ) { client in
            let foodClient = Food_FoodService.Client(wrapping: client)
            return try await body(foodClient)
        }
    }

    func withAuthenticatedMetadata<T: Sendable>(_ operation: (Metadata) async throws -> T) async throws -> T {
        guard let authService else {
            throw NSError(domain: "FoodCatalogService", code: 401, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("food.service.auth_failed", comment: "Food service authorization failed")])
        }

        do {
            return try await authService.withAuthorizedMetadata(operation)
        } catch {
            if authService.shouldRetryAuthorizedRequest(after: error) {
                storeLastError(NSError(domain: "FoodCatalogService", code: 401, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("food.service.auth_refresh_failed", comment: "Food service token refresh failed")]))
            }
            throw error
        }
    }

    private func makeProduct(from draft: ProductDraft) -> Food_Product {
        var product = Food_Product()
        if let productID = draft.productID {
            product.id = productID.uuidString
        }
        product.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        product.brand = draft.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        product.barcode = draft.barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        product.description_p = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        product.visibility = draft.visibility.grpcValue

        var nutrition = Food_NutritionFacts()
        nutrition.calories = draft.caloriesPer100g
        nutrition.protein = draft.proteinPer100g
        nutrition.fat = draft.fatPer100g
        nutrition.saturatedFat = draft.saturatedFatPer100g
        nutrition.unsaturatedFat = draft.unsaturatedFatPer100g
        nutrition.carbs = draft.carbsPer100g
        nutrition.fiber = draft.fiberPer100g
        nutrition.sugar = draft.sugarPer100g
        nutrition.sodiumMg = draft.sodiumMgPer100g
        nutrition.servingAmount = draft.servingAmount
        nutrition.servingUnit = grpcUnit(from: draft.servingUnit)
        nutrition.additionalNutrients = draft.additionalNutrients.map(makeNutrientValue)
        product.per100G = nutrition
        product.servingOptions = normalizedServingOptions(for: draft).map(makeServingOptionPayload)
        return product
    }

    private func makeRecipe(from draft: RecipeDraft) -> Food_Recipe {
        let nutrition = computedNutrition(for: draft)
        var recipe = Food_Recipe()
        if let recipeID = draft.recipeID {
            recipe.id = recipeID.uuidString
        }
        recipe.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.description_p = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.emoji = draft.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.servings = Int32(max(draft.servings, 1))
        recipe.visibility = draft.visibility.grpcValue
        recipe.outputWeightGrams = max(draft.outputWeightGrams, 0)
        recipe.steps = draft.steps
        recipe.ingredients = draft.ingredients.compactMap(makeRecipeIngredient)
        recipe.nutritionPerServing = nutritionFacts(from: nutrition.perServing)
        recipe.nutritionPer100G = nutritionFacts(from: nutrition.per100g)
        return recipe
    }

    private func makeMealTemplate(from draft: MealTemplateDraft) -> Food_MealTemplate {
        var mealTemplate = Food_MealTemplate()
        if let mealTemplateID = draft.mealTemplateID {
            mealTemplate.id = mealTemplateID.uuidString
        }
        mealTemplate.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        mealTemplate.description_p = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        mealTemplate.visibility = draft.visibility.grpcValue
        mealTemplate.items = draft.items.compactMap(makeMealTemplateItem)
        let totalNutrition = NutritionSummary(
            calories: draft.items.reduce(0) { $0 + $1.calories },
            protein: draft.items.reduce(0) { $0 + $1.protein },
            fat: draft.items.reduce(0) { $0 + $1.fat },
            carbs: draft.items.reduce(0) { $0 + $1.carbs }
        )
        mealTemplate.totals = nutritionFacts(from: totalNutrition)
        return mealTemplate
    }

    private func makeRecipeIngredient(from ingredient: RecipeIngredientDraft) -> Food_RecipeIngredient? {
        guard ingredient.productID != nil || ingredient.nestedRecipeID != nil else { return nil }

        var payload = Food_RecipeIngredient()
        payload.id = ingredient.id.uuidString
        payload.amount = ingredient.amount
        payload.unit = grpcUnit(from: ingredient.unit)
        payload.note = ingredient.note.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.servingLabel = ingredient.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        if let productID = ingredient.productID {
            payload.productID = productID.uuidString
        } else if let nestedRecipeID = ingredient.nestedRecipeID {
            payload.nestedRecipeID = nestedRecipeID.uuidString
        }

        return payload
    }

    private func makeMealTemplateItem(from item: MealItemEntry) -> Food_MealItem? {
        guard item.productID != nil || item.recipeID != nil else { return nil }

        var payload = Food_MealItem()
        payload.id = item.id.uuidString
        payload.amount = item.amount
        payload.unit = grpcUnit(from: item.unit)
        payload.note = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.servingLabel = item.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        if let productID = item.productID {
            payload.productID = productID.uuidString
        } else if let recipeID = item.recipeID {
            payload.recipeID = recipeID.uuidString
        }

        return payload
    }

    private func nutrition(for ingredient: RecipeIngredientDraft) -> NutritionSummary {
        if let product = productSummary(for: ingredient) {
            let base = NutritionSummary(
                calories: product.caloriesPer100g,
                protein: product.proteinPer100g,
                fat: product.fatPer100g,
                carbs: product.carbsPer100g
            )
            let resolvedAmount = product.actualAmount(
                for: ingredient.amount,
                unit: ingredient.unit,
                servingLabel: ingredient.servingLabel
            )
            return scaledNutrition(base, amount: resolvedAmount.amount, unit: resolvedAmount.unit)
        }

        if let recipe = recipeSummary(for: ingredient) {
            if ingredient.unit == .serving {
                return NutritionSummary(
                    calories: Int((Double(recipe.caloriesPerServing) * ingredient.amount).rounded()),
                    protein: Int((Double(recipe.proteinPerServing) * ingredient.amount).rounded()),
                    fat: Int((Double(recipe.fatPerServing) * ingredient.amount).rounded()),
                    carbs: Int((Double(recipe.carbsPerServing) * ingredient.amount).rounded())
                )
            }

            return scaledNutrition(nutritionPreview(for: recipe).per100g, amount: ingredient.amount, unit: ingredient.unit)
        }

        return .zero
    }

    private func estimatedOutputWeight(for draft: RecipeDraft) -> Double {
        draft.ingredients.reduce(0) { partial, ingredient in
            partial + estimatedWeight(for: ingredient)
        }
    }

    private func estimatedOutputWeight(for recipe: RecipeSummary) -> Double {
        recipe.ingredients.reduce(0) { partial, ingredient in
            partial + estimatedWeight(for: ingredient)
        }
    }

    private func estimatedWeight(for ingredient: RecipeIngredientDraft) -> Double {
        if let product = productSummary(for: ingredient) {
            let resolvedAmount = product.actualAmount(
                for: ingredient.amount,
                unit: ingredient.unit,
                servingLabel: ingredient.servingLabel
            )
            return max(resolvedAmount.amount, 0)
        }

        if let recipe = recipeSummary(for: ingredient) {
            switch ingredient.unit {
            case .grams, .milliliters:
                return max(ingredient.amount, 0)
            case .serving:
                let servingWeight = portionWeight(for: recipe)
                return max(ingredient.amount, 0) * max(servingWeight, 1)
            }
        }

        return 0
    }

    private func estimatedWeight(for ingredient: RecipeIngredientSummary) -> Double {
        if let product = productSummary(for: ingredient) {
            let resolvedAmount = product.actualAmount(
                for: ingredient.amount,
                unit: ingredient.unit,
                servingLabel: ingredient.servingLabel
            )
            return max(resolvedAmount.amount, 0)
        }

        if let recipe = recipeSummary(for: ingredient) {
            switch ingredient.unit {
            case .grams, .milliliters:
                return max(ingredient.amount, 0)
            case .serving:
                let servingWeight = portionWeight(for: recipe)
                return max(ingredient.amount, 0) * max(servingWeight, 1)
            }
        }

        return 0
    }

    private func scaledNutrition(_ nutrition: NutritionSummary, amount: Double, unit: MealItemUnit) -> NutritionSummary {
        switch unit {
        case .grams, .milliliters:
            return nutrition.scaled(by: amount / 100.0)
        case .serving:
            return nutrition.scaled(by: max(amount, 1))
        }
    }

    private func nutritionFacts(from summary: NutritionSummary) -> Food_NutritionFacts {
        var facts = Food_NutritionFacts()
        facts.calories = Double(summary.calories)
        facts.protein = Double(summary.protein)
        facts.fat = Double(summary.fat)
        facts.carbs = Double(summary.carbs)
        return facts
    }

    private func grpcUnit(from unit: MealItemUnit) -> Food_NutritionUnit {
        switch unit {
        case .grams:
            return .grams
        case .milliliters:
            return .milliliters
        case .serving:
            return .serving
        }
    }

    private func mealUnit(from unit: Food_NutritionUnit) -> MealItemUnit {
        switch unit {
        case .grams:
            return .grams
        case .milliliters:
            return .milliliters
        case .serving:
            return .serving
        case .unspecified, .UNRECOGNIZED:
            return .grams
        }
    }

    private static func date(from timestamp: Google_Protobuf_Timestamp) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp.seconds) + TimeInterval(timestamp.nanos) / 1_000_000_000)
    }

    private func normalizedShareCode(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let exactMatch = exactShareCode(from: trimmed) {
            return exactMatch
        }

        guard let components = URLComponents(string: trimmed) else {
            return nil
        }

        let queryCandidates = ["shareCode", "share_code", "code", "token"]
        for key in queryCandidates {
            if let value = components.queryItems?.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value,
               let match = exactShareCode(from: value) {
                return match
            }
        }

        let pathCandidates = ([components.host] + components.path
            .split(separator: "/")
            .map(String.init)
        )
            .compactMap { $0 }
            .reversed()

        if let pathMatch = pathCandidates.compactMap(exactShareCode(from:)).first {
            return pathMatch
        }

        return nil
    }

    private func exactShareCode(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let invalidCharacters = CharacterSet(charactersIn: ":/?&#")
        guard trimmed.rangeOfCharacter(from: invalidCharacters) == nil else {
            return nil
        }

        // The prefixes the service issues, and only those. `mtshare` used to be
        // listed for meal templates and is not a thing the service has ever
        // produced, so a template code was rejected here before anything
        // downstream could recognise it.
        let normalized = trimmed.lowercased()
        let known = ["rshare", "mshare", "tshare", "pshare"]
        guard known.contains(where: normalized.hasPrefix) else {
            return nil
        }

        return trimmed
    }

    private static func makeProductSummary(_ product: Food_Product) -> ProductSummary? {
        guard let id = UUID(uuidString: product.id) else { return nil }
        return ProductSummary(
            id: id,
            name: product.name,
            brand: product.brand,
            barcode: product.barcode,
            caloriesPer100g: Int(product.per100G.calories.rounded()),
            proteinPer100g: Int(product.per100G.protein.rounded()),
            fatPer100g: Int(product.per100G.fat.rounded()),
            carbsPer100g: Int(product.per100G.carbs.rounded()),
            createdAt: product.hasCreatedAt ? Self.date(from: product.createdAt) : nil,
            updatedAt: product.hasUpdatedAt ? Self.date(from: product.updatedAt) : nil,
            details: product.description_p,
            visibility: FoodVisibilityOption(grpcValue: product.visibility),
            servingAmount: product.per100G.servingAmount,
            servingUnit: mealUnitStatic(from: product.per100G.servingUnit),
            fiberPer100g: product.per100G.fiber,
            sugarPer100g: product.per100G.sugar,
            sodiumMgPer100g: product.per100G.sodiumMg,
            saturatedFatPer100g: product.per100G.saturatedFat,
            unsaturatedFatPer100g: product.per100G.unsaturatedFat,
            additionalNutrients: product.per100G.additionalNutrients.map(makeProductNutrient),
            servingOptions: product.servingOptions.map(makeServingOption)
        )
    }

    static func linkedSummaries(from snapshot: Food_CatalogItemSnapshot) -> (product: ProductSummary?, recipe: RecipeSummary?) {
        switch snapshot.item {
        case .product(let product):
            return (product: makeProductSummary(product), recipe: nil)
        case .recipe(let recipe):
            return (product: nil, recipe: makeRecipeSummary(recipe))
        case nil:
            return (product: nil, recipe: nil)
        }
    }

    private static func makeProductSummary(_ product: Food_LinkedProductSnapshot) -> ProductSummary? {
        guard let id = UUID(uuidString: product.id) else { return nil }
        return ProductSummary(
            id: id,
            name: product.name,
            brand: product.brand,
            caloriesPer100g: Int(product.per100G.calories.rounded()),
            proteinPer100g: Int(product.per100G.protein.rounded()),
            fatPer100g: Int(product.per100G.fat.rounded()),
            carbsPer100g: Int(product.per100G.carbs.rounded()),
            createdAt: product.hasCreatedAt ? Self.date(from: product.createdAt) : nil,
            updatedAt: product.hasUpdatedAt ? Self.date(from: product.updatedAt) : nil,
            details: product.description_p,
            visibility: FoodVisibilityOption(grpcValue: product.visibility),
            servingAmount: product.per100G.servingAmount,
            servingUnit: mealUnitStatic(from: product.per100G.servingUnit),
            fiberPer100g: product.per100G.fiber,
            sugarPer100g: product.per100G.sugar,
            sodiumMgPer100g: product.per100G.sodiumMg,
            saturatedFatPer100g: product.per100G.saturatedFat,
            unsaturatedFatPer100g: product.per100G.unsaturatedFat,
            additionalNutrients: product.per100G.additionalNutrients.map(makeProductNutrient),
            servingOptions: product.servingOptions.map(makeServingOption)
        )
    }

    private static func makeRecipeSummary(_ recipe: Food_Recipe) -> RecipeSummary? {
        guard let id = UUID(uuidString: recipe.id) else { return nil }
        return RecipeSummary(
            id: id,
            title: recipe.title,
            servings: Int(recipe.servings),
            caloriesPerServing: Int(recipe.nutritionPerServing.calories.rounded()),
            proteinPerServing: Int(recipe.nutritionPerServing.protein.rounded()),
            fatPerServing: Int(recipe.nutritionPerServing.fat.rounded()),
            carbsPerServing: Int(recipe.nutritionPerServing.carbs.rounded()),
            cookTimeMinutes: 0,
            category: recipe.category,
            emoji: recipe.emoji,
            createdAt: recipe.hasCreatedAt ? Self.date(from: recipe.createdAt) : nil,
            updatedAt: recipe.hasUpdatedAt ? Self.date(from: recipe.updatedAt) : nil,
            details: recipe.description_p,
            ingredients: recipe.ingredients.map(makeRecipeIngredientSummary),
            steps: recipe.steps,
            visibility: FoodVisibilityOption(grpcValue: recipe.visibility),
            outputWeightGrams: recipe.outputWeightGrams,
            nutritionPer100g: NutritionSummary(
                calories: Int(recipe.nutritionPer100G.calories.rounded()),
                protein: Int(recipe.nutritionPer100G.protein.rounded()),
                fat: Int(recipe.nutritionPer100G.fat.rounded()),
                carbs: Int(recipe.nutritionPer100G.carbs.rounded())
            )
        )
    }

    private static func makeRecipeSummary(_ recipe: Food_LinkedRecipeSnapshot) -> RecipeSummary? {
        guard let id = UUID(uuidString: recipe.id) else { return nil }
        return RecipeSummary(
            id: id,
            title: recipe.title,
            servings: Int(recipe.servings),
            caloriesPerServing: Int(recipe.nutritionPerServing.calories.rounded()),
            proteinPerServing: Int(recipe.nutritionPerServing.protein.rounded()),
            fatPerServing: Int(recipe.nutritionPerServing.fat.rounded()),
            carbsPerServing: Int(recipe.nutritionPerServing.carbs.rounded()),
            cookTimeMinutes: 0,
            category: recipe.category,
            createdAt: recipe.hasCreatedAt ? Self.date(from: recipe.createdAt) : nil,
            updatedAt: recipe.hasUpdatedAt ? Self.date(from: recipe.updatedAt) : nil,
            details: recipe.description_p,
            ingredients: [],
            steps: [],
            visibility: FoodVisibilityOption(grpcValue: recipe.visibility),
            outputWeightGrams: recipe.outputWeightGrams,
            nutritionPer100g: NutritionSummary(
                calories: Int(recipe.nutritionPer100G.calories.rounded()),
                protein: Int(recipe.nutritionPer100G.protein.rounded()),
                fat: Int(recipe.nutritionPer100G.fat.rounded()),
                carbs: Int(recipe.nutritionPer100G.carbs.rounded())
            )
        )
    }

    private static func makeMealTemplateSummary(_ mealTemplate: Food_MealTemplate) -> MealTemplateSummary? {
        guard let id = UUID(uuidString: mealTemplate.id) else { return nil }
        return MealTemplateSummary(
            id: id,
            title: mealTemplate.title,
            details: mealTemplate.description_p,
            items: mealTemplate.items.map(makeMealTemplateItemEntry),
            nutrition: NutritionSummary(
                calories: Int(mealTemplate.totals.calories.rounded()),
                protein: Int(mealTemplate.totals.protein.rounded()),
                fat: Int(mealTemplate.totals.fat.rounded()),
                carbs: Int(mealTemplate.totals.carbs.rounded())
            ),
            createdAt: mealTemplate.hasCreatedAt ? Self.date(from: mealTemplate.createdAt) : nil,
            updatedAt: mealTemplate.hasUpdatedAt ? Self.date(from: mealTemplate.updatedAt) : nil,
            visibility: FoodVisibilityOption(grpcValue: mealTemplate.visibility)
        )
    }

    private static func makeRecipeIngredientSummary(_ ingredient: Food_RecipeIngredient) -> RecipeIngredientSummary {
        let snapshot = ingredient.hasSnapshot ? linkedSummaries(from: ingredient.snapshot) : (product: nil, recipe: nil)
        return RecipeIngredientSummary(
            id: UUID(uuidString: ingredient.id) ?? UUID(),
            productID: UUID(uuidString: ingredient.productID),
            nestedRecipeID: UUID(uuidString: ingredient.nestedRecipeID),
            amount: ingredient.amount,
            unit: mealUnitStatic(from: ingredient.unit),
            note: ingredient.note,
            servingLabel: ingredient.servingLabel,
            productSnapshot: snapshot.product,
            nestedRecipeSnapshot: snapshot.recipe
        )
    }

    private static func makeMealTemplateItemEntry(_ item: Food_MealItem) -> MealItemEntry {
        let unit = mealUnitStatic(from: item.unit)
        let productID = UUID(uuidString: item.productID)
        let recipeID = UUID(uuidString: item.recipeID)
        let snapshot = item.hasSnapshot ? linkedSummaries(from: item.snapshot) : (product: nil, recipe: nil)
        let recipeNutrition = snapshot.recipe.map { recipe -> NutritionSummary in
            switch unit {
            case .serving:
                return recipe.nutritionPerServing
            case .grams, .milliliters:
                return recipe.resolvedNutritionPer100g
            }
        }
        let fallbackName = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = snapshot.product?.name ?? snapshot.recipe?.title ?? fallbackName
        return MealItemEntry(
            id: UUID(uuidString: item.id) ?? UUID(),
            name: resolvedName.isEmpty ? (recipeID == nil ? NSLocalizedString("addmeal.item.product_fallback", comment: "Fallback product title") : NSLocalizedString("recipe.fallback_title", comment: "Fallback recipe title")) : resolvedName,
            amount: item.amount,
            unit: unit,
            note: "",
            servingLabel: item.servingLabel,
            caloriesPer100g: snapshot.product?.caloriesPer100g ?? recipeNutrition?.calories ?? 0,
            proteinPer100g: snapshot.product?.proteinPer100g ?? recipeNutrition?.protein ?? 0,
            fatPer100g: snapshot.product?.fatPer100g ?? recipeNutrition?.fat ?? 0,
            carbsPer100g: snapshot.product?.carbsPer100g ?? recipeNutrition?.carbs ?? 0,
            productID: productID,
            recipeID: recipeID,
            productSnapshot: snapshot.product,
            recipeSnapshot: snapshot.recipe
        )
    }

    private func makeNutrientValue(from nutrient: ProductNutrient) -> Food_NutrientValue {
        var payload = Food_NutrientValue()
        payload.code = nutrient.code.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.label = nutrient.label.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.amount = nutrient.amount
        payload.unit = nutrient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return payload
    }

    private func makeServingOptionPayload(from option: ProductServingOption) -> Food_ProductServingOption {
        var payload = Food_ProductServingOption()
        payload.id = option.id
        payload.label = option.label.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.amount = option.amount
        payload.unit = grpcUnit(from: option.unit)
        payload.metricAmount = option.metricAmount
        payload.metricUnit = grpcUnit(from: option.metricUnit)
        payload.sortOrder = Int32(option.sortOrder)
        return payload
    }

    private func normalizedServingOptions(for draft: ProductDraft) -> [ProductServingOption] {
        let baseUnit: MealItemUnit = draft.servingUnit == .milliliters ? .milliliters : .grams
        let normalizedAmount = max(draft.servingAmount, 1)

        var options = draft.servingOptions.filter {
            !($0.unit == baseUnit
                && abs($0.amount - 100) < 0.0001
                && $0.metricUnit == baseUnit
                && abs($0.metricAmount - 100) < 0.0001)
        }

        if abs(normalizedAmount - 100) > 0.0001 && !options.contains(where: { $0.unit == .serving }) {
            // Preserve legacy behavior only when there are no explicit serving portions.
            options.insert(
                ProductServingOption(
                    id: "",
                    label: "",
                    amount: 1,
                    unit: .serving,
                    metricAmount: normalizedAmount,
                    metricUnit: baseUnit,
                    sortOrder: 0
                ),
                at: 0
            )
        }

        options = deduplicatedServingOptions(options, baseUnit: baseUnit, baselineAmount: normalizedAmount)

        return options.enumerated().map { index, option in
            var adjustedOption = option
            if adjustedOption.id.isEmpty {
                adjustedOption.id = "draft-serving-option-\(index)"
            }
            if adjustedOption.sortOrder < 0 {
                adjustedOption.sortOrder = index
            }
            return adjustedOption
        }
    }

    private func deduplicatedServingOptions(
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

    private static func makeProductNutrient(_ nutrient: Food_NutrientValue) -> ProductNutrient {
        ProductNutrient(
            code: nutrient.code,
            label: nutrient.label,
            amount: nutrient.amount,
            unit: nutrient.unit
        )
    }

    private static func makeServingOption(_ option: Food_ProductServingOption) -> ProductServingOption {
        ProductServingOption(
            id: option.id,
            label: option.label,
            amount: option.amount,
            unit: mealUnitStatic(from: option.unit),
            metricAmount: option.metricAmount,
            metricUnit: mealUnitStatic(from: option.metricUnit),
            sortOrder: Int(option.sortOrder)
        )
    }

    private static func mealUnitStatic(from unit: Food_NutritionUnit) -> MealItemUnit {
        switch unit {
        case .grams:
            return .grams
        case .milliliters:
            return .milliliters
        case .serving:
            return .serving
        case .unspecified, .UNRECOGNIZED:
            return .grams
        }
    }

    private static let sampleRecipes: [RecipeSummary] = [
        RecipeSummary(id: UUID(), title: "Сырники с йогуртом", servings: 2, caloriesPerServing: 330, proteinPerServing: 18, fatPerServing: 12, carbsPerServing: 26, cookTimeMinutes: 20),
        RecipeSummary(id: UUID(), title: "Паста с индейкой", servings: 3, caloriesPerServing: 480, proteinPerServing: 30, fatPerServing: 14, carbsPerServing: 52, cookTimeMinutes: 35),
        RecipeSummary(id: UUID(), title: "Боул с лососем", servings: 2, caloriesPerServing: 520, proteinPerServing: 28, fatPerServing: 21, carbsPerServing: 43, cookTimeMinutes: 25),
        RecipeSummary(id: UUID(), title: "Шакшука", servings: 2, caloriesPerServing: 360, proteinPerServing: 20, fatPerServing: 17, carbsPerServing: 18, cookTimeMinutes: 18)
    ]

    private static let sampleProducts: [ProductSummary] = [
        ProductSummary(id: UUID(), name: "Греческий йогурт", brand: "Eatometer Local", caloriesPer100g: 68, proteinPer100g: 5, fatPer100g: 3, carbsPer100g: 4),
        ProductSummary(id: UUID(), name: "Овсяные хлопья", brand: "Nordic", caloriesPer100g: 352, proteinPer100g: 12, fatPer100g: 6, carbsPer100g: 61),
        ProductSummary(id: UUID(), name: "Филе индейки", brand: "Farm", caloriesPer100g: 144, proteinPer100g: 29, fatPer100g: 2, carbsPer100g: 0),
        ProductSummary(id: UUID(), name: "Творог 5%", brand: "Village", caloriesPer100g: 121, proteinPer100g: 17, fatPer100g: 5, carbsPer100g: 3)
    ]

    private static let sampleMealTemplates: [MealTemplateSummary] = [
        MealTemplateSummary(
            id: UUID(),
            title: "Быстрый завтрак",
            details: "Йогурт, хлопья и сырники на одно сохранение.",
            items: [
                MealItemEntry(id: UUID(), name: "Греческий йогурт", amount: 180, unit: .grams, note: "Греческий йогурт", caloriesPer100g: 68, proteinPer100g: 5, fatPer100g: 3, carbsPer100g: 4, productID: nil, recipeID: nil),
                MealItemEntry(id: UUID(), name: "Овсяные хлопья", amount: 60, unit: .grams, note: "Овсяные хлопья", caloriesPer100g: 352, proteinPer100g: 12, fatPer100g: 6, carbsPer100g: 61, productID: nil, recipeID: nil)
            ],
            nutrition: NutritionSummary(calories: 334, protein: 16, fat: 9, carbs: 44)
        ),
        MealTemplateSummary(
            id: UUID(),
            title: "Обед с пастой",
            details: "Комбо из готового блюда и дополнительного белка.",
            items: [
                MealItemEntry(id: UUID(), name: "Паста с индейкой", amount: 1, unit: .serving, note: "Паста с индейкой", caloriesPer100g: 480, proteinPer100g: 30, fatPer100g: 14, carbsPer100g: 52, productID: nil, recipeID: nil),
                MealItemEntry(id: UUID(), name: "Филе индейки", amount: 120, unit: .grams, note: "Филе индейки", caloriesPer100g: 144, proteinPer100g: 29, fatPer100g: 2, carbsPer100g: 0, productID: nil, recipeID: nil)
            ],
            nutrition: NutritionSummary(calories: 653, protein: 65, fat: 16, carbs: 52)
        )
    ]
}
