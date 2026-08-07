import SwiftUI
import UIKit

extension Color {
    /// Primary brand accent (system blue) driven by the asset
    /// catalog so it also feeds the system `.tint` / `.accentColor`.
    static var appAccent: Color {
        Color("AccentColor")
    }

    /// Secondary "energy" accent (#FE4F2D) used sparingly for action / progress
    /// highlights so the teal-led UI keeps a lively two-tone identity.
    static var appHighlight: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0.996, green: 0.310, blue: 0.176, alpha: 1) // #FE4F2D
                : UIColor(red: 1.000, green: 0.416, blue: 0.298, alpha: 1) // #FF6A4C
        })
    }

    static var appAccentReadableText: Color {
        Color(UIColor { _ in
            UIColor.white
        })
    }

    /// Legacy aliases – both now resolve through the shared design system so
    /// every screen picks up the mock-up palette without further edits.
    static var appCardBackground: Color {
        EOTheme.Palette.card
    }

    static var appPageBackground: Color {
        EOTheme.Palette.pageBackground
    }
}
