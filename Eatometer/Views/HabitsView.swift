import SwiftUI

struct HabitsView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var habitsService: HabitsService
    @EnvironmentObject private var diaryService: FoodDiaryService
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @Environment(\.colorScheme) private var colorScheme

    @State private var showCreateSheet = false
    @State private var hasLoadedOnce = false
    @State private var streaksByHabitID: [UUID: Int] = [:]
    @State private var streakRecalcTask: Task<Void, Never>?
    @State private var editingHabit: Habit?
    @State private var presentedHabit: Habit?
    @State private var isNotificationsPresented = false

    private var pageBackground: Color {
        EOTheme.Palette.pageBackground
    }

    private var trackedTemplateIDs: Set<String> {
        Set(habitsService.habits.compactMap { habit in
            guard !habit.isArchived else { return nil }
            return HabitAutomaticTracker(habit: habit)?.templateID
        })
    }

    private func scheduleStreakRecalculation(delayNanoseconds: UInt64 = 350_000_000) {
        streakRecalcTask?.cancel()
        streakRecalcTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await recalculateStreaks()
        }
    }

    private func recalculateStreaks() async {
        var resolved: [UUID: Int] = [:]
        let habits = habitsService.habits
        resolved.reserveCapacity(habits.count)

        for (index, habit) in habits.enumerated() {
            resolved[habit.id] = HabitStreakResolver.currentStreak(
                for: habit,
                habitsService: habitsService,
                diaryService: diaryService
            )

            if index > 0 && index.isMultiple(of: 3) {
                await Task.yield()
            }
        }

        if streaksByHabitID != resolved {
            streaksByHabitID = resolved
        }
    }

    var body: some View {
        Group {
            if habitsService.habits.isEmpty {
                if hasLoadedOnce && !habitsService.isLoading {
                    emptyCard
                } else {
                    Color.clear
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: EOTheme.Metrics.headerSpacing) {
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            habitsList(now: timeline.date)
                        }

                        Text("common.context_menu_hint")
                            .font(EOTheme.Typography.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, EOTheme.Metrics.cardInset)
                            .padding(.top, 4)
                    }
                    .eoCardInsets()
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle("habits.title")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItemGroup(placement: .platformTopBarTrailing) {
                NotificationBellButton {
                    isNotificationsPresented = true
                }

                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .tint(.primary)
                .accessibilityLabel(Text("common.add"))
            }
        }
        .navigationDestination(isPresented: $isNotificationsPresented) {
            NotificationInboxView()
        }
        .sheet(isPresented: $showCreateSheet) {
            HabitEditorSheet(
                mode: .create,
                quickTemplates: HabitTemplate.builtIns,
                trackedTemplateIDs: trackedTemplateIDs
            ) { payload in
                let result = await habitsService.createHabit(
                    name: payload.name,
                    description: payload.description,
                    kind: payload.kind,
                    icon: payload.icon,
                    colorHex: payload.colorHex,
                    dailyTarget: payload.dailyTarget,
                    unitLabel: payload.unitLabel,
                    clientSettings: payload.clientSettings
                )
                return result != nil
            }
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorSheet(
                mode: .edit(habit),
                clientSettings: habit.clientSettings
            ) { payload in
                await habitsService.updateHabit(
                    id: habit.id,
                    name: payload.name,
                    description: payload.description,
                    kind: payload.kind,
                    icon: payload.icon,
                    colorHex: payload.colorHex,
                    dailyTarget: payload.dailyTarget,
                    unitLabel: payload.unitLabel,
                    archived: payload.archived,
                    clientSettings: payload.clientSettings
                ) != nil
            }
        }
        .task {
            if !hasLoadedOnce {
                if habitsService.habits.isEmpty {
                    await habitsService.preloadHabitsForCurrentSession()
                }
                await recalculateStreaks()
                hasLoadedOnce = true
            }
        }
        .onDisappear {
            streakRecalcTask?.cancel()
        }
        .onAppear {
            if hasLoadedOnce {
                scheduleStreakRecalculation(delayNanoseconds: 0)
            }
        }
        .onChange(of: habitsService.habits) { _, _ in
            scheduleStreakRecalculation()
        }
        .onChange(of: habitsService.historyRevision) { _, _ in
            scheduleStreakRecalculation()
        }
        .task(id: deepLinkRouter.pendingHabitID) {
            guard let habitID = deepLinkRouter.pendingHabitID else { return }
            deepLinkRouter.pendingHabitID = nil
            presentedHabit = habitsService.habits.first(where: { $0.id == habitID })
        }
    }

    private func displayedCurrentStreak(for habit: Habit, at date: Date) -> Int {
        guard habit.currentAttempt?.endedAt == nil else {
            return streaksByHabitID[habit.id] ?? 0
        }

        return HabitStreakResolver.currentStreak(
            for: habit,
            habitsService: habitsService,
            diaryService: diaryService,
            on: date
        )
    }

    private var emptyCard: some View {
        EOEmptyState("habits.empty.title", subtitle: "habits.empty.subtitle")
    }

    private func displayedProgressDays(for habit: Habit, at date: Date) -> Double {
        let currentStreak = Double(displayedCurrentStreak(for: habit, at: date))
        guard let attempt = habit.currentAttempt, attempt.endedAt == nil else {
            return currentStreak
        }

        let elapsedDays = max(0, date.timeIntervalSince(attempt.startedAt) / HabitProgressClock.daySeconds)
        let nextDayProgress = min(currentStreak + 1, elapsedDays)
        return max(currentStreak, nextDayProgress)
    }

    private func habitsList(now: Date) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(habitsService.habits.enumerated()), id: \.element.id) { index, habit in
                Button {
                    presentedHabit = habit
                } label: {
                    HabitRow(
                        habit: habit,
                        progress: .make(for: displayedProgressDays(for: habit, at: now)),
                        clientSettings: habit.clientSettings,
                        streakDays: displayedCurrentStreak(for: habit, at: now)
                    )
                    .equatable()
                }
                .buttonStyle(.plain)
                .eoRowContextMenu {
                    Button {
                        editingHabit = habit
                    } label: {
                        Label("habits.edit", systemImage: "pencil")
                    }

                    Button {
                        Task { _ = await habitsService.resetProgress(habitID: habit.id, reason: "manual") }
                    } label: {
                        Label("habits.reset", systemImage: "arrow.counterclockwise")
                    }

                    EODestructiveMenuButton("common.delete", systemImage: "trash") {
                        Task { _ = await habitsService.deleteHabit(id: habit.id) }
                    }
                }

                if index < habitsService.habits.count - 1 {
                    EORowSeparator()
                }
            }
        }
        .background(EOTheme.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .sheet(item: $presentedHabit) { habit in
            HabitDetailView(habit: habit)
                .environmentObject(habitsService)
                .environmentObject(diaryService)
        }
    }
}

private struct HabitRow: View, Equatable {
    let habit: Habit
    let progress: HabitMilestoneProgress
    let clientSettings: HabitClientSettings
    let streakDays: Int

    var body: some View {
        EOListRow(
            title: Text(verbatim: habit.name),
            subtitle: Text(verbatim: subtitle),
            accessory: .symbol(name: habit.icon, color: habit.color)
        )
    }

    /// The mock-ups show the current streak ("3 days") under the habit name.
    private var subtitle: String {
        String(
            format: NSLocalizedString("habits.streak.days", comment: "Current habit streak in days"),
            streakDays
        )
    }

    private var legacySubtitle: String {
        if let targetDays = clientSettings.targetDays {
            return String(
                format: NSLocalizedString(
                    "habits.duration.row",
                    tableName: nil,
                    bundle: .main,
                    value: "%d-day habit",
                    comment: "Habit row finite duration label"
                ),
                targetDays
            )
        }

        if clientSettings.trackingMode == .manual {
            return NSLocalizedString(
                "habits.tracking.manual",
                tableName: nil,
                bundle: .main,
                value: "Manual check",
                comment: "Manual habit tracking mode"
            )
        }

        return NSLocalizedString(habit.kind.titleKey, comment: "")
    }
}
