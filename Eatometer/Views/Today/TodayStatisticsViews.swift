import SwiftUI

struct NutritionStatisticsView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var diaryService: FoodDiaryService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let initialDay: Date

    @State private var anchorDay: Date
    @State private var statistics: NutritionStatisticsSnapshot?
    @State private var previousStatistics: NutritionStatisticsSnapshot?
    @State private var isLoading = false
    @State private var mainHeaderScrollOffset: CGFloat = 0
    @State private var weekTransitionDirection = 1
    /// Current logging streak, always computed from the present week regardless
    /// of which week is being browsed, so the Streak card never shifts.
    @State private var currentStreakDays = 0

    private var compactHeaderProgress: CGFloat {
        min(1, max(0, (mainHeaderScrollOffset - 30) / 30))
    }

    init(initialDay: Date) {
        let normalizedDay = Calendar.current.startOfDay(for: initialDay)
        self.initialDay = normalizedDay
        self._anchorDay = State(initialValue: normalizedDay)
        self._statistics = State(initialValue: nil)
        self._previousStatistics = State(initialValue: nil)
    }

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                scrollContent(
                    topInset: proxy.safeAreaInsets.top,
                    availableWidth: proxy.size.width - StatisticsGridMetrics.horizontalPadding * 2
                )
            }

            MainHeaderCompactOverlay(
                title: "today.stats.title",
                username: authService.currentUsername,
                onProfileTap: { authService.showProfile = true },
                progress: compactHeaderProgress
            )
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .rootNavigationChrome("today.stats.title")
        .navigationDestination(for: StatisticsDetailRoute.self) { route in
            NutritionStatisticDetailView(route: route, initialDay: anchorDay)
        }
        .task(id: anchorDay) {
            applyCachedStatistics()
            await reloadStatistics()
        }
        .task {
            await loadCurrentStreak()
        }
    }

    private func loadCurrentStreak() async {
        // Always computed from real continuous history ending today, independent
        // of which week is being browsed, so the Streak card is stable.
        currentStreakDays = await diaryService.loggingStreakDays()
    }

    private func scrollContent(topInset: CGFloat, availableWidth: CGFloat) -> some View {
        let tileSide = StatisticsGridMetrics.tileSide(for: availableWidth)

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: StatisticsGridMetrics.spacing) {
                MainHeaderView(
                    title: "today.stats.title",
                    username: authService.currentUsername,
                    onProfileTap: { authService.showProfile = true }
                )
                .opacity(1 - compactHeaderProgress)
                .padding(.top, horizontalSizeClass == .regular ? 0 : topInset + 8)
                .padding(.bottom, 8)

                StatisticsWeekSwitcher(
                    anchorDay: anchorDay,
                    transitionDirection: weekTransitionDirection,
                    canMoveForward: !statisticsIsCurrentWeek(anchorDay),
                    onPrevious: { shiftWeek(-1) },
                    onNext: { shiftWeek(1) }
                )

                weekContent(tileSide: tileSide)
            }
            .padding(.horizontal, StatisticsGridMetrics.horizontalPadding)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: horizontalSizeClass == .regular ? [] : .top)
        .refreshable {
            await reloadStatistics()
            await loadCurrentStreak()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newValue in
            mainHeaderScrollOffset = newValue
        }
    }

    @ViewBuilder
    private func weekContent(tileSide: CGFloat) -> some View {
        if let statistics {
            VStack(alignment: .leading, spacing: StatisticsGridMetrics.spacing) {
                topInsightGrid(for: statistics, tileSide: tileSide)

                NavigationLink(value: StatisticsDetailRoute.macros) {
                    WeeklyMacroCaloriesCard(
                        entries: weeklyMacroEntries(for: statistics),
                        selectedDay: anchorDay,
                        averageSummary: statistics.summary.averagePerDay
                    )
                }
                .buttonStyle(.plain)

                metricGrid(for: statistics, tileSide: tileSide)
            }
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
        } else {
            NutritionStatisticsEmptyStateCard()
        }
    }

    private func reloadStatistics() async {
        isLoading = statistics == nil
        defer { isLoading = false }

        let currentSnapshot = await diaryService.loadNutritionStatistics(period: .week, anchor: anchorDay)
        guard let currentSnapshot else { return }

        let previousAnchor = Calendar.current.date(byAdding: .day, value: -7, to: currentSnapshot.selectedAt)
            ?? currentSnapshot.selectedAt
        async let previousSnapshot = diaryService.loadNutritionStatistics(period: .week, anchor: previousAnchor)
        let resolvedPrevious = await previousSnapshot

        withAnimation(.easeInOut(duration: 0.25)) {
            statistics = currentSnapshot
            previousStatistics = resolvedPrevious
        }
    }

    private func applyCachedStatistics() {
        guard let cachedStatistics = diaryService.cachedNutritionStatistics(period: .week, anchor: anchorDay) else {
            statistics = nil
            previousStatistics = nil
            return
        }

        let previousAnchor = Calendar.current.date(byAdding: .day, value: -7, to: cachedStatistics.selectedAt)
            ?? cachedStatistics.selectedAt
        statistics = cachedStatistics
        previousStatistics = diaryService.cachedNutritionStatistics(period: .week, anchor: previousAnchor)
    }

    @ViewBuilder
    private func topInsightGrid(for statistics: NutritionStatisticsSnapshot, tileSide: CGFloat) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.fixed(tileSide), spacing: StatisticsGridMetrics.spacing),
                GridItem(.fixed(tileSide), spacing: StatisticsGridMetrics.spacing)
            ],
            spacing: StatisticsGridMetrics.spacing
        ) {
            StreakInsightCard(days: currentStreakDays)
                .frame(width: tileSide, height: tileSide)

            NavigationLink(value: StatisticsDetailRoute.calorieBalance) {
                CalorieBalanceInsightCard(insight: calorieBalanceInsight(for: statistics))
                    .frame(width: tileSide, height: tileSide)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func metricGrid(for statistics: NutritionStatisticsSnapshot, tileSide: CGFloat) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.fixed(tileSide), spacing: StatisticsGridMetrics.spacing),
                GridItem(.fixed(tileSide), spacing: StatisticsGridMetrics.spacing)
            ],
            spacing: StatisticsGridMetrics.spacing
        ) {
            ForEach(InsightMetricKind.allCases) { metric in
                NavigationLink(value: StatisticsDetailRoute.metric(metric)) {
                    InsightMetricCard(
                        metric: metric,
                        averageValue: metric.value(from: statistics.summary.averagePerDay),
                        trend: trend(for: metric, statistics: statistics),
                        buckets: statistics.buckets
                    )
                    .frame(width: tileSide, height: tileSide)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func weeklyMacroEntries(for statistics: NutritionStatisticsSnapshot) -> [WeeklyMacroCaloriesEntry] {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: statistics.selectedAt)?.start
            ?? calendar.startOfDay(for: statistics.periodStart)
        var bucketsByDay: [Date: NutritionStatisticsBucket] = [:]
        for bucket in statistics.buckets {
            bucketsByDay[calendar.startOfDay(for: bucket.startAt)] = bucket
        }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                return nil
            }
            let normalizedDay = calendar.startOfDay(for: day)
            return WeeklyMacroCaloriesEntry(
                date: normalizedDay,
                summary: bucketsByDay[normalizedDay]?.total ?? .zero
            )
        }
    }


    private func completedLoggedDayStreak(
        currentBuckets: [NutritionStatisticsBucket],
        previousBuckets: [NutritionStatisticsBucket]
    ) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var bucketsByDay: [Date: NutritionStatisticsBucket] = [:]
        for bucket in previousBuckets + currentBuckets {
            bucketsByDay[calendar.startOfDay(for: bucket.startAt)] = bucket
        }

        var day = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var streak = 0
        while let bucket = bucketsByDay[day], bucket.hasEntries {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }
        return streak
    }

    private func calorieBalanceInsight(for statistics: NutritionStatisticsSnapshot) -> CalorieBalanceInsight {
        let averageCalories = statistics.summary.averagePerDay.calories
        let averageGoal = averageGoalCalories(in: statistics.buckets)
        let dailyDelta = averageCalories - (averageGoal ?? averageCalories)
        let weeklyWeightKilograms = Double(abs(dailyDelta)) * 7.0 / 7700.0
        let progressLimit = max(Double(averageGoal ?? max(averageCalories, 1)) * 0.25, 1)
        let progress = min(Double(abs(dailyDelta)) / progressLimit, 1)

        return CalorieBalanceInsight(
            dailyDelta: dailyDelta,
            weeklyWeightKilograms: weeklyWeightKilograms,
            progress: progress
        )
    }

    private func averageGoalCalories(in buckets: [NutritionStatisticsBucket]) -> Int? {
        let goals = buckets.compactMap { $0.goal?.calories }.filter { $0 > 0 }
        guard !goals.isEmpty else { return nil }
        return goals.reduce(0, +) / goals.count
    }

    private func trend(for metric: InsightMetricKind, statistics: NutritionStatisticsSnapshot) -> InsightTrend? {
        guard let previousStatistics else { return nil }
        let current = metric.value(from: statistics.summary.averagePerDay)
        let previous = metric.value(from: previousStatistics.summary.averagePerDay)
        guard previous > 0 else { return nil }
        let delta = current - previous
        guard delta != 0 else { return InsightTrend(direction: .flat, percent: 0) }
        let percent = Int((Double(abs(delta)) / Double(previous) * 100).rounded())
        return InsightTrend(direction: delta > 0 ? .up : .down, percent: percent)
    }

    private func shiftWeek(_ weeks: Int) {
        guard let nextAnchor = Calendar.current.date(byAdding: .day, value: weeks * 7, to: anchorDay) else {
            return
        }
        weekTransitionDirection = weeks >= 0 ? 1 : -1
        withAnimation(.snappy(duration: 0.28)) {
            anchorDay = Calendar.current.startOfDay(for: nextAnchor)
        }
    }

}

