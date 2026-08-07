import SwiftUI

enum HabitAutomaticTracker: CaseIterable {
    case water
    case sugar
    case regularity
    case lateMeals
    case nutritionGoal

    init?(habit: Habit) {
        let normalizedName = Self.normalized(habit.name)
        let normalizedDescription = Self.normalized(habit.description)
        let normalizedUnitLabel = Self.normalized(habit.unitLabel)
        let regularityUnitLabel = Self.normalized(
            NSLocalizedString(
                "habits.template.regularity.unit",
                tableName: nil,
                bundle: .main,
                value: "meals",
                comment: "Unit label for regular meal logging habit"
            )
        )

        for tracker in Self.allCases {
            let localizedName = Self.normalized(
                NSLocalizedString(
                    tracker.nameKey,
                    tableName: nil,
                    bundle: .main,
                    value: tracker.fallbackName,
                    comment: "Built-in habit name"
                )
            )
            let localizedDescription = Self.normalized(
                NSLocalizedString(
                    tracker.descriptionKey,
                    tableName: nil,
                    bundle: .main,
                    value: tracker.fallbackDescription,
                    comment: "Built-in habit description"
                )
            )
            let fallbackName = Self.normalized(tracker.fallbackName)
            let fallbackDescription = Self.normalized(tracker.fallbackDescription)

            let matchesName = !localizedName.isEmpty && normalizedName == localizedName
            let matchesDescription = !localizedDescription.isEmpty && normalizedDescription == localizedDescription
            let matchesFallbackName = !fallbackName.isEmpty && normalizedName == fallbackName
            let matchesFallbackDescription = !fallbackDescription.isEmpty && normalizedDescription == fallbackDescription

            if habit.kind == tracker.kind && (matchesName || matchesDescription || matchesFallbackName || matchesFallbackDescription) {
                self = tracker
                return
            }

            // Keep built-in regularity detection stable if user renamed the habit.
            if tracker == .regularity,
               habit.kind == .build,
               habit.dailyTarget > 0,
               !normalizedUnitLabel.isEmpty,
               normalizedUnitLabel == regularityUnitLabel {
                self = tracker
                return
            }

            // Fallback signature for previously customized/renamed built-in habits.
            if habit.kind == tracker.kind && habit.icon == tracker.defaultIcon {
                if tracker == .regularity && habit.dailyTarget <= 0 {
                    continue
                }
                if tracker == .water && habit.dailyTarget > 0 {
                    continue
                }
                self = tracker
                return
            }
        }

        return nil
    }

    var kind: HabitKind {
        switch self {
        case .water, .regularity, .nutritionGoal:
            return .build
        case .sugar, .lateMeals:
            return .quit
        }
    }

    var nameKey: String {
        switch self {
        case .water:
            return "habits.idea.water"
        case .sugar:
            return "habits.idea.sugar"
        case .regularity:
            return "habits.idea.regularity"
        case .lateMeals:
            return "habits.idea.lateMeals"
        case .nutritionGoal:
            return "habits.idea.nutritionGoal"
        }
    }

    var descriptionKey: String {
        switch self {
        case .water:
            return "habits.template.water.desc"
        case .sugar:
            return "habits.template.sugar.desc"
        case .regularity:
            return "habits.template.regularity.desc"
        case .lateMeals:
            return "habits.template.lateMeals.desc"
        case .nutritionGoal:
            return "habits.template.nutritionGoal.desc"
        }
    }

    var fallbackName: String {
        switch self {
        case .water:
            return "Drink enough water"
        case .sugar:
            return "Reduce sugar"
        case .regularity:
            return "Eat regularly"
        case .lateMeals:
            return "Avoid late meals"
        case .nutritionGoal:
            return "Stay within nutrition goals"
        }
    }

    var fallbackDescription: String {
        switch self {
        case .water:
            return "Track whether you hit your daily water goal."
        case .sugar:
            return "Track how much sugar you consumed during the day."
        case .regularity:
            return "Track whether you logged your meals regularly."
        case .lateMeals:
            return "Track days without meals after 20:00."
        case .nutritionGoal:
            return "Track days when calories, protein, fat, and carbs stay within 10% of target."
        }
    }

    var defaultIcon: String {
        switch self {
        case .water:
            return "drop.fill"
        case .sugar:
            return "nosign"
        case .regularity:
            return "fork.knife"
        case .lateMeals:
            return "moon.zzz.fill"
        case .nutritionGoal:
            return "target"
        }
    }

