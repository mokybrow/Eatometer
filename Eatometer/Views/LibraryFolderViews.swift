import SwiftUI

// MARK: - Sort menu

private struct LibrarySortMenu: View {
    @Binding var sort: AppSettings.ListSort

    var body: some View {
        Menu {
            Picker("settings.listsort.title", selection: $sort) {
                ForEach(AppSettings.ListSort.allCases, id: \.self) { sort in
                    Text(sort.displayName).tag(sort)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(.primary)
    }
}

private extension View {
    func libraryFolderChrome(
        title: LocalizedStringKey,
        onAdd: (() -> Void)? = nil,
        addMenu: AnyView? = nil,
        sort: Binding<AppSettings.ListSort>? = nil
    ) -> some View {
        self
            .background(Color.appPageBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let addMenu {
                    ToolbarItem(placement: .platformTopBarTrailing) {
                        addMenu
                    }
                } else if let onAdd {
                    ToolbarItem(placement: .platformTopBarTrailing) {
                        Button(action: onAdd) {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                        }
                        .tint(.primary)
                        .accessibilityLabel(Text("common.add"))
                    }
                }
                if let sort {
                    ToolbarItem(placement: .platformTopBarTrailing) {
                        LibrarySortMenu(sort: sort)
                    }
                }
            }
    }
}

private func compareLibraryAddedDate(_ lhs: Date?, _ rhs: Date?, newestFirst: Bool, lhsTitle: String, rhsTitle: String) -> Bool {
    let lhsDate = lhs ?? .distantPast
    let rhsDate = rhs ?? .distantPast
    if lhsDate != rhsDate {
        return newestFirst ? lhsDate > rhsDate : lhsDate < rhsDate
    }
    return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
}

private func sortLibraryProducts(_ products: [ProductSummary], by sort: AppSettings.ListSort) -> [ProductSummary] {
    products.sorted { lhs, rhs in
        switch sort {
        case .titleAsc:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .titleDesc:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
        case .addedNewest:
            return compareLibraryAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: true, lhsTitle: lhs.name, rhsTitle: rhs.name)
        case .addedOldest:
            return compareLibraryAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: false, lhsTitle: lhs.name, rhsTitle: rhs.name)
        }
    }
}

private func sortLibraryRecipes(_ recipes: [RecipeSummary], by sort: AppSettings.ListSort) -> [RecipeSummary] {
    recipes.sorted { lhs, rhs in
        switch sort {
        case .titleAsc:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .titleDesc:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedDescending
        case .addedNewest:
            return compareLibraryAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: true, lhsTitle: lhs.title, rhsTitle: rhs.title)
        case .addedOldest:
            return compareLibraryAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: false, lhsTitle: lhs.title, rhsTitle: rhs.title)
        }
    }
}

private func sortLibraryMeals(_ meals: [MealTemplateSummary], by sort: AppSettings.ListSort) -> [MealTemplateSummary] {
    meals.sorted { lhs, rhs in
        switch sort {
        case .titleAsc:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .titleDesc:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedDescending
        case .addedNewest:
            return compareLibraryAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: true, lhsTitle: lhs.title, rhsTitle: rhs.title)
        case .addedOldest:
            return compareLibraryAddedDate(lhs.createdAt ?? lhs.updatedAt, rhs.createdAt ?? rhs.updatedAt, newestFirst: false, lhsTitle: lhs.title, rhsTitle: rhs.title)
        }
    }
}

private struct LibraryRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var emoji: String? = nil
    var showsIcon: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if showsIcon {
                if let trimmed = emoji?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                    Text(trimmed)
                        .font(.system(size: 26))
                        .frame(width: 32, height: 32, alignment: .center)
                } else {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
    }
}

private struct LibraryEmptyState: View {
    let kind: FoodPlaceholderKind
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            FoodPlaceholderArtwork(kind: kind, width: 128, height: 128)
            VStack(spacing: 6) {
                Text(titleKey)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(subtitleKey)
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .containerRelativeFrame(.vertical, alignment: .center)
    }
}

private struct LibraryCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    private var rowCardBackground: Color {
        colorScheme == .dark ? Color.platformSecondarySystemBackground : .white
    }

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(rowCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
    }
}

// MARK: - Subtitle helpers

private func productSubtitle(_ product: ProductSummary) -> String {
    let kcal = NSLocalizedString("diary.kcal", comment: "Calories suffix")
    let protein = NSLocalizedString("recipe.detail.protein_short", comment: "Protein short title")
    let fat = NSLocalizedString("recipe.detail.fat_short", comment: "Fat short title")
    let carbs = NSLocalizedString("recipe.detail.carbs_short", comment: "Carbs short title")
    let nutrition = "\(product.caloriesPer100g) \(kcal) · \(protein) \(product.proteinPer100g) · \(fat) \(product.fatPer100g) · \(carbs) \(product.carbsPer100g)"
    let brand = product.brand.trimmingCharacters(in: .whitespacesAndNewlines)
    return brand.isEmpty ? nutrition : "\(brand) · \(nutrition)"
}

