import Combine
import Foundation
import StoreKit
import UIKit

@MainActor
final class SupporterService: ObservableObject {
    static let appID = "eatometer-app"
    private static let pendingBackendReportDefaultsKey = "Eatometer.pendingSupporterBackendReport"

    enum Tier: String, CaseIterable, Identifiable {
        case tier1
        case tier2
        case tier3

        var id: String { rawValue }

        var productID: String {
            switch self {
            case .tier1: return "com.goeatometer.Eatometer.supporter.tier1"
            case .tier2: return "com.goeatometer.Eatometer.supporter.tier2"
            case .tier3: return "com.goeatometer.Eatometer.supporter.tier3"
            }
        }

        var fallbackTitle: String {
            switch self {
            case .tier1:
                return NSLocalizedString("supporter.tier.tier1", value: "Supporter", comment: "Tier 1 fallback name")
            case .tier2:
                return NSLocalizedString("supporter.tier.tier2", value: "Friend", comment: "Tier 2 fallback name")
            case .tier3:
                return NSLocalizedString("supporter.tier.tier3", value: "Patron", comment: "Tier 3 fallback name")
            }
        }
    }

    static let allProductIDs: [String] = Tier.allCases.map { $0.productID }

    static func tier(for productID: String) -> Tier? {
        Tier.allCases.first { $0.productID == productID }
    }

    private struct PendingBackendReport: Codable, Equatable {
        let active: Bool
        let tier: String
        let productID: String
        let originalTransactionID: String
        let expiresAt: Date?
        let appID: String

        var deduplicationKey: String {
            "\(active)|\(tier)|\(originalTransactionID)|\(expiresAt?.timeIntervalSince1970 ?? 0)"
        }
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var activeTier: Tier?
    @Published private(set) var activeExpiresAt: Date?
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var purchaseInProgress: Bool = false
    @Published private(set) var lastErrorMessage: String?

    private let userService: UserService?
    private var transactionListener: Task<Void, Never>?
    private var lastReportedTransactionKey: String?

    private var shouldDeduplicateBackendReports: Bool {
    #if DEBUG
        false
    #else
        true
    #endif
    }

