import Foundation
import Combine
import WatchConnectivity


@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var todaySnapshot = WatchTodaySnapshot.empty
    @Published var isPhoneReachable = false
    @Published var hasReceivedInitialData = false

    private let session: WCSession = .default
    private let cacheKey = "EatometerWatch.cachedSnapshot"

    override init() {
        super.init()
        loadCachedSnapshot()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func adjustWater(by milliliters: Int) {
        guard milliliters != 0 else { return }

        todaySnapshot.waterIntakeMilliliters = max(0, todaySnapshot.waterIntakeMilliliters + milliliters)
        todaySnapshot.updatedAt = Date()
        cacheSnapshot()

        sendPayload([
            "action": "addWater",
            "amount": milliliters,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    func logFavoriteProduct(_ id: String, mealCategoryID: String) {
        sendPayload([
            "action": "logFavoriteProduct",
            "productID": id,
            "mealCategoryID": mealCategoryID,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    func logRecipe(_ id: String, mealCategoryID: String) {
        sendPayload([
            "action": "logRecipe",
            "recipeID": id,
            "mealCategoryID": mealCategoryID,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    func logMealTemplate(_ id: String, mealCategoryID: String) {
        sendPayload([
            "action": "logMealTemplate",
            "mealTemplateID": id,
            "mealCategoryID": mealCategoryID,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    func deleteMeal(mealID: String) {
        sendPayload([
            "action": "deleteMeal",
            "mealID": mealID,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    func deleteMealItem(mealID: String, itemID: String?) {
        var payload: [String: Any] = [
            "action": "deleteMealItem",
            "mealID": mealID,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let itemID,
           !itemID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["itemID"] = itemID
        }

        sendPayload(payload)
    }

    private func sendPayload(_ payload: [String: Any]) {
        let wcSession = session
        if wcSession.isReachable {
            wcSession.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                wcSession.transferUserInfo(payload)
            })
        } else {
            wcSession.transferUserInfo(payload)
        }
    }

    private func applySnapshotData(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(WatchTodaySnapshot.self, from: data) else { return }
        todaySnapshot = snapshot
        hasReceivedInitialData = true
        cacheSnapshot()
    }

    // MARK: - Cache

    private func loadCachedSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let snapshot = try? JSONDecoder().decode(WatchTodaySnapshot.self, from: data) else { return }
        if snapshot.dayKey == WatchTodaySnapshot.todayKey() {
            todaySnapshot = snapshot
            hasReceivedInitialData = true
        }
    }

    private func cacheSnapshot() {
        guard let data = try? JSONEncoder().encode(todaySnapshot) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {}

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            self.isPhoneReachable = reachable
            if let data = context["snapshot"] as? Data,
               !data.isEmpty {
                self.applySnapshotData(data)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        Task { @MainActor in
            self.applySnapshotData(data)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isPhoneReachable = reachable
        }
    }
}
