import Foundation
import SwiftProtobuf
import SwiftUI

enum HabitKind: String, CaseIterable, Codable, Sendable {
    case build
    case quit

    var titleKey: String {
        switch self {
        case .build: return "habits.kind.build"
        case .quit: return "habits.kind.quit"
        }
    }

    var grpcValue: Food_HabitKind {
        switch self {
        case .build: return .build
        case .quit: return .quit
        }
    }

    static func fromGRPC(_ value: Food_HabitKind) -> HabitKind {
        switch value {
        case .quit: return .quit
        default: return .build
        }
    }
}

enum HabitTrackingMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case manual

    var grpcValue: Food_HabitTrackingMode {
        switch self {
        case .automatic: return .automatic
        case .manual: return .manual
        }
    }

    static func fromGRPC(_ value: Food_HabitTrackingMode) -> HabitTrackingMode {
        switch value {
        case .manual: return .manual
        default: return .automatic
        }
    }
}

struct HabitAttempt: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let habitID: UUID
    let startedAt: Date
    let endedAt: Date?
    let endReason: String
    let totalCheckIns: Int
    let longestStreakDays: Int

    var isActive: Bool { endedAt == nil }
    var durationDays: Int {
        let end = endedAt ?? Date()
        return max(0, Int(end.timeIntervalSince(startedAt) / 86_400))
    }
}

struct HabitCheckIn: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let attemptID: UUID
    let day: Date
    let value: Int
    let note: String
    let checkedAt: Date
}

struct Habit: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var description: String
    var kind: HabitKind
    var icon: String
    var colorHex: String
    var dailyTarget: Int
    var unitLabel: String
    var trackingMode: HabitTrackingMode
    var targetDays: Int?
    var manualReminderEnabled: Bool
    var milestoneNotificationsEnabled: Bool
    var archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    var currentAttempt: HabitAttempt?

    var isArchived: Bool { archivedAt != nil }
    var color: Color { Color(hex: colorHex) ?? .green }

    var clientSettings: HabitClientSettings {
        HabitClientSettings(
            trackingMode: trackingMode,
            targetDays: targetDays,
            isReminderEnabled: manualReminderEnabled
        )
    }
}

struct HabitClientSettings: Codable, Equatable, Sendable {
    var trackingMode: HabitTrackingMode
    var targetDays: Int?
    var isReminderEnabled: Bool

    static let `default` = HabitClientSettings(
        trackingMode: .automatic,
        targetDays: nil,
        isReminderEnabled: false
    )

    var normalized: HabitClientSettings {
        HabitClientSettings(
            trackingMode: trackingMode,
            targetDays: targetDays.map { max(1, $0) },
            isReminderEnabled: trackingMode == .manual && isReminderEnabled
        )
    }
}

struct HabitTemplate: Identifiable, Hashable, Sendable {
    static let adultSugarDailyTargetGrams = 50

    let id: String
    let nameKey: String
    let descriptionKey: String
    let kind: HabitKind
    let icon: String
    let colorHex: String
    let dailyTarget: Int
    let unitLabelKey: String?

    static let builtIns: [HabitTemplate] = [
        HabitTemplate(
            id: "water",
            nameKey: "habits.idea.water",
            descriptionKey: "habits.template.water.desc",
            kind: .build,
            icon: "drop.fill",
            colorHex: "#0A84FF",
            dailyTarget: 0,
            unitLabelKey: nil
        )
    ]
}

// MARK: - GRPC bridging

extension HabitAttempt {
    init?(grpc: Food_HabitAttempt) {
        guard let id = UUID(uuidString: grpc.id), let habitID = UUID(uuidString: grpc.habitID) else { return nil }
        self.id = id
        self.habitID = habitID
        self.startedAt = grpc.hasStartedAt ? grpc.startedAt.date : Date()
        self.endedAt = grpc.hasEndedAt ? grpc.endedAt.date : nil
        self.endReason = grpc.endReason
        self.totalCheckIns = Int(grpc.totalCheckIns)
        self.longestStreakDays = Int(grpc.longestStreakDays)
    }
}

extension HabitCheckIn {
    init?(grpc: Food_HabitCheckIn) {
        guard let id = UUID(uuidString: grpc.id), let attemptID = UUID(uuidString: grpc.attemptID) else { return nil }
        let formatter = DateFormatter.habitDay
        guard let day = formatter.date(from: grpc.day) else { return nil }
        self.id = id
        self.attemptID = attemptID
        self.day = day
        self.value = Int(grpc.value)
        self.note = grpc.note
        self.checkedAt = grpc.hasCheckedAt ? grpc.checkedAt.date : day
    }
}