    var templateID: String {
        switch self {
        case .water:
            return "water"
        case .sugar:
            return "sugar"
        case .regularity:
            return "regularity"
        case .lateMeals:
            return "lateMeals"
        case .nutritionGoal:
            return "nutritionGoal"
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

enum HabitProgressClock {
    static let daySeconds: TimeInterval = 86_400
    static let manualCheckGraceSeconds: TimeInterval = (23 * 3_600) + (59 * 60) + 59

    static func completedDays(for attempt: HabitAttempt?, at referenceDate: Date = Date()) -> Int {
        guard let attempt else { return 0 }
        let end = attempt.endedAt ?? referenceDate
        guard end > attempt.startedAt else { return 0 }
        return max(0, Int(end.timeIntervalSince(attempt.startedAt) / daySeconds))
    }

    static func elapsedText(since startDate: Date?, to referenceDate: Date = Date()) -> String {
        guard let startDate else { return "--:--:--" }
        let elapsed = max(0, Int(referenceDate.timeIntervalSince(startDate)))
        let days = elapsed / 86_400
        let hours = (elapsed % 86_400) / 3_600
        let minutes = (elapsed % 3_600) / 60
        let seconds = elapsed % 60
        if days > 0 {
            return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, seconds)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func currentCompletedIntervalDate(for attempt: HabitAttempt?, at referenceDate: Date = Date()) -> Date? {
        guard let attempt else { return nil }
        let completed = completedDays(for: attempt, at: referenceDate)
        guard completed > 0 else { return nil }
        return attempt.startedAt.addingTimeInterval(TimeInterval(completed) * daySeconds)
    }

    static func manualCheckDay(for attempt: HabitAttempt, completedDayIndex: Int, calendar: Calendar = .current) -> Date {
        let startDay = calendar.startOfDay(for: attempt.startedAt)
        return calendar.date(byAdding: .day, value: completedDayIndex, to: startDay) ?? startDay
    }

    static func manualCheckDeadline(for attempt: HabitAttempt, completedDayIndex: Int) -> Date {
        attempt.startedAt
            .addingTimeInterval(TimeInterval(completedDayIndex + 1) * daySeconds)
            .addingTimeInterval(manualCheckGraceSeconds)
    }
}

@MainActor
enum HabitStreakResolver {
    static func currentStreak(
        for habit: Habit,
        habitsService: HabitsService,
        diaryService: FoodDiaryService,
        on referenceDate: Date = Date()
    ) -> Int {
        if habit.trackingMode == .automatic, let tracker = HabitAutomaticTracker(habit: habit) {
            return automaticCurrentStreak(for: habit, tracker: tracker, diaryService: diaryService, on: referenceDate)
        }

        if habit.trackingMode == .manual {
            return manualCurrentStreak(for: habit, habitsService: habitsService)
        }

        if habit.kind == .quit {
            return quitCurrentStreak(for: habit, on: referenceDate)
        }

        return habitsService.currentStreak(habit: habit, on: referenceDate)
    }

    static func failureDateRequiringReset(
        for habit: Habit,
        diaryService: FoodDiaryService,
        on referenceDate: Date = Date()
    ) -> Date? {
        guard habit.trackingMode == .automatic,
              let tracker = HabitAutomaticTracker(habit: habit),
              let attempt = habit.currentAttempt else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let anchorDay = lastCompletedHabitDay(for: referenceDate, calendar: calendar)
        let trackingStart = calendar.startOfDay(for: attempt.startedAt)
        guard trackingStart <= anchorDay else { return nil }

        for day in daysInRange(from: trackingStart, through: anchorDay) {
            if automaticDayKind(for: day, habit: habit, tracker: tracker, diaryService: diaryService, today: today) == .failure {
                return day
            }
        }

        return nil
    }

    static func manualFailureDateRequiringReset(
        for habit: Habit,
        habitsService: HabitsService,
        on referenceDate: Date = Date()
    ) -> Date? {
        guard habit.trackingMode == .manual,
              let attempt = habit.currentAttempt else { return nil }

        let calendar = Calendar.current
        let completedDays = HabitProgressClock.completedDays(for: attempt, at: referenceDate)
        guard completedDays > 0 else { return nil }
        let checkedDays = Set(habitsService.checkIns(forAttempt: attempt.id).map { calendar.startOfDay(for: $0.day) })

        for index in 0..<completedDays {
            let deadline = HabitProgressClock.manualCheckDeadline(for: attempt, completedDayIndex: index)
            guard referenceDate > deadline else { break }

            let day = HabitProgressClock.manualCheckDay(for: attempt, completedDayIndex: index, calendar: calendar)
            if !checkedDays.contains(calendar.startOfDay(for: day)) {
                return day
            }
        }

        return nil
    }

    static func regularityProgress(for day: Date, diaryService: FoodDiaryService) -> (loggedSlots: Int, requiredSlots: Int, isComplete: Bool) {
        let requiredSlotIDs = diaryService.mealCategories
            .filter(\.isEnabled)
            .map(\.id)
        let requiredSlots = Set(requiredSlotIDs)
        guard !requiredSlots.isEmpty else { return (0, 0, false) }

        let loggedSlots = Set(diaryService.meals(on: day).map(\.mealCategoryID))
        let filledSlots = requiredSlots.intersection(loggedSlots).count
        return (filledSlots, requiredSlots.count, requiredSlots.isSubset(of: loggedSlots))
    }

    private static func quitCurrentStreak(for habit: Habit, on referenceDate: Date) -> Int {
        HabitProgressClock.completedDays(for: habit.currentAttempt, at: referenceDate)
    }

    private static func manualCurrentStreak(for habit: Habit, habitsService: HabitsService) -> Int {
        guard let attempt = habit.currentAttempt else { return 0 }
        let calendar = Calendar.current
        return Set(habitsService.checkIns(forAttempt: attempt.id).map { calendar.startOfDay(for: $0.day) }).count
    }

    private static func automaticCurrentStreak(
        for habit: Habit,
        tracker: HabitAutomaticTracker,
        diaryService: FoodDiaryService,
        on referenceDate: Date
    ) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let anchorDay = lastCompletedHabitDay(for: referenceDate, calendar: calendar)
        let trackingStart = automaticTrackingStart(for: habit, today: today)

        guard trackingStart <= anchorDay else { return 0 }

        var currentRun = 0
        var cursor = anchorDay
        while cursor >= trackingStart {
            switch automaticDayKind(for: cursor, habit: habit, tracker: tracker, diaryService: diaryService, today: today) {
            case .success:
                currentRun += 1
            case .failure:
                return currentRun
            case .neutral:
                return currentRun
            }

            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return currentRun
    }

    private static func lastCompletedHabitDay(for referenceDate: Date, calendar: Calendar) -> Date {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        if calendar.isDateInToday(referenceDay) {
            return calendar.date(byAdding: .day, value: -1, to: referenceDay) ?? referenceDay
        }

        return referenceDay
    }

    private static func automaticTrackingStart(for habit: Habit, today: Date) -> Date {
        let calendar = Calendar.current
        let recentWindowStart = calendar.date(byAdding: .day, value: -120, to: today) ?? today
        let attemptStart = habit.currentAttempt.map { calendar.startOfDay(for: $0.startedAt) } ?? recentWindowStart
        return max(attemptStart, recentWindowStart)
    }

    private static func automaticDayKind(
        for day: Date,
        habit: Habit,
        tracker: HabitAutomaticTracker,
        diaryService: FoodDiaryService,
        today: Date
    ) -> HabitAutomaticDayKind {
        let calendar = Calendar.current
        let resolvedDay = calendar.startOfDay(for: day)
        let isPastDay = resolvedDay < today
        let isToday = calendar.isDateInToday(resolvedDay)

        switch tracker {
        case .water:
            let goal = diaryService.dailyWaterGoalMilliliters
            guard goal > 0 else { return .neutral }
            return diaryService.waterIntake(for: resolvedDay) >= goal ? .success : (isPastDay ? .failure : .neutral)

        case .lateMeals:
            let meals = diaryService.meals(on: resolvedDay)
            guard let latestMeal = meals.max(by: { $0.scheduledAt < $1.scheduledAt }) else {
                return isPastDay ? .failure : .neutral
            }

            let cutoff = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: resolvedDay) ?? resolvedDay
            if latestMeal.scheduledAt >= cutoff {
                return .failure
            }

            return (isPastDay || (isToday && Date() >= cutoff)) ? .success : .neutral

        case .regularity:
            let progress = regularityProgress(for: resolvedDay, diaryService: diaryService)
            guard progress.requiredSlots > 0 else { return .neutral }
            if progress.isComplete {
                return .success
            }

            return isPastDay ? .failure : .neutral

        case .sugar:
            let meals = diaryService.meals(on: resolvedDay)
            let threshold = sugarDailyTargetGrams(for: habit)
            let estimatedSugar = estimatedSugar(for: meals)
            if estimatedSugar > threshold {
                return .failure
            }

            return isPastDay ? .success : .neutral

        case .nutritionGoal:
            return nutritionGoalDayKind(for: resolvedDay, diaryService: diaryService, isPastDay: isPastDay)
        }
    }

    private static func nutritionGoalDayKind(
        for day: Date,
        diaryService: FoodDiaryService,
        isPastDay: Bool
    ) -> HabitAutomaticDayKind {
        let summary = diaryService.nutritionSummary(on: day)
        let goal = diaryService.goal(for: day)
        let targetProtein = diaryService.goalProteinGrams(for: day)
        let targetFat = diaryService.goalFatGrams(for: day)
        let targetCarbs = diaryService.goalCarbsGrams(for: day)

        guard goal.calories > 0, targetProtein > 0, targetFat > 0, targetCarbs > 0 else {
            return .neutral
        }

        guard summary.calories > 0 || summary.protein > 0 || summary.fat > 0 || summary.carbs > 0 else {
            return isPastDay ? .failure : .neutral
        }

        let isComplete = isWithinTenPercent(summary.calories, of: goal.calories)
            && isWithinTenPercent(summary.protein, of: targetProtein)
            && isWithinTenPercent(summary.fat, of: targetFat)
            && isWithinTenPercent(summary.carbs, of: targetCarbs)

        if isComplete {
            return .success
        }

        return isPastDay ? .failure : .neutral
    }

    private static func isWithinTenPercent(_ value: Int, of target: Int) -> Bool {
        guard target > 0 else { return false }
        let ratio = Double(value) / Double(target)
        return ratio >= 0.9 && ratio <= 1.1
    }

    private static func estimatedSugar(for meals: [MealEntry]) -> Double {
        meals.reduce(0) { partial, meal in
            partial + meal.items.reduce(0) { itemTotal, item in
                itemTotal + estimatedSugar(for: item)
            }
        }
    }

    private static func sugarDailyTargetGrams(for habit: Habit) -> Double {
        Double(habit.dailyTarget > 0 ? habit.dailyTarget : HabitTemplate.adultSugarDailyTargetGrams)
    }

    private static func estimatedSugar(for item: MealItemEntry) -> Double {
        guard let product = item.linkedProductSummary else { return 0 }

        let sugarPer100g = product.sugarPer100g
        guard sugarPer100g > 0 else { return 0 }

        switch item.unit {
        case .serving:
            return sugarPer100g * max(item.amount, 1)
        case .grams, .milliliters:
            return sugarPer100g * item.amount / 100.0
        }
    }
}

private enum HabitAutomaticDayKind {
    case success
    case failure
    case neutral
}

private func daysInRange(from start: Date, through end: Date) -> [Date] {
    let calendar = Calendar.current
    let resolvedStart = calendar.startOfDay(for: start)
    let resolvedEnd = calendar.startOfDay(for: end)
    guard resolvedStart <= resolvedEnd else { return [] }

    var days: [Date] = []
    var current = resolvedStart
    while current <= resolvedEnd {
        days.append(current)
        guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
        current = next
    }
    return days
}

struct HabitMilestoneProgress: Equatable {
    let currentStreak: Int
    let previousThreshold: Int
    let nextThreshold: Int
    let fraction: Double

    private static let thresholds = [7, 30, 90, 180, 365]

    static func make(for streak: Int) -> HabitMilestoneProgress {
        make(for: Double(streak))
    }

    static func make(for progressDays: Double) -> HabitMilestoneProgress {
        let resolvedProgress = max(0, progressDays)
        let resolvedStreak = max(0, Int(floor(resolvedProgress)))

        var previousThreshold = 0
        for threshold in thresholds {
            if resolvedProgress <= Double(threshold) {
                let phaseLength = max(1, threshold - previousThreshold)
                let phaseProgress = (resolvedProgress - Double(previousThreshold)) / Double(phaseLength)
                return HabitMilestoneProgress(
                    currentStreak: resolvedStreak,
                    previousThreshold: previousThreshold,
                    nextThreshold: threshold,
                    fraction: min(max(phaseProgress, 0), 1)
                )
            }

            previousThreshold = threshold
        }

        let lastThreshold = thresholds.last ?? 365
        return HabitMilestoneProgress(
            currentStreak: resolvedStreak,
            previousThreshold: lastThreshold,
            nextThreshold: lastThreshold,
            fraction: 1
        )
    }
}

struct HabitMilestoneRing: View {
    let progress: HabitMilestoneProgress
    let tint: Color
    let icon: String
    var size: CGFloat = 52
    var lineWidth: CGFloat = 4
    var iconSize: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.12), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.35), value: progress.fraction)

            Circle()
                .fill(tint.opacity(0.12))
                .padding(lineWidth * 1.75)

            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}