private enum StatisticsGridMetrics {
    static let spacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 20

    static func tileSide(for availableWidth: CGFloat) -> CGFloat {
        max(1, floor((max(0, availableWidth) - spacing) / 2))
    }
}

private enum StatisticsDetailRoute: Hashable {
    case streak
    case calorieBalance
    case macros
    case metric(InsightMetricKind)

    var title: String {
        switch self {
        case .streak:
            return NSLocalizedString("today.stats.streak.title", comment: "Streak title")
        case .calorieBalance:
            return NSLocalizedString("today.stats.calorie_balance.title", comment: "Calorie balance title")
        case .macros:
            return NSLocalizedString("today.macro_chart.title", comment: "Macros chart title")
        case .metric(let metric):
            return metric.title
        }
    }
}

private struct NutritionStatisticDetailView: View {
    @EnvironmentObject private var diaryService: FoodDiaryService

    let route: StatisticsDetailRoute

    @State private var anchorDay: Date
    @State private var statistics: NutritionStatisticsSnapshot?
    @State private var previousStatistics: NutritionStatisticsSnapshot?
    @State private var isLoading = false
    @State private var weekTransitionDirection = 1
    @State private var streakDays = 0

    init(route: StatisticsDetailRoute, initialDay: Date) {
        self.route = route
        self._anchorDay = State(initialValue: Calendar.current.startOfDay(for: initialDay))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                StatisticsWeekSwitcher(
                    anchorDay: anchorDay,
                    transitionDirection: weekTransitionDirection,
                    canMoveForward: !statisticsIsCurrentWeek(anchorDay),
                    onPrevious: { shiftWeek(-1) },
                    onNext: { shiftWeek(1) }
                )
                .padding(.top, 12)

                detailWeekContent
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: anchorDay) {
            applyCachedStatistics()
            await reloadStatistics()
        }
        .task {
            if route == .streak {
                streakDays = await diaryService.loggingStreakDays()
            }
        }
        .refreshable {
            await reloadStatistics()
        }
    }

    @ViewBuilder
    private var detailWeekContent: some View {
        if let statistics {
            VStack(alignment: .leading, spacing: 12) {
                detailSummary(for: statistics)
                detailChart(for: statistics)
            }
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
        } else {
            NutritionStatisticsEmptyStateCard()
        }
    }

    @ViewBuilder
    private func detailSummary(for statistics: NutritionStatisticsSnapshot) -> some View {
        switch route {
        case .streak:
            let days = streakDays
            StatisticDetailHeroCard(
                iconName: "trophy.fill",
                tint: WeeklyMacroBarColors.protein,
                title: route.title,
                value: String(format: NSLocalizedString("today.stats.streak.value", comment: "Streak days value"), days),
                subtitle: days > 0
                    ? NSLocalizedString("today.stats.streak.message", comment: "Streak positive message")
                    : NSLocalizedString("today.stats.streak.empty", comment: "Streak empty message"),
                trend: nil
            )
        case .calorieBalance:
            let insight = calorieBalanceInsight(for: statistics)
            StatisticDetailHeroCard(
                iconName: "scale.3d",
                tint: insight.isSurplus ? Color(red: 0.94, green: 0.42, blue: 0.48) : WeeklyMacroBarColors.protein,
                title: route.title,
                value: String(format: NSLocalizedString("today.stats.calorie_balance.kg_per_week", comment: "Weight change per week"), insight.weeklyWeightKilograms),
                subtitle: String(format: NSLocalizedString("today.kcal_value", comment: "Calories value"), abs(insight.dailyDelta)),
                trend: nil
            )
        case .macros:
            StatisticDetailHeroCard(
                iconName: "chart.bar.fill",
                tint: Color.appAccent,
                title: route.title,
                value: String(format: NSLocalizedString("today.kcal_value", comment: "Calories value"), statistics.summary.averagePerDay.calories),
                subtitle: NSLocalizedString("today.stats.metric.daily_average", comment: "Daily average"),
                trend: trend(for: .calories, statistics: statistics)
            )
        case .metric(let metric):
            StatisticDetailHeroCard(
                iconName: metric.systemImage,
                tint: metric.tint,
                title: metric.title,
                value: "\(metric.value(from: statistics.summary.averagePerDay)) \(metric.unit)",
                subtitle: NSLocalizedString("today.stats.metric.daily_average", comment: "Daily average"),
                trend: trend(for: metric, statistics: statistics)
            )
        }
    }

    @ViewBuilder
    private func detailChart(for statistics: NutritionStatisticsSnapshot) -> some View {
        switch route {
        case .macros:
            WeeklyMacroCaloriesCard(
                entries: weeklyMacroEntries(for: statistics),
                selectedDay: anchorDay,
                averageSummary: statistics.summary.averagePerDay,
                showsSelection: true
            )
        case .streak:
            WeeklyLoggingDetailCard(buckets: statistics.buckets)
        case .calorieBalance:
            StatisticDetailBarCard(
                title: NSLocalizedString("settings.widget.metric.calories", comment: "Calories metric title"),
                metric: .calories,
                buckets: statistics.buckets
            )
        case .metric(let metric):
            StatisticDetailBarCard(
                title: metric.title,
                metric: metric,
                buckets: statistics.buckets
            )
        }
    }

    private func reloadStatistics() async {
        isLoading = statistics == nil
        defer { isLoading = false }

        let currentSnapshot = await diaryService.loadNutritionStatistics(period: .week, anchor: anchorDay)
        guard let currentSnapshot else { return }

        let previousAnchor = Calendar.current.date(byAdding: .day, value: -7, to: currentSnapshot.selectedAt)
            ?? currentSnapshot.selectedAt
        async let previousSnapshot = diaryService.loadNutritionStatistics(period: .week, anchor: previousAnchor)
        let resolvedPrevious = await previousSnapshot

        withAnimation(.easeInOut(duration: 0.25)) {
            statistics = currentSnapshot
            previousStatistics = resolvedPrevious
        }
    }

    private func applyCachedStatistics() {
        guard let cachedStatistics = diaryService.cachedNutritionStatistics(period: .week, anchor: anchorDay) else {
            statistics = nil
            previousStatistics = nil
            return
        }

        let previousAnchor = Calendar.current.date(byAdding: .day, value: -7, to: cachedStatistics.selectedAt)
            ?? cachedStatistics.selectedAt
        statistics = cachedStatistics
        previousStatistics = diaryService.cachedNutritionStatistics(period: .week, anchor: previousAnchor)
    }

    private func shiftWeek(_ weeks: Int) {
        guard let nextAnchor = Calendar.current.date(byAdding: .day, value: weeks * 7, to: anchorDay) else {
            return
        }
        weekTransitionDirection = weeks >= 0 ? 1 : -1
        withAnimation(.snappy(duration: 0.28)) {
            anchorDay = Calendar.current.startOfDay(for: nextAnchor)
        }
    }

    private func trend(for metric: InsightMetricKind, statistics: NutritionStatisticsSnapshot) -> InsightTrend? {
        guard let previousStatistics else { return nil }
        let current = metric.value(from: statistics.summary.averagePerDay)
        let previous = metric.value(from: previousStatistics.summary.averagePerDay)
        guard previous > 0 else { return nil }
        let delta = current - previous
        guard delta != 0 else { return InsightTrend(direction: .flat, percent: 0) }
        let percent = Int((Double(abs(delta)) / Double(previous) * 100).rounded())
        return InsightTrend(direction: delta > 0 ? .up : .down, percent: percent)
    }
}

