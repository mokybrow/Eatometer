import SwiftUI

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: FoodAuthService
    @State private var isOldPasswordVisible = false
    @State private var isNewPasswordVisible = false
    @State private var isConfirmPasswordVisible = false

    let showsCloseButton: Bool

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    init(showsCloseButton: Bool = true) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        Group {
            if showsCloseButton {
                NavigationStack {
                    content
                }
            } else {
                content
            }
        }
    }

    private var content: some View {
        Form {
            Section {
                PasswordInputField(
                    placeholder: "profile.password.change.current_placeholder",
                    text: $oldPassword,
                    isVisible: $isOldPasswordVisible
                )
                PasswordInputField(
                    placeholder: "profile.password.change.new_placeholder",
                    text: $newPassword,
                    isVisible: $isNewPasswordVisible
                )
                PasswordInputField(
                    placeholder: "profile.password.change.confirm_placeholder",
                    text: $confirmPassword,
                    isVisible: $isConfirmPasswordVisible
                )
            } footer: {
                if let footerErrorMessage {
                    Text(footerErrorMessage).foregroundStyle(.red)
                } else if let successMessage {
                    Text(successMessage).foregroundStyle(.green)
                } else {
                    Text(PasswordPolicy.requirementsText).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text("profile.password.change.title"))
        .navigationBarTitleDisplayMode(.inline)
        .dismissesKeyboardInteractively()
        .onChange(of: oldPassword) { _, _ in
            errorMessage = nil
            successMessage = nil
        }
        .onChange(of: newPassword) { _, _ in
            errorMessage = nil
            successMessage = nil
        }
        .onChange(of: confirmPassword) { _, _ in
            errorMessage = nil
            successMessage = nil
        }
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    PressableIconButton(action: { dismiss() }) {
                        Label("common.cancel", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 48, height: 48)
                    }
                    .padding(16)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isLoading {
                    ProgressView()
                } else {
                    Button(action: changePassword) {
                        Label("common.done", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .tint(.accentColor)
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.45)
                }
            }
        }
    }

    private var canSubmit: Bool {
        !oldPassword.isEmpty && !newPassword.isEmpty && !confirmPassword.isEmpty && passwordValidationMessage == nil && passwordsMatch
    }

    private var passwordsMatch: Bool {
        newPassword == confirmPassword
    }

    private var passwordValidationMessage: String? {
        guard !newPassword.isEmpty else { return nil }
        return PasswordPolicy.validationError(for: newPassword, currentPassword: oldPassword)
    }

    private var mismatchMessage: String? {
        guard !confirmPassword.isEmpty && !passwordsMatch else { return nil }
        return NSLocalizedString("profile.password.set.mismatch", comment: "Change password mismatch error")
    }

    private var footerErrorMessage: String? {
        errorMessage ?? passwordValidationMessage ?? mismatchMessage
    }

    private func changePassword() {
        if let passwordValidationMessage {
            errorMessage = passwordValidationMessage
            return
        }
        guard passwordsMatch else {
            errorMessage = NSLocalizedString("profile.password.set.mismatch", comment: "Change password mismatch error")
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        Task {
            let success = await authService.changePassword(old: oldPassword, new: newPassword)
            await MainActor.run {
                isLoading = false
                if success {
                    successMessage = NSLocalizedString("profile.password.change.success", comment: "Change password success message")
                    oldPassword = ""
                    newPassword = ""
                    confirmPassword = ""
                } else {
                    errorMessage = NSLocalizedString("profile.password.change.failed", comment: "Change password failed message")
                }
            }
        }
    }
}