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
    @Published private(set) var pendingEmailConfirmationToken: String?
    @Published private(set) var pendingResetPasswordToken: String?

    func receive(_ url: URL) {
        if let token = resetPasswordToken(from: url) {
            pendingResetPasswordToken = token
            return
        }

        if let token = emailConfirmationToken(from: url) {
            pendingEmailConfirmationToken = token
            return
        }

        pendingURL = url
    }

    func clear() {
        pendingURL = nil
    }

    func consumeEmailConfirmationToken(_ token: String) {
        guard pendingEmailConfirmationToken == token else { return }
        pendingEmailConfirmationToken = nil
    }

    func consumeResetPasswordToken(_ token: String) {
        guard pendingResetPasswordToken == token else { return }
        pendingResetPasswordToken = nil
    }

    private func emailConfirmationToken(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased() ?? ""
        let route: String

        if scheme == "eatometer" {
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            route = path.isEmpty ? host : path
        } else if scheme == "https", host == "goeatometer.com" {
            route = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        } else {
            return nil
        }

        guard ["confirm-email", "confirm_email", "confirmemail"].contains(route),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }

        return token
    }

    private func resetPasswordToken(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased() ?? ""
        let route: String

        if scheme == "eatometer" {
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            route = path.isEmpty ? host : path
        } else if scheme == "https", host == "goeatometer.com" {
            route = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        } else {
            return nil
        }

        guard ["reset-password", "reset_password", "resetpassword"].contains(route),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }

        return token
    }
}