private struct StatisticsWeekSwitcher: View {
    let anchorDay: Date
    let transitionDirection: Int
    let canMoveForward: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var weekID: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: anchorDay)?.start ?? anchorDay
    }

    private var weekTitleTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: transitionDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: transitionDirection >= 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Color.appCardBackground, in: Circle())
            }
            .buttonStyle(.plain)

            ZStack {
                weekTitlePill
                    .id(weekID)
                    .transition(weekTitleTransition)
            }
            .frame(maxWidth: .infinity)
            .clipped()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Color.appCardBackground.opacity(canMoveForward ? 1 : 0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canMoveForward)
            .opacity(canMoveForward ? 1 : 0.45)
        }
    }

    private var weekTitlePill: some View {
        Text(statisticsWeekTitle(for: anchorDay))
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(Color.appCardBackground, in: Capsule())
    }
}

private struct StatisticDetailHeroCard: View {
    let iconName: String
    let tint: Color
    let title: String
    let value: String
    let subtitle: String
    let trend: InsightTrend?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.appAccentReadableText)
                    .frame(width: 34, height: 34)
                    .background(tint, in: Circle())

                Text(title)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 7) {
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    if let trend {
                        TrendBadge(trend: trend)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}

private struct TrendBadge: View {
    let trend: InsightTrend

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: trend.direction.systemImage)
                .font(.caption2.weight(.bold))
            Text("\(trend.percent)%")
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

private struct StatisticDetailBarCard: View {
    let title: String
    let metric: InsightMetricKind
    let buckets: [NutritionStatisticsBucket]

    @State private var selectedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline.weight(.bold))
                .lineLimit(1)

            MiniMetricBarChart(metric: metric, buckets: buckets, selectedIndex: $selectedIndex)
                .frame(height: 210)
        }
        .padding(20)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .onChange(of: buckets.map(\.startAt)) { _, _ in
            selectedIndex = nil
        }
    }
}