private func productIcon(_ product: ProductSummary) -> (String, Color) {
    ("shippingbox.fill", .primary)
}

private func recipeSubtitle(_ recipe: RecipeSummary) -> String {
    let kcal = NSLocalizedString("diary.kcal", comment: "Calories suffix")
    let perServing = NSLocalizedString("recipe.editor.per_serving", comment: "Per serving")
    return "\(recipe.caloriesPerServing) \(kcal) · \(perServing)"
}

private func mealSubtitle(_ meal: MealTemplateSummary) -> String {
    let kcal = NSLocalizedString("diary.kcal", comment: "Calories suffix")
    return "\(meal.calories) \(kcal) · \(meal.items.count)"
}

// MARK: - Folder views

struct LibraryProductsFolderView: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @State private var selectedProduct: ProductSummary?
    @State private var productEditorState: ProductEditorState?
    @AppStorage("Eatometer.library.sort.products") private var sortRawValue = AppSettings.ListSort.addedNewest.rawValue

    private var sort: AppSettings.ListSort {
        get { AppSettings.ListSort(rawValue: sortRawValue) ?? .addedNewest }
        nonmutating set { sortRawValue = newValue.rawValue }
    }

    private var sortBinding: Binding<AppSettings.ListSort> {
        Binding(get: { sort }, set: { sort = $0 })
    }

    private var items: [ProductSummary] { sortLibraryProducts(catalogService.products, by: sort) }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                LibraryEmptyState(
                    kind: .grocery,
                    titleKey: "products.empty.title",
                    subtitleKey: "products.empty.subtitle"
                )
            } else {
                LibraryCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, product in
                        let icon = productIcon(product)
                        Button { selectedProduct = product } label: {
                            LibraryRow(icon: icon.0, tint: icon.1, title: product.name, subtitle: productSubtitle(product), showsIcon: false)
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .libraryFolderChrome(
            title: "library.folder.products",
            addMenu: AnyView(productAddMenu),
            sort: sortBinding
        )
        .navigationDestination(item: $selectedProduct) { product in
            ProductDetailView(productID: product.id, initialProduct: product)
                .environmentObject(catalogService)
        }
        .sheet(item: $productEditorState) { state in
            ProductEditorSheet(state: state)
                .environmentObject(catalogService)
        }
    }

    private var productAddMenu: some View {
        Menu {
            Button {
                var draft = ProductDraft()
                draft.visibility = .privateVisibility
                productEditorState = ProductEditorState(
                    draft: draft,
                    visibilityOptions: [.privateVisibility, .friendsVisibility]
                )
            } label: {
                Label("product.add.personal", systemImage: "person.fill")
            }

            Button {
                var draft = ProductDraft()
                draft.visibility = .publicVisibility
                productEditorState = ProductEditorState(
                    draft: draft,
                    visibilityOptions: [.publicVisibility]
                )
            } label: {
                Label("product.add.community", systemImage: "person.3.fill")
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
        }
        .tint(.primary)
        .accessibilityLabel(Text("common.add"))
    }
}

struct LibraryRecipesFolderView: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @State private var selectedRecipe: RecipeSummary?
    @AppStorage("Eatometer.library.sort.recipes") private var sortRawValue = AppSettings.ListSort.addedNewest.rawValue

    private var sort: AppSettings.ListSort {
        get { AppSettings.ListSort(rawValue: sortRawValue) ?? .addedNewest }
        nonmutating set { sortRawValue = newValue.rawValue }
    }

    private var sortBinding: Binding<AppSettings.ListSort> {
        Binding(get: { sort }, set: { sort = $0 })
    }

    private var items: [RecipeSummary] { sortLibraryRecipes(catalogService.recipes, by: sort) }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                LibraryEmptyState(
                    kind: .recipe,
                    titleKey: "recipes.empty.title",
                    subtitleKey: "recipes.empty.subtitle"
                )
            } else {
                LibraryCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, recipe in
                        Button { selectedRecipe = recipe } label: {
                            LibraryRow(icon: "fork.knife", tint: .orange, title: recipe.title, subtitle: recipeSubtitle(recipe), showsIcon: false)
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .libraryFolderChrome(title: "library.folder.recipes", onAdd: {
            catalogService.presentRecipeEditor(draft: RecipeDraft())
        }, sort: sortBinding)
        .navigationDestination(item: $selectedRecipe) { recipe in
            RecipeDetailView(recipeID: recipe.id, initialRecipe: recipe)
                .environmentObject(catalogService)
        }
    }
}

