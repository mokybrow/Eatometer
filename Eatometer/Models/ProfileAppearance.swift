import Foundation
import SwiftUI

struct ProfileAppearance: Codable, Equatable {
    enum MonogramStyle: String, CaseIterable, Codable, Identifiable {
        case classic
        case rounded
        case serif
        case mono

        var id: String { rawValue }

        var title: String {
            switch self {
            case .classic: return NSLocalizedString("profile.appearance.style.classic", comment: "Classic profile appearance style")
            case .rounded: return NSLocalizedString("profile.appearance.style.rounded", comment: "Rounded profile appearance style")
            case .serif: return NSLocalizedString("profile.appearance.style.serif", comment: "Serif profile appearance style")
            case .mono: return NSLocalizedString("profile.appearance.style.mono", comment: "Monospace profile appearance style")
            }
        }

        func font(size: CGFloat) -> Font {
            switch self {
            case .classic:
                return .system(size: size, weight: .bold, design: .default)
            case .rounded:
                return .system(size: size, weight: .bold, design: .rounded)
            case .serif:
                return .system(size: size, weight: .bold, design: .serif)
            case .mono:
                return .system(size: size, weight: .bold, design: .monospaced)
            }
        }
    }

    enum BackgroundStyle: String, CaseIterable, Codable, Identifiable {
        case cyan
        case blue
        case indigo
        case green
        case orange
        case pink
        case purple
        case teal

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .cyan: return .cyan.opacity(0.82)
            case .blue: return .blue.opacity(0.82)
            case .indigo: return .indigo.opacity(0.82)
            case .green: return .green.opacity(0.82)
            case .orange: return .orange.opacity(0.82)
            case .pink: return .pink.opacity(0.82)
            case .purple: return .purple.opacity(0.82)
            case .teal: return .teal.opacity(0.82)
            }
        }
    }

    var emoji: String?
    var monogramStyle: MonogramStyle
    var backgroundStyle: BackgroundStyle

    static let `default` = ProfileAppearance(
        emoji: nil,
        monogramStyle: .classic,
        backgroundStyle: .cyan
    )
}

enum ProfileAppearanceStore {
    private static let keyPrefix = "Eatometer.profileAppearance."

    static func load(userID: String?) -> ProfileAppearance {
        guard let userID, !userID.isEmpty else { return .default }
        guard let data = UserDefaults.standard.data(forKey: keyPrefix + userID),
              let appearance = try? JSONDecoder().decode(ProfileAppearance.self, from: data)
        else {
            return .default
        }
        return appearance
    }

    static func save(_ appearance: ProfileAppearance, userID: String?) {
        guard let userID, !userID.isEmpty,
              let data = try? JSONEncoder().encode(appearance)
        else {
            return
        }
        UserDefaults.standard.set(data, forKey: keyPrefix + userID)
    }
}