    private var pendingBackendReport: PendingBackendReport? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.pendingBackendReportDefaultsKey) else {
                return nil
            }
            return try? JSONDecoder().decode(PendingBackendReport.self, from: data)
        }
        set {
            let defaults = UserDefaults.standard
            guard let newValue else {
                defaults.removeObject(forKey: Self.pendingBackendReportDefaultsKey)
                return
            }
            guard let encoded = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: Self.pendingBackendReportDefaultsKey)
                return
            }
            defaults.set(encoded, forKey: Self.pendingBackendReportDefaultsKey)
        }
    }

    init(userService: UserService? = nil) {
        self.userService = userService
        self.transactionListener = makeTransactionListener()
    }

    deinit {
        transactionListener?.cancel()
    }

    func bootstrap() async {
        await loadProducts()
        await retryPendingBackendReportIfNeeded()
        await refreshEntitlements(reportToBackend: true)
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            // Sort by price ascending so UI displays Tier1 → Tier3
            products = loaded.sorted { $0.price < $1.price }
            if loaded.isEmpty {
#if DEBUG
                lastErrorMessage = NSLocalizedString(
                    "supporter.products_missing.debug",
                    value: "StoreKit returned no subscription products. For local runs, attach EatometerSupporters.storekit to the Eatometer scheme. For TestFlight or App Store builds, create the matching subscriptions in App Store Connect.",
                    comment: "Debug hint when StoreKit returns no supporter products"
                )
#else
                lastErrorMessage = NSLocalizedString(
                    "supporter.products_missing",
                    value: "StoreKit returned no subscription products for this build.",
                    comment: "Empty supporter products message"
                )
#endif
            } else {
                lastErrorMessage = nil
            }
        } catch {
            lastErrorMessage = String(describing: error)
            print("SupporterService.loadProducts failed: \(error)")
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseInProgress = true
        lastErrorMessage = nil
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await applyTransaction(transaction, reportToBackend: true)
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastErrorMessage = String(describing: error)
            print("SupporterService.purchase failed: \(error)")
            return false
        }
    }

    func restorePurchases() async {
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            try await AppStore.sync()
        } catch {
            lastErrorMessage = String(describing: error)
            print("SupporterService.restorePurchases sync failed: \(error)")
        }
        await refreshEntitlements(reportToBackend: true)
    }

    func manageSubscriptions() async {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            print("SupporterService.manageSubscriptions failed: \(error)")
        }
        #endif
    }

    func refreshEntitlements(reportToBackend: Bool) async {
        var bestActive: (transaction: Transaction, tier: Tier)?
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard let tier = Self.tier(for: transaction.productID) else { continue }
            if let revoked = transaction.revocationDate, revoked <= Date() {
                continue
            }
            if let expires = transaction.expirationDate, expires <= Date() {
                continue
            }
            purchased.insert(transaction.productID)
            if let current = bestActive {
                // Pick the highest tier (sorted by enum order)
                if priority(of: tier) > priority(of: current.tier) {
                    bestActive = (transaction, tier)
                }
            } else {
                bestActive = (transaction, tier)
            }
        }

        purchasedProductIDs = purchased
        activeTier = bestActive?.tier
        activeExpiresAt = bestActive?.transaction.expirationDate

        if reportToBackend {
            await reportEntitlement(bestActive?.transaction, tier: bestActive?.tier)
        }
    }

    // MARK: - Private

    private func priority(of tier: Tier) -> Int {
        switch tier {
        case .tier1: return 1
        case .tier2: return 2
        case .tier3: return 3
        }
    }

    private func makeTransactionListener() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.applyTransaction(transaction, reportToBackend: true)
                    await transaction.finish()
                } catch {
                    await MainActor.run {
                        self.lastErrorMessage = String(describing: error)
                    }
                }
            }
        }
    }

    private func applyTransaction(_ transaction: Transaction, reportToBackend: Bool) async {
        await refreshEntitlements(reportToBackend: reportToBackend)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }

    private func reportEntitlement(_ transaction: Transaction?, tier: Tier?) async {
        let report = makeBackendReport(transaction: transaction, tier: tier)

        if shouldDeduplicateBackendReports, report.deduplicationKey == lastReportedTransactionKey {
            return
        }

        pendingBackendReport = report

        let (success, error) = await sendBackendReport(report)
        if success {
            if shouldDeduplicateBackendReports {
                lastReportedTransactionKey = report.deduplicationKey
            }
            pendingBackendReport = nil
            return
        }

        lastErrorMessage = error
        if let error {
            print("SupporterService.reportEntitlement failed: \(error)")
        }
    }

    private func retryPendingBackendReportIfNeeded() async {
        guard let report = pendingBackendReport else { return }

        let (success, error) = await sendBackendReport(report)
        if success {
            if shouldDeduplicateBackendReports {
                lastReportedTransactionKey = report.deduplicationKey
            }
            pendingBackendReport = nil
            return
        }

        lastErrorMessage = error
        if let error {
            print("SupporterService.retryPendingBackendReportIfNeeded failed: \(error)")
        }
    }

    private func makeBackendReport(transaction: Transaction?, tier: Tier?) -> PendingBackendReport {
        if let transaction, let tier {
            return PendingBackendReport(
                active: true,
                tier: tier.rawValue,
                productID: transaction.productID,
                originalTransactionID: String(transaction.originalID),
                expiresAt: transaction.expirationDate,
                appID: Self.appID
            )
        }

        return PendingBackendReport(
            active: false,
            tier: "",
            productID: "",
            originalTransactionID: "",
            expiresAt: nil,
            appID: Self.appID
        )
    }

    private func sendBackendReport(_ report: PendingBackendReport) async -> (Bool, String?) {
        guard let userService else {
            return (false, "User service unavailable")
        }

        return await userService.setSupporterStatus(
            active: report.active,
            tier: report.tier,
            productID: report.productID,
            originalTransactionID: report.originalTransactionID,
            expiresAt: report.expiresAt,
            appID: report.appID
        )
    }
}