struct LibraryMealsFolderView: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @State private var selectedMeal: MealTemplateSummary?
    @State private var isMealEditorPresented = false
    @AppStorage("Eatometer.library.sort.meals") private var sortRawValue = AppSettings.ListSort.addedNewest.rawValue

    private var sort: AppSettings.ListSort {
        get { AppSettings.ListSort(rawValue: sortRawValue) ?? .addedNewest }
        nonmutating set { sortRawValue = newValue.rawValue }
    }

    private var sortBinding: Binding<AppSettings.ListSort> {
        Binding(get: { sort }, set: { sort = $0 })
    }

    private var items: [MealTemplateSummary] { sortLibraryMeals(catalogService.mealTemplates, by: sort) }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                LibraryEmptyState(
                    kind: .meal,
                    titleKey: "recipes.saved_meals.empty.title",
                    subtitleKey: "recipes.saved_meals.empty.subtitle"
                )
            } else {
                LibraryCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, meal in
                        Button { selectedMeal = meal } label: {
                            LibraryRow(icon: "square.stack.3d.up.fill", tint: .mint, title: meal.title, subtitle: mealSubtitle(meal), showsIcon: false)
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .libraryFolderChrome(title: "library.folder.meals", onAdd: {
            isMealEditorPresented = true
        }, sort: sortBinding)
        .navigationDestination(item: $selectedMeal) { meal in
            MealTemplateDetailView(mealTemplateID: meal.id, initialMealTemplate: meal)
                .environmentObject(catalogService)
        }
        .sheet(isPresented: $isMealEditorPresented) {
            MealTemplateEditorSheet(draft: MealTemplateDraft())
                .environmentObject(catalogService)
        }
    }
}

struct LibraryFavoritesFolderView: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @State private var selectedProduct: ProductSummary?
    @State private var selectedRecipe: RecipeSummary?
    @State private var selectedMeal: MealTemplateSummary?
    @AppStorage("Eatometer.library.sort.favorites") private var sortRawValue = AppSettings.ListSort.addedNewest.rawValue

    private var sort: AppSettings.ListSort {
        get { AppSettings.ListSort(rawValue: sortRawValue) ?? .addedNewest }
        nonmutating set { sortRawValue = newValue.rawValue }
    }

    private var sortBinding: Binding<AppSettings.ListSort> {
        Binding(get: { sort }, set: { sort = $0 })
    }

    private var products: [ProductSummary] { sortLibraryProducts(catalogService.favoriteProductSummaries, by: sort) }
    private var recipes: [RecipeSummary] { sortLibraryRecipes(catalogService.favoriteRecipeSummaries, by: sort) }
    private var meals: [MealTemplateSummary] { sortLibraryMeals(catalogService.favoriteMealTemplateSummaries, by: sort) }

    private var isEmpty: Bool {
        products.isEmpty && recipes.isEmpty && meals.isEmpty
    }

    var body: some View {
        ScrollView {
            if isEmpty {
                LibraryEmptyState(kind: .favorite, titleKey: "favorites.empty.title", subtitleKey: "favorites.empty.subtitle")
            } else {
                VStack(spacing: 8) {
                    if !products.isEmpty {
                        section(titleKey: "favorites.scope.products") {
                            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                                let icon = productIcon(product)
                                Button { selectedProduct = product } label: {
                                    LibraryRow(icon: icon.0, tint: icon.1, title: product.name, subtitle: productSubtitle(product), showsIcon: false)
                                }
                                .buttonStyle(.plain)
                                if index < products.count - 1 { Divider().padding(.leading, 60) }
                            }
                        }
                    }
                    if !recipes.isEmpty {
                        section(titleKey: "favorites.scope.recipes") {
                            ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                                Button { selectedRecipe = recipe } label: {
                                    LibraryRow(icon: "fork.knife", tint: .orange, title: recipe.title, subtitle: recipeSubtitle(recipe), showsIcon: false)
                                }
                                .buttonStyle(.plain)
                                if index < recipes.count - 1 { Divider().padding(.leading, 60) }
                            }
                        }
                    }
                    if !meals.isEmpty {
                        section(titleKey: "favorites.scope.meals") {
                            ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                                Button { selectedMeal = meal } label: {
                                    LibraryRow(icon: "square.stack.3d.up.fill", tint: .mint, title: meal.title, subtitle: mealSubtitle(meal), showsIcon: false)
                                }
                                .buttonStyle(.plain)
                                if index < meals.count - 1 { Divider().padding(.leading, 60) }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .libraryFolderChrome(title: "library.folder.favorites", sort: sortBinding)
        .navigationDestination(item: $selectedProduct) { product in
            ProductDetailView(productID: product.id, initialProduct: product)
                .environmentObject(catalogService)
        }
        .navigationDestination(item: $selectedRecipe) { recipe in
            RecipeDetailView(recipeID: recipe.id, initialRecipe: recipe)
                .environmentObject(catalogService)
        }
        .navigationDestination(item: $selectedMeal) { meal in
            MealTemplateDetailView(mealTemplateID: meal.id, initialMealTemplate: meal)
                .environmentObject(catalogService)
        }
    }

    @ViewBuilder
    private func section<Content: View>(titleKey: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleKey)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 8)
            LibraryCard { content() }
        }
    }
}
