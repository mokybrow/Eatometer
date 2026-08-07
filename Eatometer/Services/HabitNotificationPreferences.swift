import Combine
import Foundation

@MainActor
final class HabitNotificationPreferences: ObservableObject {
    static let shared = HabitNotificationPreferences()

    @Published private(set) var habitNotificationsEnabled: Bool
    @Published private(set) var waterLoggingRemindersEnabled: Bool

    private init() {
        habitNotificationsEnabled = true
        waterLoggingRemindersEnabled = true
    }

    func apply(habitNotificationsEnabled: Bool, waterLoggingRemindersEnabled: Bool) {
        self.habitNotificationsEnabled = habitNotificationsEnabled
        self.waterLoggingRemindersEnabled = waterLoggingRemindersEnabled
    }

    func setHabitNotificationsEnabled(_ enabled: Bool) {
        habitNotificationsEnabled = enabled
    }

    func setWaterLoggingRemindersEnabled(_ enabled: Bool) {
        waterLoggingRemindersEnabled = enabled
    }
}