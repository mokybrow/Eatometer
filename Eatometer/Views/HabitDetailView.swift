import SwiftUI

struct HabitDetailView: View {
    let habit: Habit
    @EnvironmentObject private var habitsService: HabitsService
    @EnvironmentObject private var diaryService: FoodDiaryService
    @Environment(\.dismiss) private var dismiss

    @State private var showEditor = false
    @State private var showExtendDurationOptions = false
    @State private var manualCheckButtonPhase: ManualCheckButtonPhase = .idle

    private enum ManualCheckButtonPhase {
        case idle
        case submitting
        case success
    }

    private var refreshedHabit: Habit {
        habitsService.habits.first(where: { $0.id == habit.id }) ?? habit
    }

    var body: some View {
        let h = refreshedHabit
        let attempt = h.currentAttempt
        let attempts = habitsService.attempts(forHabit: h.id)
        let pastAttempts = attempts.filter { $0.id != attempt?.id }
        let currentStreak = HabitStreakResolver.currentStreak(
            for: h,
            habitsService: habitsService,
            diaryService: diaryService
        )

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let runtime = HabitRuntimeSnapshot(habit: h, now: timeline.date)
                        progressCard(for: h, runtime: runtime, currentStreak: currentStreak)
                    }

                    if !pastAttempts.isEmpty {
                        historyCard(habit: h, attempts: pastAttempts)
                    }
                }
                .eoCardInsets()
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .eoPageBackground()
            // Read-only viewer: editing lives in the list's context menu.
            .eoSheetChrome(title: Text(verbatim: h.name), onClose: { dismiss() })
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showEditor) {
            HabitEditorSheet(mode: .edit(h), clientSettings: h.clientSettings) { payload in
                let shouldSeedManualCheckIns = h.trackingMode == .automatic && payload.clientSettings.trackingMode == .manual
                let automaticDaysToSeed: [Date]
                if shouldSeedManualCheckIns {
                    await loadAutomaticHistoryIfNeeded(for: h)
                    automaticDaysToSeed = manualTransitionSeedDays(for: h)
                } else {
                    automaticDaysToSeed = []
                }

                let result = await habitsService.updateHabit(
                    id: h.id,
                    name: payload.name,
                    description: payload.description,
                    kind: payload.kind,
                    icon: payload.icon,
                    colorHex: payload.colorHex,
                    dailyTarget: payload.dailyTarget,
                    unitLabel: payload.unitLabel,
                    archived: payload.archived,
                    clientSettings: payload.clientSettings
                )
                if let updatedHabit = result, shouldSeedManualCheckIns {
                    await seedManualCheckIns(for: updatedHabit, days: automaticDaysToSeed)
                }
                return result != nil
            }
        }
        .confirmationDialog(
            localizedHabitString("habits.duration.extend.title", fallback: "Extend duration"),
            isPresented: $showExtendDurationOptions,
            titleVisibility: .visible
        ) {
            Button(localizedHabitString("habits.duration.extend.7", fallback: "+7 days")) {
                Task { await extendDuration(h, by: 7) }
            }
            Button(localizedHabitString("habits.duration.extend.14", fallback: "+14 days")) {
                Task { await extendDuration(h, by: 14) }
            }
            Button(localizedHabitString("habits.duration.extend.30", fallback: "+30 days")) {
                Task { await extendDuration(h, by: 30) }
            }
            Button("common.cancel", role: .cancel) {}
        }
        .task {
            await habitsService.loadAttemptsIfNeeded(habitID: h.id)
            if let attemptID = h.currentAttempt?.id {
                await habitsService.loadCheckInsIfNeeded(attemptID: attemptID)
            }
        }
    }

    /// Mock-up "Habit Page": one card with "Time Elapsed:", an optional
    /// "Time Remaining:" for countdown habits, and the manual check-in action.
    @ViewBuilder
    private func progressCard(for habit: Habit, runtime: HabitRuntimeSnapshot, currentStreak: Int) -> some View {
        EOCard {
            EOListRow(
                title: Text("habits.detail.time_elapsed"),
                accessory: .value(Text(verbatim: runtime.elapsedText))
            )

            if let remainingText = remainingText(for: habit, runtime: runtime) {
                EORowSeparator()
                EOListRow(
                    title: Text("habits.detail.time_remaining"),
                    accessory: .value(Text(verbatim: remainingText))
                )
            }

            if shouldShowManualCheckAction(for: habit) {
                EORowSeparator()
                manualCheckRow(for: habit, runtime: runtime)
            }
        }
    }

    /// "Time Remaining" has two meanings, matching the mock-ups:
    ///
    /// * **Manual habits** – time left in the current check-in window if it is
    ///   already open, otherwise the wait until the next one opens. This is the
    ///   short countdown shown next to "Let's continue".
    /// * **Countdown habits** – how much of the target duration is still ahead.
    private func remainingText(for habit: Habit, runtime: HabitRuntimeSnapshot) -> String? {
        if habit.trackingMode == .manual {
            return manualRemainingText(for: habit, runtime: runtime)
        }
        return durationRemainingText(for: habit, runtime: runtime)
    }

    private func manualRemainingText(for habit: Habit, runtime: HabitRuntimeSnapshot) -> String? {
        guard let attempt = habit.currentAttempt else { return nil }

        let completedDays = HabitProgressClock.completedDays(for: attempt, at: runtime.now)
        let targetDay = manualCheckTargetDate(for: habit, now: runtime.now)
        let checked = hasManualCheck(for: habit, targetDay: targetDay)
        let activationDate = manualCheckActivationDate(for: habit, now: runtime.now)
        let windowIsOpen = !checked && targetDay != nil && activationDate.map { runtime.now >= $0 } == true

        if windowIsOpen, completedDays > 0 {
            // Window open: count down until it closes.
            let deadline = HabitProgressClock.manualCheckDeadline(
                for: attempt,
                completedDayIndex: completedDays - 1
            )
            return countdownText(from: runtime.now, to: deadline)
        }

        // Window closed: count down until the next one opens.
        let nextDate = checked
            ? manualCheckNextActivationDate(for: habit, now: runtime.now)
            : activationDate
        guard let nextDate else { return nil }
        return countdownText(from: runtime.now, to: nextDate)
    }

    private func durationRemainingText(for habit: Habit, runtime: HabitRuntimeSnapshot) -> String? {
        guard let targetDays = habit.targetDays, let startedAt = runtime.startedAt else { return nil }
        let deadline = startedAt.addingTimeInterval(TimeInterval(targetDays) * HabitProgressClock.daySeconds)
        guard deadline > runtime.now else {
            return localizedHabitString("habits.detail.time_remaining.done", fallback: "Completed")
        }
        return countdownText(from: runtime.now, to: deadline)
    }

    private func countdownText(from now: Date, to date: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        if days > 0 {
            return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, seconds)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// "Let's continue" row – greyed out until the next check-in window opens.
    private func manualCheckRow(for habit: Habit, runtime: HabitRuntimeSnapshot) -> some View {
        let targetDay = manualCheckTargetDate(for: habit, now: runtime.now)
        let currentActivationDate = manualCheckActivationDate(for: habit, now: runtime.now)
        let nextActivationDate = manualCheckNextActivationDate(for: habit, now: runtime.now)
        let checked = hasManualCheck(for: habit, targetDay: targetDay)
        let ready = !checked && targetDay != nil && currentActivationDate.map { runtime.now >= $0 } == true
        let displayActivationDate = (checked || manualCheckButtonPhase == .success) ? nextActivationDate : currentActivationDate

        _ = displayActivationDate

        let title = manualCheckButtonPhase == .submitting
            ? localizedHabitString("habits.detail.manual.saving", fallback: "Saving…")
            : localizedHabitString("habits.detail.manual.ready", fallback: "Let's continue")

        return EOInlineActionRow(
            title: Text(verbatim: title),
            tint: habit.color,
            isEnabled: ready && manualCheckButtonPhase == .idle
        ) {
            submitManualCheck(for: habit, day: targetDay ?? runtime.now)
        }
    }

    private func overviewCard(for habit: Habit, runtime: HabitRuntimeSnapshot, progress: HabitMilestoneProgress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(habit.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 16) {
                HabitMilestoneRing(progress: progress, tint: habit.color, icon: refreshedHabit.icon, size: 92, lineWidth: 7, iconSize: 30)

                VStack(alignment: .leading, spacing: 6) {
                    Text(runtime.elapsedText)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Text(runtime.elapsedCaption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private func displayedProgressDays(for habit: Habit, currentStreak: Int, at date: Date) -> Double {
        let currentStreak = Double(currentStreak)
        guard let attempt = habit.currentAttempt, attempt.endedAt == nil else {
            return currentStreak
        }

        let elapsedDays = max(0, date.timeIntervalSince(attempt.startedAt) / HabitProgressClock.daySeconds)
        let nextDayProgress = min(currentStreak + 1, elapsedDays)
        return max(currentStreak, nextDayProgress)
    }

    private func manualCheckCard(for habit: Habit, runtime: HabitRuntimeSnapshot) -> some View {
        let targetDay = manualCheckTargetDate(for: habit, now: runtime.now)
        let currentActivationDate = manualCheckActivationDate(for: habit, now: runtime.now)
        let nextActivationDate = manualCheckNextActivationDate(for: habit, now: runtime.now)
        let checked = hasManualCheck(for: habit, targetDay: targetDay)
        let canCheck = !checked && targetDay != nil && currentActivationDate.map { runtime.now >= $0 } == true
        let displayActivationDate = (checked || manualCheckButtonPhase == .success) ? nextActivationDate : currentActivationDate

        return manualCheckActionButton(
            for: habit,
            day: targetDay ?? runtime.now,
            activationDate: displayActivationDate,
            ready: canCheck,
            phase: manualCheckButtonPhase,
            runtime: runtime
        )
        .frame(maxWidth: .infinity)
    }

    private func manualCheckActionButton(
        for habit: Habit,
        day: Date,
        activationDate: Date?,
        ready: Bool,
        phase: ManualCheckButtonPhase,
        runtime: HabitRuntimeSnapshot
    ) -> some View {
        let labelText: String
        switch phase {
        case .idle:
            if ready {
                labelText = localizedHabitString("habits.detail.manual.ready", fallback: "Выполнено")
            } else {
                labelText = manualCheckCountdownText(until: activationDate ?? runtime.now, now: runtime.now)
            }
        case .submitting:
            labelText = localizedHabitString("habits.detail.manual.saving", fallback: "Сохраняю")
        case .success:
            labelText = manualCheckCountdownText(until: activationDate ?? runtime.now, now: runtime.now)
        }

        return PressableIconButton(
            disabled: !ready || phase != .idle,
            tintColor: habit.color,
            action: { submitManualCheck(for: habit, day: day) }
        ) {
            Text(labelText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .opacity((!ready || phase == .success) ? 0.58 : 1.0)
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: phase)
        }
    }

    private func submitManualCheck(for habit: Habit, day: Date) {
        guard manualCheckButtonPhase == .idle else { return }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            manualCheckButtonPhase = .submitting
        }

        Task {
            let result = await habitsService.addCheckIn(habit: habit, day: day)
            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    manualCheckButtonPhase = result != nil ? .success : .idle
                }
            }

            guard result != nil else { return }

            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    manualCheckButtonPhase = .idle
                }
            }
        }
    }

    private func overviewCardCaption(progress: HabitMilestoneProgress, longestStreak: Int) -> String {
        if longestStreak > 0 {
            return String(
                format: localizedHabitString("habits.detail.longest_streak.value", fallback: "Best streak: %d days"),
                longestStreak
            )
        }

        return String(
            format: NSLocalizedString(
                "habits.detail.milestone.progress",
                tableName: nil,
                bundle: .main,
                value: "%d / %d days to the next milestone",
                comment: "Habit milestone progress text"
            ),
            progress.currentStreak,
            progress.nextThreshold
        )
    }

    private func historyCard(habit: Habit, attempts: [HabitAttempt]) -> some View {
        EOCard {
            EOCardTitleRow(title: Text(verbatim: localizedHabitString("habits.detail.history", fallback: "Past attempts")))

            ForEach(attempts) { attempt in
                EORowSeparator()
                EOListRow(
                    title: Text(verbatim: attemptDurationTitle(attempt, habit: habit)),
                    subtitle: Text(verbatim: attemptDateSubtitle(attempt))
                )
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targetText(habit: Habit) -> String? {
        if automaticTracker(for: habit) == .water {
            guard diaryService.dailyWaterGoalMilliliters > 0 else { return nil }
            return String(
                format: NSLocalizedString(
                    "habits.auto.water.goal",
                    tableName: nil,
                    bundle: .main,
                    value: "Water goal: %d ml",
                    comment: "Displayed water goal text for auto-tracked water habit"
                ),
                diaryService.dailyWaterGoalMilliliters
            )
        }

        guard habit.dailyTarget > 0 else { return nil }
        if habit.unitLabel.isEmpty {
            return String(format: NSLocalizedString("habits.editor.daily_target.value", comment: ""), habit.dailyTarget)
        }
        return "\(habit.dailyTarget) \(habit.unitLabel)"
    }

    private func attemptDateSubtitle(_ attempt: HabitAttempt) -> String {
        let start = compactAttemptDateText(for: attempt.startedAt)
        if let ended = attempt.endedAt {
            return "\(start) - \(compactAttemptDateText(for: ended))"
        }
        return start
    }

    private func attemptDurationTitle(_ attempt: HabitAttempt, habit: Habit) -> String {
        localizedDayCountText(resolvedAttemptDurationDays(attempt, for: habit))
    }

    private func compactAttemptDateText(for date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        let currentYear = calendar.component(.year, from: Date())
        let targetYear = calendar.component(.year, from: date)
        formatter.dateFormat = currentYear == targetYear ? "dd.MM" : "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func localizedDayCountText(_ days: Int) -> String {
        let localeIdentifier = Locale.autoupdatingCurrent.identifier.lowercased()
        if localeIdentifier.hasPrefix("ru") {
            return russianDayCountText(days)
        }

        return String(
            format: NSLocalizedString(
                "habits.detail.history.duration",
                tableName: nil,
                bundle: .main,
                value: "%d days",
                comment: "Past habit attempt duration"
            ),
            days
        )
    }

    private func russianDayCountText(_ days: Int) -> String {
        let absoluteDays = abs(days)
        let mod100 = absoluteDays % 100
        let mod10 = absoluteDays % 10

        let suffix: String
        if mod100 >= 11 && mod100 <= 14 {
            suffix = "дней"
        } else {
            switch mod10 {
            case 1:
                suffix = "день"
            case 2, 3, 4:
                suffix = "дня"
            default:
                suffix = "дней"
            }
        }

        return "\(days) \(suffix)"
    }

    private func automaticDayState(for day: Date, habit: Habit, tracker: HabitAutomaticTracker, trackingStart: Date) -> HabitDayState {
        let calendar = Calendar.current
        let resolvedDay = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: .now)
        let isPastDay = resolvedDay < today
        let isToday = calendar.isDateInToday(resolvedDay)

        if resolvedDay < trackingStart {
            return .neutral
        }

        switch tracker {
        case .water:
            let goal = diaryService.dailyWaterGoalMilliliters
            let intake = diaryService.waterIntake(for: resolvedDay)
            guard goal > 0 else {
                return .neutral
            }
            if intake >= goal {
                return .success
            }
            if isPastDay {
                return .failure
            }
            return .neutral

        case .lateMeals:
            let meals = diaryService.meals(on: resolvedDay)
            guard let latestMeal = meals.max(by: { $0.scheduledAt < $1.scheduledAt }) else {
                return isPastDay ? .failure : .neutral
            }

            let cutoff = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: resolvedDay) ?? resolvedDay

            if latestMeal.scheduledAt >= cutoff {
                return .failure
            }

            if isPastDay || (isToday && Date() >= cutoff) {
                return .success
            }

            return .neutral

        case .regularity:
            let progress = HabitStreakResolver.regularityProgress(for: resolvedDay, diaryService: diaryService)
            guard progress.requiredSlots > 0 else {
                return .neutral
            }
            if progress.isComplete {
                return .success
            }
            if isPastDay {
                return .failure
            }
            return .neutral

        case .sugar:
            let meals = diaryService.meals(on: resolvedDay)
            let estimatedSugar = estimatedSugar(for: meals)
            let threshold = sugarDailyTargetGrams(for: habit)

            if estimatedSugar > threshold {
                return .failure
            }

            if isPastDay {
                return .success
            }

            return .neutral

        case .nutritionGoal:
            return nutritionGoalDayState(for: resolvedDay, isPastDay: isPastDay)
        }
    }

    private func automaticTracker(for habit: Habit) -> HabitAutomaticTracker? {
        guard habit.trackingMode == .automatic else { return nil }
        return HabitAutomaticTracker(habit: habit)
    }

    private func shouldShowManualCheckAction(for habit: Habit) -> Bool {
        habit.trackingMode == .manual
    }

    private func hasManualCheck(for habit: Habit, targetDay: Date?) -> Bool {
        guard let attempt = habit.currentAttempt, let targetDay else { return false }
        let calendar = Calendar.current
        let resolvedDay = calendar.startOfDay(for: targetDay)
        return habitsService.checkIns(forAttempt: attempt.id).contains { checkIn in
            calendar.startOfDay(for: checkIn.day) == resolvedDay
        }
    }

    private func manualCheckTargetDate(for habit: Habit, now: Date = .now) -> Date? {
        guard let attempt = habit.currentAttempt else { return nil }
        let completedDays = HabitProgressClock.completedDays(for: attempt, at: now)
        guard completedDays > 0 else { return nil }

        let calendar = Calendar.current
        return HabitProgressClock.manualCheckDay(
            for: attempt,
            completedDayIndex: completedDays - 1,
            calendar: calendar
        )
    }

    private func manualCheckActivationDate(for habit: Habit, now: Date = .now) -> Date? {
        guard let attempt = habit.currentAttempt else { return nil }

        let completedDays = HabitProgressClock.completedDays(for: attempt, at: now)
        let nextCompletedDay = max(1, completedDays)
        return attempt.startedAt.addingTimeInterval(TimeInterval(nextCompletedDay) * HabitProgressClock.daySeconds)
    }

    private func manualCheckNextActivationDate(for habit: Habit, now: Date = .now) -> Date? {
        guard let attempt = habit.currentAttempt else { return nil }

        let completedDays = HabitProgressClock.completedDays(for: attempt, at: now)
        let nextCompletedDay = max(1, completedDays + 1)
        return attempt.startedAt.addingTimeInterval(TimeInterval(nextCompletedDay) * HabitProgressClock.daySeconds)
    }

    private func manualCheckCountdownText(until activationDate: Date, now: Date) -> String {
        let remaining = max(0, Int(activationDate.timeIntervalSince(now)))
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        if days > 0 {
            return String(format: "%d:%02d:%02d:%02d", days, hours, minutes, seconds)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func durationProgressText(for habit: Habit, currentStreak: Int) -> String? {
        guard let targetDays = habit.targetDays else { return nil }

        let shownDays = min(currentStreak, targetDays)
        return String(
            format: localizedHabitString("habits.duration.progress", fallback: "%d / %d days"),
            shownDays,
            targetDays
        )
    }

    private func extendDuration(_ habit: Habit, by days: Int) async {
        guard days > 0 else { return }
        let targetDays = max(1, (habit.targetDays ?? HabitProgressClock.completedDays(for: habit.currentAttempt)) + days)
        _ = await habitsService.updateHabit(
            id: habit.id,
            name: habit.name,
            description: habit.description,
            kind: habit.kind,
            icon: habit.icon,
            colorHex: habit.colorHex,
            dailyTarget: habit.dailyTarget,
            unitLabel: habit.unitLabel,
            archived: habit.isArchived,
            clientSettings: HabitClientSettings(
                trackingMode: habit.trackingMode,
                targetDays: targetDays,
                isReminderEnabled: habit.manualReminderEnabled
            )
        )
    }

    private func localizedHabitString(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "Habit detail auto-tracking text")
    }

    private func estimatedSugar(for meals: [MealEntry]) -> Double {
        meals.reduce(0) { partial, meal in
            partial + meal.items.reduce(0) { itemTotal, item in
                itemTotal + estimatedSugar(for: item)
            }
        }
    }

    private func sugarDailyTargetGrams(for habit: Habit) -> Double {
        Double(habit.dailyTarget > 0 ? habit.dailyTarget : HabitTemplate.adultSugarDailyTargetGrams)
    }

    private func estimatedSugar(for item: MealItemEntry) -> Double {
        guard let product = item.linkedProductSummary else { return 0 }
        switch item.unit {
        case .serving:
            return product.sugarPer100g * max(item.amount, 1)
        case .grams, .milliliters:
            return product.sugarPer100g * item.amount / 100.0
        }
    }

    private func nutritionGoalDayState(for day: Date, isPastDay: Bool) -> HabitDayState {
        let meals = diaryService.meals(on: day)
        let summary = NutritionSummary(
            calories: meals.reduce(0) { $0 + $1.calories },
            protein: meals.reduce(0) { $0 + $1.protein },
            fat: meals.reduce(0) { $0 + $1.fat },
            carbs: meals.reduce(0) { $0 + $1.carbs }
        )
        let goal = diaryService.goal(for: day)
        let proteinGoal = diaryService.goalProteinGrams(for: day)
        let fatGoal = diaryService.goalFatGrams(for: day)
        let carbsGoal = diaryService.goalCarbsGrams(for: day)

        guard goal.calories > 0, proteinGoal > 0, fatGoal > 0, carbsGoal > 0 else {
            return .neutral
        }

        guard summary.calories > 0 || summary.protein > 0 || summary.fat > 0 || summary.carbs > 0 else {
            return isPastDay ? .failure : .neutral
        }

        let complete = isWithinTenPercent(summary.calories, of: goal.calories)
            && isWithinTenPercent(summary.protein, of: proteinGoal)
            && isWithinTenPercent(summary.fat, of: fatGoal)
            && isWithinTenPercent(summary.carbs, of: carbsGoal)

        if complete {
            return .success
        }

        return isPastDay ? .failure : .neutral
    }

    private func isWithinTenPercent(_ value: Int, of target: Int) -> Bool {
        guard target > 0 else { return false }
        let ratio = Double(value) / Double(target)
        return ratio >= 0.9 && ratio <= 1.1
    }

    private func dayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func daysInRange(from start: Date, through end: Date) -> [Date] {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        guard normalizedStart <= normalizedEnd else { return [] }

        var days: [Date] = []
        var currentDay = normalizedStart
        while currentDay <= normalizedEnd {
            days.append(currentDay)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }
        return days
    }

    private func loadAutomaticHistoryIfNeeded(for habit: Habit) async {
        guard automaticTracker(for: habit) != nil else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let historyStart = automaticTrackingStart(for: habit, today: today)
        await diaryService.loadMealHistory(from: historyStart, through: today)
    }

    private func enforceAutomaticFailureResetIfNeeded(for habit: Habit) async {
        guard habit.trackingMode == .automatic,
              HabitAutomaticTracker(habit: habit) != nil,
              let failedDay = HabitStreakResolver.failureDateRequiringReset(
                for: habit,
                diaryService: diaryService
              ) else { return }

        let dayKey = DateFormatter.habitDay.string(from: failedDay)
        let resetReason = "automatic_failure:\(dayKey)"
        if await habitsService.resetProgress(habitID: habit.id, reason: resetReason) != nil {
            await habitsService.loadAttempts(habitID: habit.id)
        }
    }

    private func automaticSuccessfulDays(for habit: Habit, on referenceDate: Date = .now) -> [Date] {
        guard let tracker = automaticTracker(for: habit) else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let trackingStart = automaticTrackingStart(for: habit, today: today)
        let completedDay = lastCompletedHabitDay(for: referenceDate)
        guard trackingStart <= completedDay else { return [] }

        return daysInRange(from: trackingStart, through: completedDay).filter { day in
            automaticDayState(for: day, habit: habit, tracker: tracker, trackingStart: trackingStart) == .success
        }
    }

    private func manualTransitionSeedDays(for habit: Habit, on referenceDate: Date = .now) -> [Date] {
        if automaticTracker(for: habit) != nil {
            return automaticSuccessfulDays(for: habit, on: referenceDate)
        }

        guard let attempt = habit.currentAttempt else { return [] }

        let completedDays = HabitProgressClock.completedDays(for: attempt, at: referenceDate)
        guard completedDays > 0 else { return [] }

        let calendar = Calendar.current
        return (0..<completedDays).compactMap { completedDayIndex in
            HabitProgressClock.manualCheckDay(
                for: attempt,
                completedDayIndex: completedDayIndex,
                calendar: calendar
            )
        }
    }

    private func seedManualCheckIns(for habit: Habit, days: [Date]) async {
        guard let attemptID = habit.currentAttempt?.id, !days.isEmpty else { return }
        let calendar = Calendar.current
        let existingDays = Set(habitsService.checkIns(forAttempt: attemptID).map { calendar.startOfDay(for: $0.day) })

        for day in days where !existingDays.contains(calendar.startOfDay(for: day)) {
            _ = await habitsService.addCheckIn(habit: habit, day: day)
        }
    }

    private func automaticTrackingStart(for habit: Habit, today: Date) -> Date {
        let calendar = Calendar.current
        let recentWindowStart = calendar.date(byAdding: .day, value: -120, to: today) ?? today
        let attempts = habitsService.attempts(forHabit: habit.id)
        let earliestAttemptStart = attempts
            .map { calendar.startOfDay(for: $0.startedAt) }
            .min()
        let attemptStart = earliestAttemptStart ?? habit.currentAttempt.map { calendar.startOfDay(for: $0.startedAt) } ?? recentWindowStart
        return max(attemptStart, recentWindowStart)
    }

    private func resolvedLongestStreak(for habit: Habit, attempts: [HabitAttempt], currentStreak: Int, fallbackLongest: Int) -> Int {
        if automaticTracker(for: habit) != nil {
            return max(currentStreak, fallbackLongest)
        }

        let attemptsLongest = attempts.map { resolvedBestAttemptLength($0, for: habit) }.max() ?? 0
        let currentAttemptLongest = habit.currentAttempt.map { resolvedBestAttemptLength($0, for: habit) } ?? 0
        if habit.kind == .quit {
            return max(currentStreak, currentAttemptLongest, attemptsLongest)
        }
        return max(currentStreak, fallbackLongest, currentAttemptLongest, attemptsLongest)
    }

    private func resolvedAttemptDurationDays(_ attempt: HabitAttempt, for habit: Habit) -> Int {
        if habit.kind == .quit && habit.trackingMode != .manual {
            return resolvedQuitAttemptDurationDays(attempt)
        }

        let checkIns = habitsService.checkIns(forAttempt: attempt.id)
        if !checkIns.isEmpty {
            let calendar = Calendar.current
            let uniqueDays = Set(checkIns.map { calendar.startOfDay(for: $0.day) })
            return uniqueDays.count
        }

        if attempt.longestStreakDays > 0 {
            return attempt.longestStreakDays
        }

        return attempt.durationDays
    }

    private func resolvedQuitAttemptDurationDays(_ attempt: HabitAttempt) -> Int {
        HabitProgressClock.completedDays(for: attempt, at: attempt.endedAt ?? Date())
    }

    private func resolvedAttemptStreakDays(_ attempt: HabitAttempt, for habit: Habit) -> Int {
        if habit.kind == .quit && habit.trackingMode != .manual {
            return resolvedAttemptDurationDays(attempt, for: habit)
        }
        return max(resolvedAttemptDurationDays(attempt, for: habit), attempt.longestStreakDays)
    }

    private func resolvedBestAttemptLength(_ attempt: HabitAttempt, for habit: Habit) -> Int {
        resolvedAttemptStreakDays(attempt, for: habit)
    }

    private func lastCompletedHabitDay(for referenceDate: Date) -> Date {
        let calendar = Calendar.current
        let resolvedDay = calendar.startOfDay(for: referenceDate)
        if calendar.isDateInToday(resolvedDay) {
            return calendar.date(byAdding: .day, value: -1, to: resolvedDay) ?? resolvedDay
        }

        return resolvedDay
    }
}

private struct HabitRuntimeSnapshot {
    let now: Date
    let completedDays: Int
    let completedIntervalDate: Date?
    let startedAt: Date?

    init(habit: Habit, now: Date) {
        self.now = now
        self.completedDays = HabitProgressClock.completedDays(for: habit.currentAttempt, at: now)
        self.completedIntervalDate = HabitProgressClock.currentCompletedIntervalDate(for: habit.currentAttempt, at: now)
        self.startedAt = habit.currentAttempt?.startedAt
    }

    var elapsedText: String {
        HabitProgressClock.elapsedText(since: startedAt, to: now)
    }

    var elapsedCaption: String {
        guard let startedAt else {
            return localized("habits.detail.countdown.no_active", fallback: "No active attempt")
        }
        return String(
            format: localized("habits.detail.elapsed.caption", fallback: "Started at %@"),
            dateTimeText(for: startedAt)
        )
    }

    var manualCheckCaption: String {
        guard let completedIntervalDate else {
            return localized("habits.detail.manual.wait", fallback: "The first mark opens after the first completed day.")
        }
        return String(
            format: localized("habits.detail.manual.caption", fallback: "Latest completed interval: %@"),
            dateTimeText(for: completedIntervalDate)
        )
    }

    private func localized(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "Habit countdown text")
    }

    private func dateTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private enum HabitDayState {
    case success
    case failure
    case neutral
}
