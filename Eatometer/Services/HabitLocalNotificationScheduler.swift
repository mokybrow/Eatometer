import Foundation
import Combine
import UserNotifications

@MainActor
final class HabitLocalNotificationScheduler {
    static let shared = HabitLocalNotificationScheduler()

    private let manualNotificationPrefix = "habit-manual-check-"
    private let resetNotificationPrefix = "habit-auto-reset-"
    private let waterNotificationPrefix = "water-log-reminder-"
    private let manualReminderLookaheadDays = 30

    private struct ScheduledManualReminder {
        let identifier: String
        let date: Date
    }

    private init() {}

    func refreshReminders(for habits: [Habit]) {
        guard HabitNotificationPreferences.shared.habitNotificationsEnabled else {
            cancelPendingRequests(withPrefix: manualNotificationPrefix)
            cancelPendingRequests(withPrefix: resetNotificationPrefix)
            return
        }

        let activeHabitIDs = Set(habits.map(\.id))
        let reminderHabits = habits.filter { habit in
            !habit.isArchived && habit.trackingMode == .manual && habit.manualReminderEnabled
        }
        let schedulesByHabitID = Dictionary(
            uniqueKeysWithValues: reminderHabits.map { habit in
                (habit.id, scheduledManualReminders(for: habit))
            }
        )
        let requestedIdentifiers = Set(
            schedulesByHabitID.values
                .flatMap { $0 }
                .map(\.identifier)
        )

        UNUserNotificationCenter.current().getPendingNotificationRequests { [manualNotificationPrefix] requests in
            let staleIdentifiers = requests
                .map(\.identifier)
                .filter { identifier in
                    guard identifier.hasPrefix(manualNotificationPrefix) else { return false }
                    let rawID = String(
                        identifier
                            .dropFirst(manualNotificationPrefix.count)
                            .split(separator: "-")
                            .dropLast()
                            .joined(separator: "-")
                    )
                    guard let habitID = UUID(uuidString: rawID) else { return true }
                    return !activeHabitIDs.contains(habitID) || !requestedIdentifiers.contains(identifier)
                }
            if !staleIdentifiers.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
            }
        }

        for habit in reminderHabits {
            for reminder in schedulesByHabitID[habit.id] ?? [] {
                scheduleReminder(for: habit, reminder: reminder)
            }
        }
    }

    func cancelReminder(for habitID: UUID) {
        cancelPendingRequests(withPrefix: manualNotificationPrefix + habitID.uuidString + "-")
    }

    func refreshWaterReminders(isWaterTrackingEnabled: Bool) {
        // Water reminders are delivered by notification-service. Always clear
        // legacy local requests so an upgraded device does not show duplicate
        // local and remote notifications.
        cancelPendingRequests(withPrefix: waterNotificationPrefix)
        _ = isWaterTrackingEnabled
    }

    func notifyAutomaticReset(for habit: Habit, failedDay: Date) {
        guard HabitNotificationPreferences.shared.habitNotificationsEnabled else { return }

        let dayKey = DateFormatter.habitDay.string(from: failedDay)
        let identifier = resetNotificationPrefix + habit.id.uuidString + "-" + dayKey

        Task {
            await PushNotificationService.shared.requestLocalAuthorizationIfNeeded()

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString(
                "habits.reset.title",
                tableName: nil,
                bundle: .main,
                value: "Habit streak reset",
                comment: "Automatic habit reset notification title"
            )
            let bodyTemplate = NSLocalizedString(
                "habits.reset.body",
                tableName: nil,
                bundle: .main,
                value: "%@ reset because a completed day missed its goal.",
                comment: "Automatic habit reset notification body"
            )
            content.body = String(format: bodyTemplate, habit.name)
            content.sound = .default
            content.userInfo = [
                "type": "habit_auto_reset",
                "habit_id": habit.id.uuidString,
                "failed_day": dayKey,
                "target_screen": "habits",
                "deep_link": "eatometer://habits?habit_id=\(habit.id.uuidString)"
            ]

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    func scheduleCaloriePlanReviewNotification() {
        Task {
            await PushNotificationService.shared.requestLocalAuthorizationIfNeeded()

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString(
                "calorie_review.push.title",
                tableName: nil,
                bundle: .main,
                value: "Update your calorie target?",
                comment: "Calorie plan review notification title"
            )
            content.body = NSLocalizedString(
                "calorie_review.push.body",
                tableName: nil,
                bundle: .main,
                value: "Your weight seems to have changed. You may want to review your daily calorie norm.",
                comment: "Calorie plan review notification body"
            )
            content.sound = .default
            content.userInfo = [
                "type": "calorie_plan_review",
                "target_screen": "calorie_plan_review",
                "deep_link": "eatometer://calorie-plan-review"
            ]

            let request = UNNotificationRequest(
                identifier: "calorie-plan-review",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func scheduleReminder(for habit: Habit, reminder: ScheduledManualReminder) {
        Task {
            await PushNotificationService.shared.requestLocalAuthorizationIfNeeded()

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: reminder.date
            )

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString(
                "habits.reminder.title",
                tableName: nil,
                bundle: .main,
                value: "Check your habit",
                comment: "Manual habit reminder title"
            )
            content.body = NSLocalizedString(
                "habits.reminder.body",
                tableName: nil,
                bundle: .main,
                value: "Open Eatometer and mark whether you completed it today.",
                comment: "Manual habit reminder body"
            )
            content.sound = .default
            content.userInfo = [
                "type": "habit_manual_check",
                "habit_id": habit.id.uuidString,
                "target_screen": "habits",
                "deep_link": "eatometer://habits?habit_id=\(habit.id.uuidString)"
            ]

            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.identifier])
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func scheduledManualReminders(for habit: Habit, now: Date = Date()) -> [ScheduledManualReminder] {
        guard let attempt = habit.currentAttempt, attempt.isActive else { return [] }

        let firstUpcomingDayIndex = max(0, HabitProgressClock.completedDays(for: attempt, at: now))
        let maxScheduledDayIndexExclusive = habit.targetDays.map { max(0, $0) } ?? (firstUpcomingDayIndex + manualReminderLookaheadDays)
        let upperBound = min(maxScheduledDayIndexExclusive, firstUpcomingDayIndex + manualReminderLookaheadDays)
        guard firstUpcomingDayIndex < upperBound else { return [] }

        return (firstUpcomingDayIndex..<upperBound).compactMap { completedDayIndex in
            let activationDate = attempt.startedAt.addingTimeInterval(
                TimeInterval(completedDayIndex + 1) * HabitProgressClock.daySeconds
            )
            guard activationDate > now else { return nil }
            return ScheduledManualReminder(
                identifier: notificationIdentifier(for: habit.id, completedDayIndex: completedDayIndex),
                date: activationDate
            )
        }
    }

    private func notificationIdentifier(for habitID: UUID, completedDayIndex: Int) -> String {
        manualNotificationPrefix + habitID.uuidString + "-\(completedDayIndex)"
    }

    private func cancelPendingRequests(withPrefix prefix: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            if !identifiers.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }
    }
}
