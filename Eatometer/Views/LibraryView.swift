import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var catalogService: FoodCatalogService
    @EnvironmentObject private var habitsService: HabitsService
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var mainHeaderScrollOffset: CGFloat = 0

    private var pageBackground: Color {
        colorScheme == .dark ? Color.platformSystemGroupedBackground : Color.platformSystemGray6
    }

    private var compactHeaderProgress: CGFloat {
        min(1, max(0, (mainHeaderScrollOffset - 30) / 30))
    }

    private var topOverscrollFillHeight: CGFloat {
        max(0, -mainHeaderScrollOffset) + 96
    }

    private var topOverscrollFillColor: Color {
        pageBackground
    }

    enum Folder: String, Identifiable, CaseIterable {
        case recipes
        case products
        case meals
        case habits

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .habits: return "library.folder.habits"
            case .recipes: return "library.folder.recipes"
            case .products: return "library.folder.products"
            case .meals: return "library.folder.meals"
            }
        }

        var systemImage: String {
            switch self {
            case .habits: return "leaf.fill"
            case .recipes: return "fork.knife"
            case .products: return "basket.fill"
            case .meals: return "square.stack.3d.up.fill"
            }
        }

        var tint: Color {
            switch self {
            case .habits: return .teal
            case .recipes: return .orange
            case .products: return .green
            case .meals: return .mint
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { proxy in
                let topInset = proxy.safeAreaInsets.top

                Rectangle()
                    .fill(topOverscrollFillColor)
                    .frame(height: topOverscrollFillHeight)
                    .ignoresSafeArea(edges: horizontalSizeClass == .regular ? [] : .top)
                    .opacity(mainHeaderScrollOffset < 0 ? 1 : 0)
                    .allowsHitTesting(false)

                scrollContent(topInset: topInset)
            }

            MainHeaderCompactOverlay(
                title: "library.title",
                username: authService.currentUsername,
                onProfileTap: { authService.showProfile = true },
                progress: compactHeaderProgress
            )
        }
        .background(pageBackground.ignoresSafeArea())
        .rootNavigationChrome("library.title")
        .navigationDestination(for: Folder.self) { folder in
            destination(for: folder)
        }
    }

    @ViewBuilder
    private func destination(for folder: Folder) -> some View {
        switch folder {
        case .habits:
            HabitsView()
        case .recipes:
            LibraryRecipesFolderView()
        case .meals:
            LibraryMealsFolderView()
        case .products:
            LibraryProductsFolderView()
        }
    }

    private func scrollContent(topInset: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                MainHeaderView(
                    title: "library.title",
                    username: authService.currentUsername,
                    onProfileTap: { authService.showProfile = true }
                )
                .padding(.horizontal, 20)
                .padding(.top, horizontalSizeClass == .regular ? 0 : topInset + 8)
                .opacity(1 - compactHeaderProgress)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(Folder.allCases) { folder in
                        NavigationLink(value: folder) {
                            folderCard(folder)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
                    .frame(height: 24)
            }
        }
        .ignoresSafeArea(edges: horizontalSizeClass == .regular ? [] : .top)
        .scrollContentBackground(.hidden)
        .coordinateSpace(name: "library-main-scroll")
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newValue in
            mainHeaderScrollOffset = newValue
        }
    }

    private func folderCard(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(folder.tint.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: folder.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(folder.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(folder.titleKey))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle(for: folder))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                .fill(Color.appCardBackground)
        )
    }

    private func subtitle(for folder: Folder) -> String {
        switch folder {
        case .habits:
            return countString(habitsService.habits.count, key: "library.count.habits")
        case .recipes:
            return countString(catalogService.recipes.count, key: "library.count.recipes")
        case .products:
            return countString(catalogService.products.count, key: "library.count.products")
        case .meals:
            return countString(catalogService.mealTemplates.count, key: "library.count.meals")
        }
    }

    private func countString(_ count: Int, key: String) -> String {
        let format = NSLocalizedString(key, comment: "Library folder subtitle")
        return String(format: format, count)
    }
}
