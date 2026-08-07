import Foundation
import Combine

/// Tracks how often products are added to meals, entirely on-device, so the
/// add-to-meal picker can surface the user's most frequently used products
/// before they type a query. Persisted to `UserDefaults` as JSON; no backend.
@MainActor
final class FrequentProductsStore: ObservableObject {
    static let shared = FrequentProductsStore()

    private struct Entry: Codable {
        var product: ProductSummary
        var count: Int
        var lastUsed: Date
    }

    /// Most frequently used products first (ties broken by recency), capped for display.
    @Published private(set) var products: [ProductSummary] = []

    private var entries: [UUID: Entry] = [:]
    private let storageKey = "frequentProducts.v1"
    /// Upper bound on tracked entries; oldest/least-used replace each other.
    private let maxStored = 10
    /// How many to expose to the UI.
    private let displayLimit = 10
    /// A product only counts as "frequently used" once added at least this many times.
    private let minCount = 2
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.decodeEntries(from: defaults, key: "frequentProducts.v1")
        self.entries = loaded
        self.products = Self.topProducts(from: loaded, limit: 10, minCount: 2)
    }

    /// Call whenever a product is added to a meal.
    func record(_ product: ProductSummary) {
        var entry = entries[product.id] ?? Entry(product: product, count: 0, lastUsed: Date())
        entry.count += 1
        entry.lastUsed = Date()
        entry.product = product // refresh the cached snapshot (name/nutrition may have changed)
        entries[product.id] = entry
        prune()
        persist()
        products = Self.topProducts(from: entries, limit: displayLimit, minCount: minCount)
    }

    /// Wipes the "recently used" list (the "Clear" action in Food Search).
    func clear() {
        entries.removeAll()
        persist()
        products = []
    }

    private func prune() {
        guard entries.count > maxStored else { return }
        let survivors = entries.values.sorted(by: Self.moreRelevant).prefix(maxStored)
        entries = Dictionary(uniqueKeysWithValues: survivors.map { ($0.product.id, $0) })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Array(entries.values)) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func decodeEntries(from defaults: UserDefaults, key: String) -> [UUID: Entry] {
        guard
            let data = defaults.data(forKey: key),
            let stored = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: stored.map { ($0.product.id, $0) })
    }

    private static func topProducts(from entries: [UUID: Entry], limit: Int, minCount: Int) -> [ProductSummary] {
        entries.values
            .filter { $0.count >= minCount }
            .sorted(by: moreRelevant)
            .prefix(limit)
            .map(\.product)
    }

    /// Frequently added first; recency breaks ties.
    private static func moreRelevant(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.lastUsed > rhs.lastUsed
    }
}
