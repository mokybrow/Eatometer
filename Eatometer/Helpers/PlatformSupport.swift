import SwiftUI
import UIKit

enum PlatformSupport {
    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) else {
            return
        }
        UIApplication.shared.open(url)
    }

    static func dismissActiveInput() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    static func copyToClipboard(_ value: String) {
        UIPasteboard.general.string = value
    }
}

enum PlatformFeedback {
    static func performSoftImpact() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.85)
    }
}

extension Color {
    static var platformSystemBackground: Color {
        Color(uiColor: .systemBackground)
    }

    static var platformSystemGroupedBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    static var platformSecondarySystemBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    static var platformSecondarySystemGroupedBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    static var platformTertiarySystemBackground: Color {
        Color(uiColor: .tertiarySystemBackground)
    }

    static var platformSeparator: Color {
        Color(uiColor: .separator)
    }

    static var platformSystemGray5: Color {
        Color(uiColor: .systemGray5)
    }

    static var platformSystemGray6: Color {
        Color(uiColor: .systemGray6)
    }
}