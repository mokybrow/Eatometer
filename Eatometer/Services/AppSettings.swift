import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private var remoteSyncTask: Task<Void, Never>?
    private var remoteSyncHandler: (@Sendable () async -> Void)?

    enum ListSort: String, CaseIterable {
        case titleAsc
        case titleDesc
        case addedNewest
        case addedOldest

        var displayName: String {
            switch self {
            case .titleAsc:
                return NSLocalizedString("settings.listsort.title_asc", comment: "Sort by title asc")
            case .titleDesc:
                return NSLocalizedString("settings.listsort.title_desc", comment: "Sort by title desc")
            case .addedNewest:
                return NSLocalizedString("settings.listsort.added_newest", comment: "Sort newest first")
            case .addedOldest:
                return NSLocalizedString("settings.listsort.added_oldest", comment: "Sort oldest first")
            }
        }
    }

    enum NutritionWidgetRingMetric: String, CaseIterable, Identifiable {
        case calories
        case protein
        case fat
        case carbs

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .calories:
                return NSLocalizedString("settings.widget.metric.calories", tableName: nil, bundle: .main, value: "Calories", comment: "Nutrition widget metric calories")
            case .protein:
                return NSLocalizedString("settings.widget.metric.protein", tableName: nil, bundle: .main, value: "Protein", comment: "Nutrition widget metric protein")
            case .fat:
                return NSLocalizedString("settings.widget.metric.fat", tableName: nil, bundle: .main, value: "Fat", comment: "Nutrition widget metric fat")
            case .carbs:
                return NSLocalizedString("settings.widget.metric.carbs", tableName: nil, bundle: .main, value: "Carbs", comment: "Nutrition widget metric carbs")
            }
        }

        var shortDisplayName: String {
            switch self {
            case .calories:
                return NSLocalizedString("settings.widget.metric.calories.short", tableName: nil, bundle: .main, value: "kcal", comment: "Nutrition widget metric calories short")
            case .protein:
                return NSLocalizedString("settings.widget.metric.protein.short", tableName: nil, bundle: .main, value: "P", comment: "Nutrition widget metric protein short")
            case .fat:
                return NSLocalizedString("settings.widget.metric.fat.short", tableName: nil, bundle: .main, value: "F", comment: "Nutrition widget metric fat short")
            case .carbs:
                return NSLocalizedString("settings.widget.metric.carbs.short", tableName: nil, bundle: .main, value: "C", comment: "Nutrition widget metric carbs short")
            }
        }

        var widgetMarker: String {
            switch self {
            case .calories:
                return "k"
            case .protein:
                return "p"
            case .fat:
                return "f"
            case .carbs:
                return "c"
            }
        }

        var tint: Color {
            switch self {
            case .calories:
                return .pink
            case .protein:
                return .green
            case .fat:
                return .orange
            case .carbs:
                return .blue
            }
        }
    }

    static let defaultNutritionWidgetRingMetrics: [NutritionWidgetRingMetric] = [.calories, .protein, .fat]
    static let defaultWaterWidgetStepMilliliters = 200

    @Published var listSort: ListSort
    @Published var isWaterTrackingEnabled: Bool
    @Published var launchHapticsEnabled: Bool
    @Published var nutritionWidgetRingMetrics: [NutritionWidgetRingMetric]
    @Published var waterWidgetStepMilliliters: Int

    private static let cachedUserProfileKey = "Eatometer.cachedUser.current"
    private static let sharedAppGroupID = "group.com.goeatometer.Eatometer.shared"
    private static let widgetScopeUserIDKey = "Eatometer.widget.scopeUserID"
    private static let nutritionWidgetKind = "EatometerNutritionWidget"
    private static let waterWidgetKind = "EatometerWidget"
    private static let quickMealWidgetKind = "EatometerQuickMealWidget"
    private static let statsWidgetKind = "EatometerStatsWidget"

    private let listSortKeyPrefix = "Eatometer.listSort."
    private let waterTrackingKeyPrefix = "Eatometer.waterTracking."
    private let launchHapticsKeyPrefix = "Eatometer.launchHapticsEnabled."
    private let nutritionWidgetRingMetricsKeyPrefix = "Eatometer.widget.nutritionRingMetrics."
    private let waterWidgetStepKeyPrefix = "Eatometer.widget.waterStep."
    private var scopeUserID: String = "anon"

    private var listSortKey: String { listSortKeyPrefix + scopeUserID }
    private var waterTrackingKey: String { waterTrackingKeyPrefix + scopeUserID }
    private var launchHapticsKey: String { launchHapticsKeyPrefix + scopeUserID }
    private var nutritionWidgetRingMetricsKey: String { nutritionWidgetRingMetricsKeyPrefix + scopeUserID }
    private var waterWidgetStepKey: String { waterWidgetStepKeyPrefix + scopeUserID }

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: Self.sharedAppGroupID)
    }

    private func syncWidgetScopeUserID() {
        guard let sharedDefaults else { return }
        sharedDefaults.set(scopeUserID, forKey: Self.widgetScopeUserIDKey)
    }

    private func reloadNutritionWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: Self.nutritionWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.quickMealWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.statsWidgetKind)
    }

    private func reloadWaterWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: Self.waterWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.statsWidgetKind)
    }

    private init() {
        self.listSort = .addedNewest
        self.isWaterTrackingEnabled = true
        self.launchHapticsEnabled = true
        self.nutritionWidgetRingMetrics = Self.defaultNutritionWidgetRingMetrics
        self.waterWidgetStepMilliliters = Self.defaultWaterWidgetStepMilliliters
        self.scopeUserID = Self.initialScopeUserID()
        reloadFromStorage()
    }

    func setRemoteSyncHandler(_ handler: (@Sendable () async -> Void)?) {
        remoteSyncTask?.cancel()
        remoteSyncHandler = handler
    }

    func setListSort(_ value: ListSort) {
        guard listSort != value else { return }
        listSort = value
        UserDefaults.standard.set(value.rawValue, forKey: listSortKey)
        scheduleRemoteSync()
    }

    func setWaterTrackingEnabled(_ value: Bool) {
        guard isWaterTrackingEnabled != value else { return }
        isWaterTrackingEnabled = value
        UserDefaults.standard.set(value, forKey: waterTrackingKey)
    }

    func setLaunchHapticsEnabled(_ value: Bool) {
        guard launchHapticsEnabled != value else { return }
        launchHapticsEnabled = value
        UserDefaults.standard.set(value, forKey: launchHapticsKey)
    }

    func setNutritionWidgetRingMetrics(_ value: [NutritionWidgetRingMetric]) {
        let sanitized = Self.sanitizedNutritionWidgetRingMetrics(value)
        guard nutritionWidgetRingMetrics != sanitized else { return }
        nutritionWidgetRingMetrics = sanitized
        UserDefaults.standard.set(sanitized.map(\.rawValue), forKey: nutritionWidgetRingMetricsKey)
        sharedDefaults?.set(sanitized.map(\.rawValue), forKey: nutritionWidgetRingMetricsKey)
        syncWidgetScopeUserID()
        reloadNutritionWidgetTimelines()
    }

    func setWaterWidgetStepMilliliters(_ value: Int) {
        let sanitized = max(50, min(2000, value))
        guard waterWidgetStepMilliliters != sanitized else { return }
        waterWidgetStepMilliliters = sanitized
        UserDefaults.standard.set(sanitized, forKey: waterWidgetStepKey)
        sharedDefaults?.set(sanitized, forKey: waterWidgetStepKey)
        syncWidgetScopeUserID()
        reloadWaterWidgetTimelines()
    }

    func setScope(userID: String?) {
        let normalizedCandidate = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = normalizedCandidate.isEmpty ? "anon" : normalizedCandidate
        guard normalized != scopeUserID else { return }
        remoteSyncTask?.cancel()
        scopeUserID = normalized
        syncWidgetScopeUserID()
        reloadFromStorage()
    }

    func resetToDefaults() {
        remoteSyncTask?.cancel()
        listSort = .addedNewest
        isWaterTrackingEnabled = true
        launchHapticsEnabled = true
        nutritionWidgetRingMetrics = Self.defaultNutritionWidgetRingMetrics
        waterWidgetStepMilliliters = Self.defaultWaterWidgetStepMilliliters
        UserDefaults.standard.set(listSort.rawValue, forKey: listSortKey)
        UserDefaults.standard.set(isWaterTrackingEnabled, forKey: waterTrackingKey)
        UserDefaults.standard.set(launchHapticsEnabled, forKey: launchHapticsKey)
        UserDefaults.standard.set(nutritionWidgetRingMetrics.map(\.rawValue), forKey: nutritionWidgetRingMetricsKey)
        UserDefaults.standard.set(waterWidgetStepMilliliters, forKey: waterWidgetStepKey)
        sharedDefaults?.set(nutritionWidgetRingMetrics.map(\.rawValue), forKey: nutritionWidgetRingMetricsKey)
        sharedDefaults?.set(waterWidgetStepMilliliters, forKey: waterWidgetStepKey)
        syncWidgetScopeUserID()
        reloadNutritionWidgetTimelines()
        reloadWaterWidgetTimelines()
    }

    func applyFromRemote(listSort: String) {
        Task { @MainActor in
            self.listSort = .addedNewest

            UserDefaults.standard.set(self.listSort.rawValue, forKey: listSortKey)
        }
    }

    private func reloadFromStorage() {
        let defaults = UserDefaults.standard
        listSort = .addedNewest
        defaults.set(listSort.rawValue, forKey: listSortKey)
        if let storedWaterTrackingValue = defaults.object(forKey: waterTrackingKey) as? Bool {
            isWaterTrackingEnabled = storedWaterTrackingValue
        } else {
            isWaterTrackingEnabled = true
        }
        if let storedLaunchHapticsValue = defaults.object(forKey: launchHapticsKey) as? Bool {
            launchHapticsEnabled = storedLaunchHapticsValue
        } else {
            launchHapticsEnabled = true
        }
        let storedRingMetrics = defaults.stringArray(forKey: nutritionWidgetRingMetricsKey)?.compactMap(NutritionWidgetRingMetric.init(rawValue:)) ?? Self.defaultNutritionWidgetRingMetrics
        nutritionWidgetRingMetrics = Self.sanitizedNutritionWidgetRingMetrics(storedRingMetrics)
        if defaults.object(forKey: waterWidgetStepKey) != nil {
            let storedStep = defaults.integer(forKey: waterWidgetStepKey)
            waterWidgetStepMilliliters = max(50, min(2000, storedStep))
        } else {
            waterWidgetStepMilliliters = Self.defaultWaterWidgetStepMilliliters
        }
        sharedDefaults?.set(nutritionWidgetRingMetrics.map(\.rawValue), forKey: nutritionWidgetRingMetricsKey)
        sharedDefaults?.set(waterWidgetStepMilliliters, forKey: waterWidgetStepKey)
        syncWidgetScopeUserID()
    }

    private static func initialScopeUserID() -> String {
        guard let cachedProfile = UserDefaults.standard.dictionary(forKey: cachedUserProfileKey),
              let rawUserID = cachedProfile["userID"] as? String
        else {
            return "anon"
        }

        let trimmedUserID = rawUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUserID.isEmpty ? "anon" : trimmedUserID
    }

    private static func sanitizedNutritionWidgetRingMetrics(_ values: [NutritionWidgetRingMetric]) -> [NutritionWidgetRingMetric] {
        var uniqueMetrics: [NutritionWidgetRingMetric] = []

        for metric in values where !uniqueMetrics.contains(metric) {
            uniqueMetrics.append(metric)
        }

        for fallbackMetric in defaultNutritionWidgetRingMetrics where !uniqueMetrics.contains(fallbackMetric) {
            guard uniqueMetrics.count < 3 else { break }
            uniqueMetrics.append(fallbackMetric)
        }

        for metric in NutritionWidgetRingMetric.allCases where !uniqueMetrics.contains(metric) {
            guard uniqueMetrics.count < 3 else { break }
            uniqueMetrics.append(metric)
        }

        return Array(uniqueMetrics.prefix(3))
    }

    private func scheduleRemoteSync() {
        remoteSyncTask?.cancel()

        guard let remoteSyncHandler else { return }

        remoteSyncTask = Task { [remoteSyncHandler] in
            await remoteSyncHandler()
        }
    }
}
