import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var diaryService: FoodDiaryService
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var catalogService: FoodCatalogService
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var mealEditorDestination: MealEditorDestination?
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var isAddWaterPresented = false
    @State private var isNotificationsPresented = false
    @State private var mainHeaderScrollOffset: CGFloat = 0
    @State private var pendingShareSheetItem: SystemShareSheetItem?
    @State private var savedMealMessage: String?
    @State private var presentedMealViewer: PresentedMealViewer?

    private struct PresentedMealViewer: Identifiable {
        let meal: MealEntry
        var id: UUID { meal.id }
    }

    @Namespace private var mealCardZoomNamespace

    private let mainHeaderScrollCoordinateSpace = "today-main-scroll"
    private let waterCardScrollID = "today-water-card"
    private let mealsSectionScrollID = "today-meals-section"

    private enum MealEditorDestination: Identifiable, Hashable {
        case create(categoryID: String, day: Date, quickAdd: PendingMealQuickAdd?)
        case edit(MealEntry, sourceMealIDs: [UUID], quickAdd: PendingMealQuickAdd?)

        var id: String {
            switch self {
            case .create(let categoryID, let day, let quickAdd):
                return "create-\(categoryID)-\(day.timeIntervalSince1970)-\(quickAdd?.id.uuidString ?? "none")"
            case .edit(let meal, let sourceMealIDs, let quickAdd):
                let sourceKey = sourceMealIDs.map(\.uuidString).joined(separator: "-")
                return "edit-\(meal.id.uuidString)-\(sourceKey)-\(quickAdd?.id.uuidString ?? "none")"
            }
        }

        var sourceCategoryID: String {
            switch self {
            case .create(let categoryID, _, _):
                return categoryID
            case .edit(let meal, _, _):
                return meal.mealCategoryID
            }
        }
    }

    private var currentDay: Date {
        Calendar.current.startOfDay(for: .now)
    }

    private var liveMealsSummary: NutritionSummary {
        NutritionSummary(
            calories: diaryService.totalCalories,
            protein: diaryService.totalProtein,
            fat: diaryService.totalFat,
            carbs: diaryService.totalCarbs
        )
    }

    private var currentDaySummary: NutritionSummary {
        diaryService.dailyHistory[currentDay] ?? liveMealsSummary
    }

    private var selectedDaySummary: NutritionSummary {
        let normalizedSelectedDay = Calendar.current.startOfDay(for: selectedDay)
        if normalizedSelectedDay == currentDay {
            return currentDaySummary
        }

        return diaryService.dailyHistory[normalizedSelectedDay] ?? liveMealsSummary
    }

    private var visibleCategories: [MealCategory] {
        diaryService.visibleMealCategories
    }

    private var compactHeaderProgress: CGFloat {
        min(1, max(0, (mainHeaderScrollOffset - 30) / 30))
    }

    private var topOverscrollFillHeight: CGFloat {
        max(0, -mainHeaderScrollOffset) + 96
    }

    private var topOverscrollFillColor: Color {
        EOTheme.Palette.pageBackground
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .topLeading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(topOverscrollFillColor)
                        .frame(height: topOverscrollFillHeight)
                        .ignoresSafeArea(edges: .top)
                        .opacity(mainHeaderScrollOffset < 0 ? 1 : 0)
                        .allowsHitTesting(false)

                    scrollContent(availableWidth: proxy.size.width)
                }
            }
            .eoPageBackground()
            .navigationTitle("diary.title")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItemGroup(placement: .platformTopBarTrailing) {
                    Button {
                        isNotificationsPresented = true
                    } label: {
                        Label("profile.notifications.inbox.title", systemImage: "bell")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .sheet(item: $mealEditorDestination) { destination in
                Group {
                    switch destination {
                    case .create(let categoryID, let day, let quickAdd):
                        AddMealSheetView(
                            preferredCategoryID: categoryID,
                            preferredDate: day,
                            initialQuickAdd: quickAdd
                        )

                    case .edit(let meal, let sourceMealIDs, let quickAdd):
                        AddMealSheetView(editingMeal: meal, mergedSourceMealIDs: sourceMealIDs, initialQuickAdd: quickAdd)
                    }
                }
                .environmentObject(diaryService)
                .environmentObject(catalogService)
                .presentationDragIndicator(.visible)
            }
            .navigationDestination(isPresented: $isNotificationsPresented) {
                NotificationInboxView()
            }
            .sheet(isPresented: $isAddWaterPresented) {
                AddWaterSheet(
                    currentMilliliters: diaryService.waterIntake(for: selectedDay),
                    goalMilliliters: diaryService.dailyWaterGoalMilliliters,
                    step: appSettings.waterWidgetStepMilliliters,
                    onSet: { ml in
                        diaryService.setWaterIntake(ml, for: selectedDay)
                    }
                )
            }
            .sheet(item: $presentedMealViewer) { viewer in
                MealEntryViewerSheet(
                    title: viewer.meal.title,
                    items: viewer.meal.items,
                    nutrition: viewer.meal.nutrition,
                    onShare: { shareMeal(viewer.meal) }
                )
                .environmentObject(catalogService)
            }
            .sheet(item: $pendingShareSheetItem) { item in
                SystemShareSheet(draft: item) {
                    pendingShareSheetItem = nil
                }
            }
            .alert(savedMealMessage ?? "", isPresented: Binding(
                get: { savedMealMessage != nil },
                set: { if !$0 { savedMealMessage = nil } }
            )) {
                Button("common.ok", role: .cancel) {}
            }
            .task(id: selectedDay) {
                await diaryService.loadMeals(for: selectedDay)
            }
            .task(id: deepLinkRouter.pendingOpenWater) {
                guard deepLinkRouter.pendingOpenWater else { return }
                deepLinkRouter.pendingOpenWater = false
                selectedDay = currentDay
                await Task.yield()
                await Task.yield()
                if appSettings.isWaterTrackingEnabled {
                    withAnimation(.easeInOut(duration: 0.32)) {
                        scrollProxy.scrollTo(waterCardScrollID, anchor: .center)
                    }
                }
                await Task.yield()
                isAddWaterPresented = true
            }
            .task(id: deepLinkRouter.pendingOpenMeals) {
                guard deepLinkRouter.pendingOpenMeals else { return }
                deepLinkRouter.pendingOpenMeals = false
                selectedDay = currentDay
                await Task.yield()
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.32)) {
                    scrollProxy.scrollTo(mealsSectionScrollID, anchor: .top)
                }
            }
            .onChange(of: selectedDay) { _, newValue in
                let normalizedDay = Calendar.current.startOfDay(for: newValue)
                if normalizedDay != newValue {
                    selectedDay = normalizedDay
                }
            }
            .onChange(of: deepLinkRouter.pendingMealSlotID) { _, slotID in
                guard let slotID, !slotID.isEmpty else { return }
                deepLinkRouter.pendingMealSlotID = nil
                let quickAdd = deepLinkRouter.pendingMealQuickAdd
                deepLinkRouter.pendingMealQuickAdd = nil
                if let category = visibleCategories.first(where: { $0.id == slotID }) {
                    editMealCategory(category, quickAdd: quickAdd)
                }
            }
            .onChange(of: deepLinkRouter.pendingMealID) { _, mealID in
                guard let mealID else { return }
                deepLinkRouter.pendingMealID = nil

                Task { @MainActor in
                    guard let meal = diaryService.mealForNavigation(id: mealID) else {
                        deepLinkRouter.pendingOpenMeals = true
                        return
                    }

                    let mealDay = Calendar.current.startOfDay(for: meal.scheduledAt)
                    if !Calendar.current.isDate(selectedDay, inSameDayAs: mealDay) {
                        selectedDay = mealDay
                        await diaryService.loadMeals(for: mealDay)
                    }

                    if let resolvedMeal = diaryService.mealForNavigation(id: mealID) {
                        presentMealEditor(.edit(resolvedMeal, sourceMealIDs: [resolvedMeal.id], quickAdd: nil))
                    } else {
                        deepLinkRouter.pendingOpenMeals = true
                    }
                }
            }
        }
    }

    private func meals(for category: MealCategory) -> [MealEntry] {
        diaryService.meals.filter { $0.mealCategoryID == category.id }
    }

    private func mealTarget(for category: MealCategory) -> NutritionSummary {
        diaryService.mealGoal(for: category, on: selectedDay)
    }

    private func sortedMeals(for category: MealCategory) -> [MealEntry] {
        meals(for: category).sorted { lhs, rhs in
            if lhs.scheduledAt != rhs.scheduledAt {
                return lhs.scheduledAt < rhs.scheduledAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// A plain tap opens the read-only viewer (so the meal can be shared);
    /// editing is reached from the card's context menu. An empty category has
    /// nothing to view, so it goes straight to the editor.
    private func openMealCategory(_ category: MealCategory) {
        guard let meal = mergedMeal(for: category, from: sortedMeals(for: category)) else {
            editMealCategory(category)
            return
        }

        presentedMealViewer = PresentedMealViewer(meal: meal)
    }

    private func editMealCategory(_ category: MealCategory, quickAdd: PendingMealQuickAdd? = nil) {
        let categoryMeals = sortedMeals(for: category)

        if let editingMeal = mergedMeal(for: category, from: categoryMeals) {
            presentMealEditor(.edit(editingMeal, sourceMealIDs: categoryMeals.map(\.id), quickAdd: quickAdd))
            return
        }

        presentMealEditor(.create(
            categoryID: category.id,
            day: Calendar.current.startOfDay(for: selectedDay),
            quickAdd: quickAdd
        ))
    }

    private func presentMealEditor(_ destination: MealEditorDestination) {
        mealEditorDestination = nil
        Task { @MainActor in
            await Task.yield()
            mealEditorDestination = destination
        }
    }

    private func mergedMeal(for category: MealCategory, from categoryMeals: [MealEntry]) -> MealEntry? {
        guard var mergedMeal = categoryMeals.first else { return nil }

        mergedMeal.title = category.displayTitle
        mergedMeal.mealCategoryID = category.id
        mergedMeal.items = categoryMeals.flatMap(\.items)
        mergedMeal.note = categoryMeals
            .map { $0.note.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        mergedMeal.nutrition = NutritionSummary(
            calories: categoryMeals.reduce(0) { $0 + $1.calories },
            protein: categoryMeals.reduce(0) { $0 + $1.protein },
            fat: categoryMeals.reduce(0) { $0 + $1.fat },
            carbs: categoryMeals.reduce(0) { $0 + $1.carbs }
        )
        return mergedMeal
    }

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scrollContent(availableWidth: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                compactDateSelector

                if isRegularLayout {
                    regularSummarySection
                } else {
                    DiaryOverviewCards(
                        waterMilliliters: diaryService.waterIntake(for: selectedDay),
                        waterGoalMilliliters: diaryService.dailyWaterGoalMilliliters,
                        summary: selectedDaySummary,
                        goal: diaryService.dailyGoal,
                        onOpenWater: { isAddWaterPresented = true },
                        showsWater: appSettings.isWaterTrackingEnabled,
                        onAdjustWater: adjustWater,
                        quickStepMilliliters: appSettings.waterWidgetStepMilliliters
                    )
                    .id(waterCardScrollID)
                    .padding(.horizontal, 20)
                }

                mealCategoriesSection
            }
            .frame(width: max(availableWidth, 0), alignment: .leading)
        }
        .coordinateSpace(name: mainHeaderScrollCoordinateSpace)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newValue in
            mainHeaderScrollOffset = newValue
        }
    }

    /// Summary strip shown on iPad: horizontally scrolling level cards.
    private var regularSummarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EOSectionHeader("today.summary.title")

            DiaryRegularSummaryRow(
                waterMilliliters: diaryService.waterIntake(for: selectedDay),
                waterGoalMilliliters: diaryService.dailyWaterGoalMilliliters,
                summary: selectedDaySummary,
                goal: diaryService.dailyGoal,
                showsWater: appSettings.isWaterTrackingEnabled,
                onOpenWater: { isAddWaterPresented = true }
            )
            .id(waterCardScrollID)
        }
    }

    /// Compact date control: a capsule with the selected day that drops a small
    /// calendar below it. Being an overlay, it never pushes the cards down.
    private var compactDateSelector: some View {
        HStack {
            DatePicker(
                "diary.title",
                selection: $selectedDay,
                in: ...currentDay,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()

            Spacer(minLength: 0)
        }
        .padding(.horizontal, EOTheme.Metrics.screenInset)
    }

    @ViewBuilder
    private var mealCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EOSectionHeader("today.meals.title")

            if isRegularLayout {
                DiaryRegularMealsRow(
                    categories: visibleCategories,
                    items: { category in
                        meals(for: category).flatMap { $0.items.map(\.name) }
                    },
                    calories: { category in
                        meals(for: category).reduce(0) { $0 + $1.calories }
                    },
                    onOpen: { category in
                        openMealCategory(category)
                    },
                    contextMenu: { category in
                        AnyView(mealContextMenu(for: category))
                    }
                )
            } else {
                ForEach(visibleCategories) { category in
                    mealCategoryRow(for: category)
                }
            }
        }
        .id(mealsSectionScrollID)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private func mealContextMenu(for category: MealCategory) -> some View {
        let categoryID = category.id

        Button {
            withCurrentCategory(categoryID) { editMealCategory($0) }
        } label: {
            Label("meal.context.edit", systemImage: "pencil")
        }

        Button {
            withCurrentCategory(categoryID) { shareMeal($0) }
        } label: {
            Label("meal.context.share", systemImage: "square.and.arrow.up")
        }

        Button {
            withCurrentCategory(categoryID) { saveMealToLibrary($0) }
        } label: {
            Label("meal.context.save", systemImage: "square.and.arrow.down")
        }
    }

    /// Menu content is built once and can outlive the value it captured, so the
    /// actions resolve the category from the live list by id instead.
    private func withCurrentCategory(_ id: String, _ action: (MealCategory) -> Void) {
        guard let category = visibleCategories.first(where: { $0.id == id }) else { return }
        action(category)
    }

    private func mealCategoryRow(for category: MealCategory) -> some View {
        MealCategoryCard(
            category: category,
            meals: meals(for: category),
            target: mealTarget(for: category),
            onOpen: { openMealCategory(category) }
        )
        .matchedTransitionSource(id: category.id, in: mealCardZoomNamespace)
        .eoCardContextMenu {
            mealContextMenu(for: category)
        }
        // Otherwise identical rows: pin each one to its category so SwiftUI
        // can't reuse a row — and its context-menu interaction — for the meal
        // that follows it in the list.
        .id(category.id)
        .padding(.horizontal, EOTheme.Metrics.screenInset)
    }

    /// Applies a signed water delta, clamped so intake never goes negative.
    private func adjustWater(by delta: Int) {
        let current = diaryService.waterIntake(for: selectedDay)
        let updated = max(0, min(10_000, current + delta))
        guard updated != current else { return }
        diaryService.setWaterIntake(updated, for: selectedDay)
    }

    private func shareMeal(_ category: MealCategory) {
        guard let meal = mergedMeal(for: category, from: sortedMeals(for: category)) else { return }
        shareMeal(meal)
    }

    private func shareMeal(_ meal: MealEntry) {
        Task {
            guard let payload = await diaryService.shareMeal(id: meal.id),
                  let link = payload.resolvedShareLink else { return }

            if let url = payload.resolvedShareURL {
                pendingShareSheetItem = SystemShareSheetItem(message: payload.localizedShareMessage, url: url)
            } else {
                pendingShareSheetItem = SystemShareSheetItem(message: payload.localizedShareMessage, text: link)
            }
        }
    }

    private func saveMealToLibrary(_ category: MealCategory) {
        let categoryMeals = meals(for: category).sorted { $0.scheduledAt < $1.scheduledAt }
        guard let meal = mergedMeal(for: category, from: categoryMeals) else { return }

        Task {
            var draft = MealTemplateDraft()
            draft.title = meal.title
            draft.items = meal.items
            let saved = await catalogService.saveMealTemplate(draft) != nil
            savedMealMessage = saved
                ? NSLocalizedString("meal.context.saved", comment: "Meal saved")
                : NSLocalizedString("meal.context.save_failed", comment: "Meal save failed")
        }
    }

    private func dayTitle(for day: Date) -> String {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        if Calendar.current.isDateInToday(normalizedDay) {
            return NSLocalizedString("today.calendar.today_button", comment: "Today label")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter.string(from: normalizedDay)
    }

}
