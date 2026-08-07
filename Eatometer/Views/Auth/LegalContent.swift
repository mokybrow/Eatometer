import Foundation

enum LegalMarkdownContext {
    case auth
    case onboarding
}

enum LegalContent {
    static let publicURL = URL(string: "https://goeatometer.com/legal")!

    static func markdown(for context: LegalMarkdownContext) -> String {
        let link = "[\(legalInformationText)](\(publicURL.absoluteString))"

        switch (currentLanguage, context) {
        case (.ru, .auth):
            return "Продолжая, вы соглашаетесь с \(link)."
        case (.ru, .onboarding):
            return "Нажимая Далее, вы соглашаетесь с \(link)."
        case (.en, .auth):
            return "By continuing, you agree to the \(link)."
        case (.en, .onboarding):
            return "By tapping Next, you agree to the \(link)."
        }
    }

    static var legalInformationTitle: String {
        switch currentLanguage {
        case .ru:
            return "Юридическая информация"
        case .en:
            return "Legal information"
        }
    }

    private static var legalInformationText: String {
        switch currentLanguage {
        case .ru:
            return "Юридической информацией"
        case .en:
            return "legal information"
        }
    }

    private enum Language {
        case en
        case ru
    }

    private static var currentLanguage: Language {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("ru") ? .ru : .en
    }
}
