import SwiftUI

struct PasswordInputField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: isVisible ? Self.hidePasswordTitle : Self.showPasswordTitle))
        }
    }

    private static let showPasswordTitle = NSLocalizedString(
        "profile.password.visibility.show",
        tableName: nil,
        bundle: .main,
        value: "Show password",
        comment: "Password visibility toggle label"
    )

    private static let hidePasswordTitle = NSLocalizedString(
        "profile.password.visibility.hide",
        tableName: nil,
        bundle: .main,
        value: "Hide password",
        comment: "Password visibility toggle label"
    )
}

enum PasswordPolicy {
    static let minimumLength = 8

    static let requirementsText = NSLocalizedString(
        "profile.password.rules",
        tableName: nil,
        bundle: .main,
        value: "Use at least 8 characters, uppercase and lowercase letters, and a number.",
        comment: "Password requirements hint"
    )

    static func validationError(for password: String, currentPassword: String? = nil) -> String? {
        if password.count < minimumLength {
            return NSLocalizedString(
                "profile.password.error.short",
                tableName: nil,
                bundle: .main,
                value: "Password must be at least 8 characters.",
                comment: "Password too short validation error"
            )
        }

        let hasUppercase = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLowercase = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil

        guard hasUppercase && hasLowercase && hasNumber else {
            return NSLocalizedString(
                "profile.password.error.weak",
                tableName: nil,
                bundle: .main,
                value: "Password must include uppercase and lowercase letters and a number.",
                comment: "Weak password validation error"
            )
        }

        if let currentPassword, !currentPassword.isEmpty, password == currentPassword {
            return NSLocalizedString(
                "profile.password.error.same_as_current",
                tableName: nil,
                bundle: .main,
                value: "New password must be different from the current password.",
                comment: "Same password validation error"
            )
        }

        return nil
    }
}