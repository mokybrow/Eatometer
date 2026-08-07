import SwiftUI

enum EatometerLibrarySection: String, CaseIterable, Identifiable {
    case products
    case meals
    case recipes

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .products: "library.folder.products"
        case .meals: "library.folder.meals"
        case .recipes: "library.folder.recipes"
        }
    }

    var systemImage: String {
        switch self {
        case .products: "carrot"
        case .meals: "fork.knife"
        case .recipes: "book.closed"
        }
    }
}

struct EatometerLibraryView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var catalogService: FoodCatalogService

    @Binding var selection: EatometerLibrarySection
    @State private var selectedProduct: ProductSummary?
    @State private var selectedMeal: MealTemplateSummary?
    @State private var selectedRecipe: RecipeSummary?
    @State private var productEditorState: ProductEditorState?
    @State private var mealEditorDraft: MealTemplateDraft?
    @State private var isNotificationsPresented = false

    var body: some View {
        VStack(spacing: 14) {
            EOSegmentedPicker(selection: $selection, segments: librarySegments)
                .eoCardInsets()

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .eoPageBackground()
        .navigationTitle("library.title")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItemGroup(placement: .platformTopBarTrailing) {
                Button {
                    isNotificationsPresented = true
                } label: {
                    Image(systemName: "bell")
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(Text("profile.notifications.inbox.title"))

                addMenu
            }
        }
        .navigationDestination(isPresented: $isNotificationsPresented) {
            NotificationInboxView()
        }
        // Viewers are sheets with their own header; the NavigationStack only
        // exists so their inner pushes (ingredient -> product) keep working.
        .sheet(item: $selectedProduct) { product in
            NavigationStack {
                ProductDetailView(
                    productID: product.id,
                    initialProduct: product,
                    showsDismissButton: true
                )
            }
            .environmentObject(catalogService)
        }
        .sheet(item: $selectedMeal) { meal in
            NavigationStack {
                MealTemplateDetailView(
                    mealTemplateID: meal.id,
                    initialMealTemplate: meal,
                    showsDismissButton: true
                )
            }
            .environmentObject(catalogService)
        }
        .sheet(item: $selectedRecipe) { recipe in
            NavigationStack {
                RecipeDetailView(
                    recipeID: recipe.id,
                    initialRecipe: recipe,
                    showsDismissButton: true
                )
            }
            .environmentObject(catalogService)
        }
        .sheet(item: $productEditorState) { state in
            ProductEditorSheet(state: state)
                .environmentObject(catalogService)
        }
        .sheet(item: $mealEditorDraft) { draft in
            MealTemplateEditorSheet(draft: draft)
                .environmentObject(catalogService)
        }
    }

    private var librarySegments: [EOSegmentedPicker<EatometerLibrarySection>.Segment] {
        EatometerLibrarySection.allCases.map { section in
            EOSegmentedPicker<EatometerLibrarySection>.Segment(section, title: Text(section.title))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .products:
            productsContent
        case .meals:
            mealsContent
        case .recipes:
            recipesContent
        }
    }

    private var productsContent: some View {
        itemList(
            isEmpty: catalogService.products.isEmpty,
            emptyTitle: "products.empty.title",
            emptySubtitle: "products.empty.subtitle"
        ) {
            ForEach(Array(catalogService.products.enumerated()), id: \.element.id) { index, product in
                Button {
                    selectedProduct = product
                } label: {
                    row(title: product.name, subtitle: product.brand)
                }
                .buttonStyle(.plain)
                .eoRowContextMenu {
                    Button {
                        productEditorState = ProductEditorState(draft: ProductDraft(summary: product))
                    } label: {
                        Label("common.edit", systemImage: "pencil")
                    }

                    EODestructiveMenuButton("common.delete", systemImage: "trash") {
                        Task { _ = await catalogService.deleteProduct(id: product.id) }
                    }
                }

                if index < catalogService.products.count - 1 {
                    EORowSeparator()
                }
            }
        }
    }

    private var mealsContent: some View {
        itemList(
            isEmpty: catalogService.mealTemplates.isEmpty,
            emptyTitle: "recipes.saved_meals.empty.title",
            emptySubtitle: "recipes.saved_meals.empty.subtitle"
        ) {
            ForEach(Array(catalogService.mealTemplates.enumerated()), id: \.element.id) { index, meal in
                Button {
                    selectedMeal = meal
                } label: {
                    row(
                        title: meal.title,
                        subtitle: "\(meal.calories) \(NSLocalizedString("diary.kcal", comment: "Calories"))"
                    )
                }
                .buttonStyle(.plain)
                .eoRowContextMenu {
                    Button {
                        mealEditorDraft = MealTemplateDraft(summary: meal)
                    } label: {
                        Label("common.edit", systemImage: "pencil")
                    }

                    EODestructiveMenuButton("common.delete", systemImage: "trash") {
                        Task { _ = await catalogService.deleteMealTemplate(id: meal.id) }
                    }
                }

                if index < catalogService.mealTemplates.count - 1 {
                    EORowSeparator()
                }
            }
        }
    }

    private var recipesContent: some View {
        itemList(
            isEmpty: catalogService.recipes.isEmpty,
            emptyTitle: "recipes.empty.title",
            emptySubtitle: "recipes.empty.subtitle"
        ) {
            ForEach(Array(catalogService.recipes.enumerated()), id: \.element.id) { index, recipe in
                Button {
                    selectedRecipe = recipe
                } label: {
                    row(
                        title: recipe.title,
                        subtitle: "\(recipe.caloriesPerServing) \(NSLocalizedString("diary.kcal", comment: "Calories"))"
                    )
                }
                .buttonStyle(.plain)
                .eoRowContextMenu {
                    Button {
                        catalogService.presentRecipeEditor(draft: RecipeDraft(summary: recipe))
                    } label: {
                        Label("common.edit", systemImage: "pencil")
                    }

                    EODestructiveMenuButton("common.delete", systemImage: "trash") {
                        Task { _ = await catalogService.deleteRecipe(id: recipe.id) }
                    }
                }

                if index < catalogService.recipes.count - 1 {
                    EORowSeparator()
                }
            }
        }
    }

    private func itemList<Rows: View>(
        isEmpty: Bool,
        emptyTitle: LocalizedStringKey,
        emptySubtitle: LocalizedStringKey,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        Group {
            if isEmpty {
                EOEmptyState(emptyTitle, subtitle: emptySubtitle)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: EOTheme.Metrics.headerSpacing) {
                        LazyVStack(spacing: 0) {
                            rows()
                        }
                        .background(EOTheme.Palette.card)
                        .clipShape(
                            RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                        )

                        Text("common.context_menu_hint")
                            .font(EOTheme.Typography.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, EOTheme.Metrics.cardInset)
                            .padding(.top, 4)
                    }
                    .eoCardInsets()
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(title: String, subtitle: String) -> some View {
        EOListRow(
            title: Text(verbatim: title),
            subtitle: subtitle.isEmpty ? nil : Text(verbatim: subtitle),
            accessory: .chevron
        )
    }

    private var addMenu: some View {
        Menu {
            Button {
                var draft = ProductDraft()
                draft.visibility = .privateVisibility
                productEditorState = ProductEditorState(
                    draft: draft,
                    visibilityOptions: [.privateVisibility, .friendsVisibility]
                )
            } label: {
                Label("products.add", systemImage: "carrot")
            }

            Button {
                mealEditorDraft = MealTemplateDraft()
            } label: {
                Label("recipes.add_saved_meal", systemImage: "fork.knife")
            }

            Button {
                catalogService.presentRecipeEditor(draft: RecipeDraft())
            } label: {
                Label("recipes.add", systemImage: "book.closed")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(Text("common.add"))
    }
}