private struct StatisticDetailChartCalloutContent: View {
    let date: Date
    let value: Int
    let unit: String
    let tint: Color

    private var dateText: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 4) {
                Text(dateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct WeeklyLoggingDetailCard: View {
    let buckets: [NutritionStatisticsBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("today.stats.streak.title")
                .font(.headline.weight(.bold))

            HStack(spacing: 8) {
                ForEach(sortedBuckets) { bucket in
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(bucket.hasEntries ? WeeklyMacroBarColors.protein : Color.primary.opacity(0.08))
                                .frame(width: 32, height: 32)

                            Image(systemName: bucket.hasEntries ? "checkmark" : "minus")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(bucket.hasEntries ? .white : .secondary)
                        }

                        Text(weekdayTitle(for: bucket.startAt))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private var sortedBuckets: [NutritionStatisticsBucket] {
        buckets.sorted { $0.startAt < $1.startAt }
    }

    private func weekdayTitle(for date: Date) -> String {
        let symbols = DateFormatter().shortStandaloneWeekdaySymbols ?? []
        let index = Calendar.current.component(.weekday, from: date) - 1
        guard symbols.indices.contains(index) else { return "" }
        return String(symbols[index].prefix(1)).uppercased()
    }
}

private func statisticsIsCurrentWeek(_ date: Date) -> Bool {
    let calendar = Calendar.current
    guard
        let selectedWeek = calendar.dateInterval(of: .weekOfYear, for: date),
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now)
    else {
        return false
    }
    return calendar.isDate(selectedWeek.start, inSameDayAs: currentWeek.start)
}

private func statisticsWeekTitle(for date: Date) -> String {
    let calendar = Calendar.current
    guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
    if statisticsIsCurrentWeek(date) {
        return localizedStatisticsText("today.stats.week.current", fallback: "This week")
    }

    let formatter = DateIntervalFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: interval.start, to: end)
        .replacingOccurrences(of: "–", with: "-")
        .replacingOccurrences(of: "—", with: "-")
}

private func localizedStatisticsText(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
}

private func weeklyMacroEntries(for statistics: NutritionStatisticsSnapshot) -> [WeeklyMacroCaloriesEntry] {
    let calendar = Calendar.current
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: statistics.selectedAt)?.start
        ?? calendar.startOfDay(for: statistics.periodStart)
    var bucketsByDay: [Date: NutritionStatisticsBucket] = [:]
    for bucket in statistics.buckets {
        bucketsByDay[calendar.startOfDay(for: bucket.startAt)] = bucket
    }

    return (0..<7).compactMap { offset in
        guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
            return nil
        }
        let normalizedDay = calendar.startOfDay(for: day)
        return WeeklyMacroCaloriesEntry(
            date: normalizedDay,
            summary: bucketsByDay[normalizedDay]?.total ?? .zero
        )
    }
}