extension Habit {
    init?(grpc: Food_Habit) {
        guard let id = UUID(uuidString: grpc.id) else { return nil }
        self.id = id
        self.name = grpc.name
        self.description = grpc.description_p
        self.kind = HabitKind.fromGRPC(grpc.kind)
        self.icon = grpc.icon.isEmpty ? "leaf.fill" : grpc.icon
        self.colorHex = grpc.colorHex.isEmpty ? "#34C759" : grpc.colorHex
        self.dailyTarget = Int(grpc.dailyTarget)
        self.unitLabel = grpc.unitLabel
        self.trackingMode = HabitTrackingMode.fromGRPC(grpc.trackingMode)
        self.targetDays = grpc.targetDays > 0 ? Int(grpc.targetDays) : nil
        self.manualReminderEnabled = grpc.manualReminderEnabled
        self.milestoneNotificationsEnabled = grpc.milestoneNotificationsEnabled
        self.archivedAt = grpc.hasArchivedAt ? grpc.archivedAt.date : nil
        self.createdAt = grpc.hasCreatedAt ? grpc.createdAt.date : Date()
        self.updatedAt = grpc.hasUpdatedAt ? grpc.updatedAt.date : Date()
        self.currentAttempt = grpc.hasCurrentAttempt ? HabitAttempt(grpc: grpc.currentAttempt) : nil
    }
}

extension DateFormatter {
    static let habitDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

enum HabitPalette {
    static let colors: [String] = [
        "#34C759", "#0A84FF", "#FF9F0A", "#FF453A",
        "#5E5CE6", "#BF5AF2", "#FF2D55", "#64D2FF",
        "#FFD60A", "#30D158", "#A1A1AA", "#8E8E93"
    ]

    static let icons: [String] = [
        "leaf.fill", "drop.fill", "flame.fill", "bolt.fill",
        "heart.fill", "figure.walk", "figure.run", "dumbbell.fill",
        "fork.knife", "cup.and.saucer.fill", "carrot.fill", "takeoutbag.and.cup.and.straw.fill",
        "moon.zzz.fill", "bed.double.fill", "alarm.fill", "sun.max.fill",
        "nosign", "minus.circle.fill", "checkmark.seal.fill", "star.fill",
        "book.fill", "brain.head.profile", "music.note", "headphones"
    ]

    /// What an icon is called, for the menu and for VoiceOver.
    ///
    /// The list above is SF Symbol names, which are addresses rather than words:
    /// a menu offering "takeoutbag.and.cup.and.straw.fill" tells the reader what
    /// the drawing is filed under, not what it means. Named after what the icon
    /// stands for in a habit — "Running", not "figure.run" — because that is
    /// what is being chosen.
    ///
    /// An unknown symbol falls back to its own name, so a symbol added to the
    /// list without a title still appears rather than going blank.
    static func title(for symbol: String) -> String {
        guard let key = titleKeys[symbol] else { return symbol }
        return NSLocalizedString(key, comment: "Habit icon name")
    }

    private static let titleKeys: [String: String] = [
        "leaf.fill": "habits.icon.leaf",
        "drop.fill": "habits.icon.drop",
        "flame.fill": "habits.icon.flame",
        "bolt.fill": "habits.icon.bolt",
        "heart.fill": "habits.icon.heart",
        "figure.walk": "habits.icon.walk",
        "figure.run": "habits.icon.run",
        "dumbbell.fill": "habits.icon.workout",
        "fork.knife": "habits.icon.meal",
        "cup.and.saucer.fill": "habits.icon.drink",
        "carrot.fill": "habits.icon.vegetables",
        "takeoutbag.and.cup.and.straw.fill": "habits.icon.takeaway",
        "moon.zzz.fill": "habits.icon.sleep",
        "bed.double.fill": "habits.icon.bed",
        "alarm.fill": "habits.icon.alarm",
        "sun.max.fill": "habits.icon.morning",
        "nosign": "habits.icon.avoid",
        "minus.circle.fill": "habits.icon.less",
        "checkmark.seal.fill": "habits.icon.done",
        "star.fill": "habits.icon.star",
        "book.fill": "habits.icon.reading",
        "brain.head.profile": "habits.icon.mind",
        "music.note": "habits.icon.music",
        "headphones": "habits.icon.headphones"
    ]
}
