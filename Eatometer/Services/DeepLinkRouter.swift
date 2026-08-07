import Combine
import Foundation

struct PendingMealQuickAdd: Hashable {
    enum Kind: String {
        case product
        case recipe
        case mealTemplate = "meal_template"
    }

    let kind: Kind
    let id: UUID
}

@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published private(set) var pendingURL: URL?
    @Published var pendingMealID: UUID?
    @Published var pendingMealSlotID: String?
    @Published var pendingMealQuickAdd: PendingMealQuickAdd?
    @Published var pendingOpenWater = false
    @Published var pendingOpenMeals = false
    /// Habit to open — the habit detail is a sheet, so it can't be pushed onto
    /// the navigation path like the other destinations.
    @Published var pendingHabitID: UUID?

    func receive(_ url: URL) {
        pendingURL = url
    }

    func clear() {
        pendingURL = nil
    }

}