private func completedLoggedDayStreak(
    currentBuckets: [NutritionStatisticsBucket],
    previousBuckets: [NutritionStatisticsBucket]
) -> Int {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    var bucketsByDay: [Date: NutritionStatisticsBucket] = [:]
    for bucket in previousBuckets + currentBuckets {
        bucketsByDay[calendar.startOfDay(for: bucket.startAt)] = bucket
    }

    var day = calendar.date(byAdding: .day, value: -1, to: today) ?? today
    var streak = 0
    while let bucket = bucketsByDay[day], bucket.hasEntries {
        streak += 1
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
        day = previousDay
    }
    return streak
}

private func calorieBalanceInsight(for statistics: NutritionStatisticsSnapshot) -> CalorieBalanceInsight {
    let averageCalories = statistics.summary.averagePerDay.calories
    let averageGoal = averageGoalCalories(in: statistics.buckets)
    let dailyDelta = averageCalories - (averageGoal ?? averageCalories)
    let weeklyWeightKilograms = Double(abs(dailyDelta)) * 7.0 / 7700.0
    let progressLimit = max(Double(averageGoal ?? max(averageCalories, 1)) * 0.25, 1)
    let progress = min(Double(abs(dailyDelta)) / progressLimit, 1)

    return CalorieBalanceInsight(
        dailyDelta: dailyDelta,
        weeklyWeightKilograms: weeklyWeightKilograms,
        progress: progress
    )
}

