import Combine
import SwiftUI

final class TopSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var debouncedQuery: String = ""
    private var cancellables = Set<AnyCancellable>()

    init(debounceMs: Int = 400) {
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(debounceMs), scheduler: RunLoop.main)
            .sink { [weak self] value in self?.debouncedQuery = value }
            .store(in: &cancellables)
    }

    func reset() {
        query = ""
        debouncedQuery = ""
    }
}

struct ContentView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var diaryService: FoodDiaryService
    @EnvironmentObject private var catalogService: FoodCatalogService
    @EnvironmentObject private var habitsService: HabitsService
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @StateObject private var pushNotificationService = PushNotificationService.shared

    @State private var selectedTab: TabSelection = .today
    @State private var librarySection: EatometerLibrarySection = .products
    @State private var sidebarColumnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showEmailConfirmationResult = false
    @State private var emailConfirmationResultMessage: String? = nil
    @State private var hasExceededStartupPlaceholderDeadline = false
    @State private var todayPath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var habitsPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var tabIconAnimationToken = 0
    @State private var pendingRecipeShareReference: PendingRecipeShareReference?
    @State private var pendingMealShareReference: PendingMealShareReference?
    @State private var pendingMealTemplateShareReference: PendingMealTemplateShareReference?
    @State private var pendingUserProductShareReference: PendingUserProductShareReference?
    @State private var showsLaunchLogoOverlay = true
    @State private var isForegroundRefreshInFlight = false
    @State private var lastForegroundRefreshAt: Date?
    @State private var lastHabitFailureEnforcementAt: Date?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    private let foregroundRefreshThrottle: TimeInterval = 45
    private let habitFailureEnforcementThrottle: TimeInterval = 15 * 60

    private struct PendingRecipeShareReference: Identifiable, Hashable {
        let id = UUID()
        let reference: String
    }

    private struct PendingMealShareReference: Identifiable, Hashable {
        let id = UUID()
        let reference: String
    }

    private struct PendingMealTemplateShareReference: Identifiable, Hashable {
        let id = UUID()
        let reference: String
    }

    private struct PendingUserProductShareReference: Identifiable, Hashable {
        let id = UUID()
        let reference: String
    }

    enum TabSelection: String, CaseIterable, Identifiable {
        case today
        case library
        case habits
        case profile

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .today:
                return "tab.diary"
            case .library:
                return "tab.library"
            case .habits:
                return "habits.title"
            case .profile:
                return "profile.section.profile"
            }
        }

        var systemImage: String {
            switch self {
            case .today:
                return "book.pages.fill"
            case .library:
                return "square.stack.fill"
            case .habits:
                return "heart.fill"
            case .profile:
                return "person.crop.circle.fill"
            }
        }

        /// Outline variants used by the iPad sidebar, per the mock-ups.
        var sidebarSystemImage: String {
            switch self {
            case .today:
                return "book.pages"
            case .library:
                return "square.stack"
            case .habits:
                return "heart"
            case .profile:
                return "person.crop.circle"
            }
        }
    }

    var body: some View {
        ZStack {
            Group {
                if authService.isAuthenticated {
                    authenticatedContent
                        .sheet(isPresented: $authService.showProfile) {
                            NavigationStack {
                                NotificationInboxView()
                                    .toolbar {
                                        ToolbarItem(placement: .cancellationAction) {
                                            Button {
                                                authService.showProfile = false
                                            } label: {
                                                Image(systemName: "xmark")
                                            }
                                        }
                                    }
                            }
                        }
                        .task(id: authService.isAuthenticated) {
                            if authService.isAuthenticated {
                                await bootstrapAuthenticatedSession()
                            } else {
                                resetAuthenticatedSession()
                            }
                        }
                        .task(id: startupPlaceholderTrigger) {
                            guard authService.isAuthenticated else {
                                hasExceededStartupPlaceholderDeadline = false
                                return
                            }

                            hasExceededStartupPlaceholderDeadline = false
                            guard !diaryService.hasResolvedCalorieOnboardingState else { return }

                            try? await Task.sleep(nanoseconds: 500_000_000)
                            guard authService.isAuthenticated else { return }
                            hasExceededStartupPlaceholderDeadline = !diaryService.hasResolvedCalorieOnboardingState
                        }
                        .onChange(of: scenePhase) { _, newPhase in
                            guard authService.isAuthenticated, newPhase == .active else { return }
                            Task {
                                await refreshAuthenticatedData(force: false)
                            }
                        }
                } else {
                    AuthView()
                }
            }

            if showsLaunchLogoOverlay {
                launchLogoOverlay
                    .transition(.opacity)
            }
        }
        .sheet(item: $pendingRecipeShareReference) { pendingReference in
            SharedRecipeImportConfirmationSheet(shareReference: pendingReference.reference) {
                librarySection = .recipes
                selectedTab = .library
            }
            .environmentObject(catalogService)
        }
        .sheet(item: $pendingMealShareReference) { pendingReference in
            SharedMealImportSheet(shareCode: pendingReference.reference)
                .environmentObject(diaryService)
        }
        .sheet(item: $pendingMealTemplateShareReference) { pendingReference in
            SharedMealTemplateImportSheet(shareReference: pendingReference.reference) {
                librarySection = .meals
                selectedTab = .library
            }
            .environmentObject(catalogService)
        }
        .sheet(item: $pendingUserProductShareReference) { pendingReference in
            SharedUserProductImportSheet(shareReference: pendingReference.reference) {
                librarySection = .products
                selectedTab = .library
            }
            .environmentObject(catalogService)
        }
        .sheet(item: recipeEditorStoreBinding) { store in
            RecipeEditorSheet(store: store, catalogService: catalogService)
        }
        .task {
            guard let url = deepLinkRouter.pendingURL else { return }
            handleIncomingURL(url)
            deepLinkRouter.clear()
        }
        .onChange(of: deepLinkRouter.pendingURL) { _, pendingURL in
            guard let url = pendingURL else { return }
            handleIncomingURL(url)
            deepLinkRouter.clear()
        }
        .task {
            await handlePendingPushDeepLinkIfNeeded()
        }
        .onChange(of: pushNotificationService.pendingDeepLinkURL) { _, _ in
            Task { @MainActor in
                await handlePendingPushDeepLinkIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationDeepLink)) { notification in
            guard let url = notification.object as? URL else { return }
            Task { @MainActor in
                await handlePushDeepLink(url)
                pushNotificationService.consumePendingDeepLinkURL(url)
            }
        }
        .alert(emailConfirmationResultMessage ?? "", isPresented: $showEmailConfirmationResult) {
            Button("common.ok", role: .cancel) {}
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated else { return }
            if pendingRecipeShareReference != nil || pendingMealTemplateShareReference != nil {
                librarySection = pendingRecipeShareReference != nil ? .recipes : .meals
                selectedTab = .library
            }
        }
        .task {
            guard showsLaunchLogoOverlay else { return }
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                showsLaunchLogoOverlay = false
            }
        }
    }

    private var startupPlaceholderTrigger: String {
        [
            authService.isAuthenticated ? "auth" : "guest",
            diaryService.hasResolvedCalorieOnboardingState ? "resolved" : "pending"
        ].joined(separator: ":")
    }

    private var shouldShowStartupPlaceholder: Bool {
        !diaryService.hasResolvedCalorieOnboardingState && !hasExceededStartupPlaceholderDeadline
    }

    private func validateAuthenticatedSession() async -> Bool {
        guard authService.isAuthenticated else {
            resetAuthenticatedSession()
            return false
        }

        let sessionIsValid = await userService.fetchCurrentUser()
        guard sessionIsValid, authService.isAuthenticated else {
            resetAuthenticatedSession()
            return false
        }

        return true
    }

    private func bootstrapAuthenticatedSession() async {
        catalogService.restoreCachedCatalogIfAvailable()
        habitsService.restoreCachedHabitsIfAvailable()
        Task {
            await habitsService.preloadHabitsForCurrentSession()
        }
        if userService.currentUserID != nil {
            diaryService.setScope(userID: userService.currentUserID)
        }

        await refreshAuthenticatedData(force: true)
    }

    private func resetAuthenticatedSession() {
        userService.clearCachedProfile()
        diaryService.setScope(userID: nil)
        catalogService.clear()
        diaryService.clear()
        habitsService.clear()
        isForegroundRefreshInFlight = false
        lastForegroundRefreshAt = nil
        lastHabitFailureEnforcementAt = nil
    }

    private func refreshAuthenticatedData(force: Bool) async {
        guard authService.isAuthenticated else {
            resetAuthenticatedSession()
            return
        }

        if isForegroundRefreshInFlight {
            return
        }

        if !force,
           let lastForegroundRefreshAt,
           Date().timeIntervalSince(lastForegroundRefreshAt) < foregroundRefreshThrottle {
            diaryService.setScope(userID: userService.currentUserID)
            diaryService.refreshWaterStateFromSharedStorage()
            HabitLocalNotificationScheduler.shared.refreshWaterReminders(isWaterTrackingEnabled: diaryService.dailyWaterGoalMilliliters > 0)
            await habitsService.processPendingWidgetHabitCheckIns()
            guard diaryService.hasResolvedCalorieOnboardingState else { return }
            guard !diaryService.shouldShowCalorieOnboarding else { return }
            return
        }

        isForegroundRefreshInFlight = true
        defer { isForegroundRefreshInFlight = false }

        guard await validateAuthenticatedSession() else { return }

        diaryService.setScope(userID: userService.currentUserID)
        diaryService.refreshWaterStateFromSharedStorage()
        async let catalogReload: Void = catalogService.reloadCatalog()
        async let mealsReload: Void = diaryService.refreshActiveDayFromServer()
        async let habitsReload: Void = habitsService.preloadHabitsForCurrentSession()
        async let statsWarmUp: Void = diaryService.warmUpNutritionStatistics()
        async let inboxReload: Void = pushNotificationService.refreshInbox()
        await catalogReload
        await mealsReload
        await habitsReload
        await statsWarmUp
        await inboxReload
        await habitsService.processPendingWidgetHabitCheckIns()

        HabitLocalNotificationScheduler.shared.refreshWaterReminders(isWaterTrackingEnabled: diaryService.dailyWaterGoalMilliliters > 0)
        scheduleHabitFailureEnforcementIfNeeded()

        lastForegroundRefreshAt = Date()

        guard diaryService.hasResolvedCalorieOnboardingState else { return }
        guard !diaryService.shouldShowCalorieOnboarding else { return }
    }

    private func scheduleHabitFailureEnforcementIfNeeded() {
        let now = Date()
        if let lastHabitFailureEnforcementAt,
           now.timeIntervalSince(lastHabitFailureEnforcementAt) < habitFailureEnforcementThrottle {
            return
        }

        lastHabitFailureEnforcementAt = now
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await enforceAutomaticHabitFailures()
            await enforceManualHabitFailures()
        }
    }

    private func enforceAutomaticHabitFailures() async {
        let automaticHabits = habitsService.habits.filter { habit in
            !habit.isArchived && habit.trackingMode == .automatic && HabitAutomaticTracker(habit: habit) != nil
        }
        guard !automaticHabits.isEmpty else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let earliestAttemptStart = automaticHabits
            .compactMap { $0.currentAttempt?.startedAt }
            .map { calendar.startOfDay(for: $0) }
            .min()
        let fallbackStart = calendar.date(byAdding: .day, value: -120, to: today) ?? today
        await diaryService.loadMealHistory(from: earliestAttemptStart ?? fallbackStart, through: today)

        for habit in automaticHabits {
            guard let failedDay = HabitStreakResolver.failureDateRequiringReset(
                for: habit,
                diaryService: diaryService
            ) else { continue }

            let dayKey = DateFormatter.habitDay.string(from: failedDay)
            let resetReason = "automatic_failure:\(dayKey)"
            _ = await habitsService.resetProgress(habitID: habit.id, reason: resetReason)
        }
    }

    private func enforceManualHabitFailures() async {
        let manualHabits = habitsService.habits.filter { habit in
            !habit.isArchived && habit.trackingMode == .manual
        }
        guard !manualHabits.isEmpty else { return }

        for habit in manualHabits {
            guard let missedDay = HabitStreakResolver.manualFailureDateRequiringReset(
                for: habit,
                habitsService: habitsService
            ) else { continue }

            let dayKey = DateFormatter.habitDay.string(from: missedDay)
            let resetReason = "manual_missed:\(dayKey)"
            _ = await habitsService.resetProgress(habitID: habit.id, reason: resetReason)
        }
    }

    private var recipeEditorStoreBinding: Binding<RecipeEditorDraftStore?> {
        Binding(
            get: { catalogService.recipeEditorStore },
            set: { newValue in
                if newValue == nil {
                    catalogService.dismissRecipeEditor()
                }
            }
        )
    }

    @ViewBuilder
    private var authenticatedRootContent: some View {
        if shouldShowStartupPlaceholder {
            onboardingResolutionPlaceholder
        } else if diaryService.shouldShowCalorieOnboarding {
            // Onboarding is a full page, not a sheet – it owns the whole screen
            // until the calorie plan is set up.
            EatometerOnboardingView()
                .environmentObject(diaryService)
                .environmentObject(appSettings)
                .transition(.opacity)
        } else {
            NativeTabView()
                .transition(.opacity)
        }
    }

    private var authenticatedContent: some View {
        authenticatedRootContent
            .animation(.easeInOut(duration: 0.25), value: diaryService.shouldShowCalorieOnboarding)
            .sheet(isPresented: $diaryService.shouldShowCaloriePlanReview) {
                CaloriePlanReviewSheet(
                    onUpdate: { diaryService.startCaloriePlanUpdateFromReview() },
                    onDismiss: { diaryService.dismissCaloriePlanReview() }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }

    private var onboardingResolutionPlaceholder: some View {
        Color.platformSystemBackground
            .ignoresSafeArea()
    }

    private var launchLogoOverlay: some View {
        ZStack {
            Color.platformSystemBackground
                .ignoresSafeArea()

            Image("LaunchAppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 116)
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func navigationContent(for tab: TabSelection) -> some View {
        // `.tint(.primary)` keeps navigation-bar glyphs in the label colour, as
        // in the mock-ups. The tab bar itself stays accent-tinted because it is
        // rendered by the TabView, outside these stacks.
        switch tab {
        case .today:
            NavigationStack(path: $todayPath) {
                TodayView()
            }
            .tint(.primary)
        case .library:
            NavigationStack(path: $libraryPath) {
                EatometerLibraryView(selection: $librarySection)
            }
            .tint(.primary)
        case .habits:
            NavigationStack(path: $habitsPath) {
                HabitsView()
            }
            .tint(.primary)
        case .profile:
            NavigationStack(path: $profilePath) {
                EatometerProfileView()
            }
            .tint(.primary)
        }
    }

    /// Tabs shown in the iPhone tab bar / iPad sidebar (in order).
    private var primaryTabs: [TabSelection] {
        [.today, .library, .habits, .profile]
    }

    private var sidebarProfileName: String {
        let user = userService.currentUser
        let first = user?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !first.isEmpty { return first }
        let last = user?.lastName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !last.isEmpty { return last }
        let username = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return username.isEmpty ? "Eatometer" : username
    }

    private var sidebarProfileButton: some View {
        Button {
            authService.showProfile = true
        } label: {
            HStack(spacing: 11) {
                ProfileAvatarView(
                    username: sidebarProfileName,
                    appearance: userService.profileAppearance,
                    size: 34
                )
                Text(sidebarProfileName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// Optional selection proxy so the split view's own selection machinery
    /// drives the detail column (otherwise the detail doesn't refresh on switch).
    private var sidebarSelection: Binding<TabSelection?> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if let newValue { selectedTab = newValue }
            }
        )
    }

    @ViewBuilder
    private var iPadSplitLayout: some View {
        NavigationSplitView(columnVisibility: $sidebarColumnVisibility) {
            List(selection: sidebarSelection) {
                ForEach([TabSelection.today, .habits, .profile]) { tab in
                    Label(tab.titleKey, systemImage: tab.sidebarSystemImage)
                        .lineLimit(1)
                        .tag(tab)
                }

                Section("tab.library") {
                    ForEach(EatometerLibrarySection.allCases) { section in
                        let isSelected = selectedTab == .library && librarySection == section

                        Button {
                            librarySection = section
                            selectedTab = .library
                        } label: {
                            Label(section.title, systemImage: section.systemImage)
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? Color.appAccent : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                        )
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Eatometer"))
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 244, ideal: 264, max: 320)
            .safeAreaInset(edge: .bottom) {
                sidebarProfileButton
            }
        } detail: {
            navigationContent(for: selectedTab)
                .id(selectedTab)
                .background(detailBackground.ignoresSafeArea())
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.appAccent)
    }

    /// Fills the detail column gutters with the same color the selected screen
    /// uses, so wide layouts read as one surface instead of a grey stripe.
    private var detailBackground: Color {
        EOTheme.Palette.pageBackground
    }

    @ViewBuilder
    func NativeTabView() -> some View {
        if horizontalSizeClass == .regular {
            iPadSplitLayout
        } else {
            iPhoneTabLayout()
        }
    }

    @ViewBuilder
    func iPhoneTabLayout() -> some View {
        TabView(selection: $selectedTab) {
            Tab(value: .today) {
                navigationContent(for: .today)
            } label: {
                tabLabel(tab: .today)
            }

            Tab(value: .library) {
                navigationContent(for: .library)
            } label: {
                tabLabel(tab: .library)
            }

            Tab(value: .habits) {
                navigationContent(for: .habits)
            } label: {
                tabLabel(tab: .habits)
            }

            Tab(value: .profile) {
                navigationContent(for: .profile)
            } label: {
                tabLabel(tab: .profile)
            }
        }
        .tint(.appAccent)
        .onChange(of: selectedTab) { _, _ in
            tabIconAnimationToken += 1
        }
    }

    private func tabLabel(tab: TabSelection) -> some View {
        VStack(spacing: 4) {
            Image(systemName: tab.systemImage)
                .symbolEffect(.bounce, value: selectedTab == tab ? tabIconAnimationToken : 0)
            Text(tab.titleKey)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let host = components.host?.lowercased() ?? ""
        let route = path.isEmpty ? host : path

        // Diary deep link: eatometer://diary?meal_slot_id=breakfast
        if route == "diary" {
            selectedTab = .today
            todayPath = NavigationPath()
            deepLinkRouter.pendingMealQuickAdd = nil
            if let open = components.queryItems?.first(where: { $0.name == "open" })?.value,
               !open.isEmpty {
                switch open.lowercased() {
                case "water":
                    diaryService.refreshWaterStateFromSharedStorage()
                    deepLinkRouter.pendingOpenWater = true
                case "meals":
                    deepLinkRouter.pendingOpenMeals = true
                default:
                    break
                }
            }
            if let quickAddType = components.queryItems?.first(where: { $0.name == "quick_add_type" })?.value,
               let quickAddKind = PendingMealQuickAdd.Kind(rawValue: quickAddType),
               let quickAddIDValue = components.queryItems?.first(where: { $0.name == "quick_add_id" })?.value,
               let quickAddID = UUID(uuidString: quickAddIDValue) {
                deepLinkRouter.pendingMealQuickAdd = PendingMealQuickAdd(kind: quickAddKind, id: quickAddID)
            }
            if let mealSlotID = components.queryItems?.first(where: { $0.name == "meal_slot_id" })?.value,
               !mealSlotID.isEmpty {
                deepLinkRouter.pendingMealSlotID = mealSlotID
            }
            if let mealIDValue = components.queryItems?.first(where: { $0.name == "meal_id" })?.value,
               let mealID = UUID(uuidString: mealIDValue) {
                deepLinkRouter.pendingMealID = mealID
            }
            return
        }

        // Water deep link: eatometer://water
        if route == "water" {
            selectedTab = .today
            todayPath = NavigationPath()
            diaryService.refreshWaterStateFromSharedStorage()
            deepLinkRouter.pendingOpenWater = true
            return
        }

        // Habit deep link: eatometer://habits?habit_id=<uuid>
        if ["habit", "habits"].contains(route) {
            selectedTab = .habits
            habitsPath = NavigationPath()
            let habitID = habitID(from: components)
            Task { @MainActor in
                await Task.yield()
                guard let habitID else { return }
                if !habitsService.habits.contains(where: { $0.id == habitID }) {
                    await habitsService.preloadHabitsForCurrentSession()
                }
                guard habitsService.habits.contains(where: { $0.id == habitID }) else { return }

                await Task.yield()
                deepLinkRouter.pendingHabitID = habitID
            }
            return
        }

        if route == "friends" {
            authService.showProfile = false
            selectedTab = .profile
            profilePath = NavigationPath()
            return
        }

        // Calorie plan review deep link: eatometer://calorie-plan-review
        if ["calorie-plan-review", "calorie_plan_review"].contains(route) {
            authService.showProfile = false
            diaryService.shouldShowCaloriePlanReview = true
            return
        }

        if ["confirm-email", "confirm_email", "confirmemail"].contains(route),
           let code = components.queryItems?.first(where: { $0.name == "token" })?.value,
           !code.isEmpty {
            Task { @MainActor in
                let success = await authService.confirmEmail(code: code)
                emailConfirmationResultMessage = success ? "Email confirmed successfully." : "Failed to confirm email. Please try again in the app."
                showEmailConfirmationResult = true
            }
            return
        }

        if let mealTemplateReference = catalogService.sharedMealTemplateReference(from: url.absoluteString) {
            authService.showProfile = false
            pendingMealTemplateShareReference = PendingMealTemplateShareReference(reference: mealTemplateReference)
            librarySection = .meals
            selectedTab = .library
            return
        }

        if let mealReference = catalogService.sharedMealReference(from: url.absoluteString) {
            authService.showProfile = false
            pendingMealShareReference = PendingMealShareReference(reference: mealReference)
            selectedTab = .today
            return
        }

        if let productReference = catalogService.sharedUserProductReference(from: url.absoluteString) {
            authService.showProfile = false
            pendingUserProductShareReference = PendingUserProductShareReference(reference: productReference)
            librarySection = .products
            selectedTab = .library
            return
        }

        guard let shareReference = catalogService.sharedRecipeReference(from: url.absoluteString) else {
            return
        }

        authService.showProfile = false
        pendingRecipeShareReference = PendingRecipeShareReference(reference: shareReference)
        librarySection = .recipes
        selectedTab = .library
    }

    private func handlePendingPushDeepLinkIfNeeded() async {
        guard let url = pushNotificationService.pendingDeepLinkURL else { return }
        await handlePushDeepLink(url)
        pushNotificationService.consumePendingDeepLinkURL(url)
    }

    private func handlePushDeepLink(_ url: URL) async {
        let wasProfilePresented = authService.showProfile
        if wasProfilePresented {
            authService.showProfile = false
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        handleIncomingURL(url)
        deepLinkRouter.clear()
    }

    private func habitID(from components: URLComponents) -> UUID? {
        let value = components.queryItems?.first(where: { item in
            ["habit_id", "habitID", "habitId"].contains(item.name)
        })?.value
        guard let value else { return nil }
        return UUID(uuidString: value)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings.shared)
        .environmentObject(FoodDiaryService())
        .environmentObject(FoodCatalogService())
        .environmentObject(HabitsService())
}