private func averageGoalCalories(in buckets: [NutritionStatisticsBucket]) -> Int? {
    let goals = buckets.compactMap { $0.goal?.calories }.filter { $0 > 0 }
    guard !goals.isEmpty else { return nil }
    return goals.reduce(0, +) / goals.count
}

private enum InsightMetricKind: String, CaseIterable, Hashable, Identifiable {
    case calories
    case carbs
    case fat
    case protein

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calories:
            return NSLocalizedString("settings.widget.metric.calories", comment: "Calories metric title")
        case .carbs:
            return NSLocalizedString("diary.carbs", comment: "Carbs")
        case .fat:
            return NSLocalizedString("diary.fat", comment: "Fat")
        case .protein:
            return NSLocalizedString("diary.protein", comment: "Protein")
        }
    }

    var systemImage: String {
        switch self {
        case .calories:
            return "flame.fill"
        case .carbs:
            return "c.circle.fill"
        case .fat:
            return "f.circle.fill"
        case .protein:
            return "p.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .calories:
            return .appAccent
        case .carbs:
            return WeeklyMacroBarColors.carbs
        case .fat:
            return WeeklyMacroBarColors.fat
        case .protein:
            return WeeklyMacroBarColors.protein
        }
    }

    var unit: String {
        switch self {
        case .calories:
            return NSLocalizedString("diary.kcal", comment: "Calories suffix")
        case .carbs, .fat, .protein:
            return NSLocalizedString("unit.grams.short", comment: "Grams unit short title")
        }
    }

    func value(from summary: NutritionSummary) -> Int {
        switch self {
        case .calories:
            return summary.calories
        case .carbs:
            return summary.carbs
        case .fat:
            return summary.fat
        case .protein:
            return summary.protein
        }
    }

    func value(from bucket: NutritionStatisticsBucket) -> Int {
        value(from: bucket.total)
    }
}

private struct InsightTrend {
    let direction: InsightTrendDirection
    let percent: Int
}

private enum InsightTrendDirection {
    case up
    case down
    case flat

    var systemImage: String {
        switch self {
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .flat:
            return "minus"
        }
    }
}

private struct CalorieBalanceInsight {
    let dailyDelta: Int
    let weeklyWeightKilograms: Double
    let progress: Double

    var isDeficit: Bool { dailyDelta < 0 }
    var isSurplus: Bool { dailyDelta > 0 }
}

private struct StreakInsightCard: View {
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("today.stats.streak.title", systemImage: "trophy.fill")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()
            }

            Spacer(minLength: 0)

            Text(String(format: NSLocalizedString("today.stats.streak.value", comment: "Streak days value"), days))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(messageKey)
                .font(.caption2.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.appAccentReadableText)
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WeeklyMacroBarColors.protein, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private var messageKey: LocalizedStringKey {
        days > 0 ? "today.stats.streak.message" : "today.stats.streak.empty"
    }
}

private struct CalorieBalanceInsightCard: View {
    let insight: CalorieBalanceInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("today.stats.calorie_balance.title")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(balanceEstimateTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(String(format: NSLocalizedString("today.stats.calorie_balance.kg_per_week", comment: "Weight change per week"), insight.weeklyWeightKilograms))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(balanceTint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(dailyDeltaTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(String(format: NSLocalizedString("today.kcal_value", comment: "Calories value"), abs(insight.dailyDelta)))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(balanceTint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            BalanceProgressBar(progress: insight.progress, tint: balanceTint)
                .frame(height: 9)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private var balanceEstimateTitle: LocalizedStringKey {
        if insight.isDeficit {
            return "today.stats.calorie_balance.loss"
        }
        if insight.isSurplus {
            return "today.stats.calorie_balance.gain"
        }
        return "today.stats.calorie_balance.stable"
    }

    private var dailyDeltaTitle: LocalizedStringKey {
        if insight.isDeficit {
            return "today.stats.calorie_balance.daily_deficit"
        }
        if insight.isSurplus {
            return "today.stats.calorie_balance.daily_surplus"
        }
        return "today.stats.calorie_balance.daily_balance"
    }

    private var balanceTint: Color {
        insight.isSurplus ? Color(red: 0.94, green: 0.42, blue: 0.48) : WeeklyMacroBarColors.protein
    }
}

private struct BalanceProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                Capsule()
                    .fill(tint)
                    .frame(width: max(geometry.size.width * CGFloat(progress), 12))
            }
        }
    }
}

private struct InsightMetricCard: View {
    let metric: InsightMetricKind
    let averageValue: Int
    let trend: InsightTrend?
    let buckets: [NutritionStatisticsBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(metric.tint)

                Text(metric.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("today.stats.metric.daily_average")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(averageValue)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(metric.unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let trend {
                        HStack(spacing: 2) {
                            Image(systemName: trend.direction.systemImage)
                                .font(.caption2.weight(.bold))
                            Text("\(trend.percent)%")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 6)

            MiniMetricBarChart(metric: metric, buckets: buckets)
                .frame(height: 54)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}

private struct MiniMetricBarChart: View {
    let metric: InsightMetricKind
    let buckets: [NutritionStatisticsBucket]
    @Binding private var selectedIndex: Int?
    private let isInteractive: Bool
    private let showsValueGrid: Bool

    /// Drives the same grow-in transition as the weekly macros chart so paging
    /// between metrics / weeks animates smoothly instead of snapping.
    @State private var displayedScale: CGFloat = 0

    init(metric: InsightMetricKind, buckets: [NutritionStatisticsBucket]) {
        self.metric = metric
        self.buckets = buckets
        self._selectedIndex = .constant(nil)
        self.isInteractive = false
        self.showsValueGrid = false
    }

    init(metric: InsightMetricKind, buckets: [NutritionStatisticsBucket], selectedIndex: Binding<Int?>) {
        self.metric = metric
        self.buckets = buckets
        self._selectedIndex = selectedIndex
        self.isInteractive = true
        self.showsValueGrid = true
    }

    private var values: [(date: Date, value: Int)] {
        buckets
            .sorted { $0.startAt < $1.startAt }
            .map { (date: $0.startAt, value: max(metric.value(from: $0), 0)) }
    }

    private var maxValue: Int {
        max(values.map(\.value).max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let labelHeight: CGFloat = 16
            let axisWidth: CGFloat = showsValueGrid ? (geometry.size.height > 90 ? 42 : 28) : 0
            let chartHeight = max(0, geometry.size.height - labelHeight)
            let spacing: CGFloat = 7
            let plotWidth = max(0, geometry.size.width - axisWidth)

            ZStack(alignment: .topLeading) {
                if showsValueGrid {
                    MetricBarValueGrid(maxValue: maxValue, chartHeight: chartHeight, axisWidth: axisWidth)
                }

                VStack(spacing: 5) {
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(values.indices, id: \.self) { index in
                            let item = values[index]
                            let isSelected = selectedIndex == index
                            let targetHeight = item.value > 0
                                ? max(8, chartHeight * CGFloat(item.value) / CGFloat(maxValue))
                                : 4

                            metricBar(
                                item: item,
                                index: index,
                                barHeight: targetHeight * displayedScale,
                                chartHeight: chartHeight,
                                isSelected: isSelected
                            )
                        }
                    }
                    .frame(height: chartHeight)

                    // Weekday labels live in their own fixed-height axis row so
                    // they always sit at the same height regardless of bar size.
                    HStack(spacing: spacing) {
                        ForEach(values.indices, id: \.self) { index in
                            let isSelected = selectedIndex == index
                            Text(weekdayTitle(for: values[index].date))
                                .font(.caption2.weight(isSelected ? .bold : .semibold))
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 11)
                }
                .padding(.trailing, axisWidth)

                if isInteractive,
                   let selectedIndex,
                   values.indices.contains(selectedIndex) {
                    let item = values[selectedIndex]
                    let anchorX = barAnchorX(index: selectedIndex, count: values.count, plotWidth: plotWidth, spacing: spacing)
                    let calloutWidth = min(170, max(132, geometry.size.width * 0.54))
                    let calloutX = min(max(anchorX, calloutWidth / 2), max(calloutWidth / 2, plotWidth - calloutWidth / 2))

                    Rectangle()
                        .fill(metric.tint.opacity(0.26))
                        .frame(width: 1, height: chartHeight)
                        .offset(x: anchorX, y: 0)

                    ChartSelectionCallout {
                        StatisticDetailChartCalloutContent(
                            date: item.date,
                            value: item.value,
                            unit: metric.unit,
                            tint: metric.tint
                        )
                    }
                    .frame(width: calloutWidth)
                    .position(x: calloutX, y: 28)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(2)
                }
            }
        }
        .onAppear {
            guard displayedScale == 0 else { return }
            withAnimation(.easeOut(duration: 0.65)) {
                displayedScale = 1
            }
        }
        .onChange(of: values.map(\.date)) { _, _ in
            displayedScale = 0
            withAnimation(.easeOut(duration: 0.65)) {
                displayedScale = 1
            }
        }
    }

    @ViewBuilder
    private func metricBar(
        item: (date: Date, value: Int),
        index: Int,
        barHeight: CGFloat,
        chartHeight: CGFloat,
        isSelected: Bool
    ) -> some View {
        let content = ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.clear)
            Rectangle()
                .fill(item.value > 0 ? metric.tint : Color.secondary.opacity(0.18))
                .frame(height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .frame(height: chartHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isSelected ? metric.tint : Color.clear)
                .frame(height: 2)
                .offset(y: 4)
        }

        if isInteractive {
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedIndex = selectedIndex == index ? nil : index
                    }
                }
        } else {
            content
        }
    }

    private func barAnchorX(index: Int, count: Int, plotWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let totalSpacing = spacing * CGFloat(max(count - 1, 0))
        let barWidth = max((plotWidth - totalSpacing) / CGFloat(count), 0)
        return CGFloat(index) * (barWidth + spacing) + barWidth / 2
    }

    private func weekdayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        let symbols = DateFormatter().shortStandaloneWeekdaySymbols ?? []
        let index = calendar.component(.weekday, from: date) - 1
        guard symbols.indices.contains(index) else { return "" }
        return String(symbols[index].prefix(1)).uppercased()
    }
}

private struct MetricBarValueGrid: View {
    let maxValue: Int
    let chartHeight: CGFloat
    let axisWidth: CGFloat

    private let fractions: [CGFloat] = [1, 0.5, 0]

    var body: some View {
        GeometryReader { geometry in
            let lineWidth = max(0, geometry.size.width - axisWidth)

            ZStack(alignment: .topLeading) {
                ForEach(fractions, id: \.self) { fraction in
                    let y = chartHeight * (1 - fraction)
                    let labelY = min(max(y, 6), max(chartHeight - 6, 6))
                    let value = Int((CGFloat(maxValue) * fraction).rounded())

                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: lineWidth, height: 1)
                        .offset(y: y)

                    Text(axisLabel(for: value))
                        .font(.system(size: axisWidth > 30 ? 9 : 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(axisWidth > 30 ? 0.72 : 0.62))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(width: axisWidth, alignment: .trailing)
                        .offset(x: lineWidth, y: labelY - 5)
                }
            }
        }
        .frame(height: chartHeight)
    }

    private func axisLabel(for value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

struct NutritionStatisticsEmptyStateCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.secondary)
            Text("today.stats.empty.title")
                .font(.headline)
            Text("today.stats.empty.message")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, 24)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}
