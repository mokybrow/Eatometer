import SwiftUI

struct SetPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var userService: UserService

    let showsCloseButton: Bool

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isNewPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                    placeholder: "profile.password.set.new_placeholder",
                    text: $newPassword,
                    isVisible: $isNewPasswordVisible
                )
                PasswordInputField(
                    placeholder: "profile.password.set.confirm_placeholder",
                    text: $confirmPassword,
                    isVisible: $isConfirmPasswordVisible
                )
            } footer: {
                if let footerErrorMessage {
                    Text(footerErrorMessage)
                        .foregroundStyle(.red)
                } else {
                    Text(PasswordPolicy.requirementsText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text("profile.password.set.title"))
        .navigationBarTitleDisplayMode(.inline)
        .dismissesKeyboardInteractively()
        .onChange(of: newPassword) { _, _ in
            errorMessage = nil
        }
        .onChange(of: confirmPassword) { _, _ in
            errorMessage = nil
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
                    Button(action: submit) {
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
        !newPassword.isEmpty && !confirmPassword.isEmpty && passwordValidationMessage == nil && passwordsMatch
    }

    private var passwordsMatch: Bool {
        newPassword == confirmPassword
    }

    private var passwordValidationMessage: String? {
        guard !newPassword.isEmpty else { return nil }
        return PasswordPolicy.validationError(for: newPassword)
    }

    private var mismatchMessage: String? {
        guard !confirmPassword.isEmpty && !passwordsMatch else { return nil }
        return NSLocalizedString("profile.password.set.mismatch", comment: "Set password mismatch error")
    }

    private var footerErrorMessage: String? {
        errorMessage ?? passwordValidationMessage ?? mismatchMessage
    }

    private func submit() {
        if let passwordValidationMessage {
            errorMessage = passwordValidationMessage
            return
        }
        guard passwordsMatch else {
            errorMessage = NSLocalizedString("profile.password.set.mismatch", comment: "Set password mismatch error")
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            let ok = await authService.setPassword(newPassword: newPassword)
            await MainActor.run {
                isLoading = false
                if ok {
                    Task { await userService.fetchCurrentUser() }
                    dismiss()
                } else {
                    errorMessage = NSLocalizedString("profile.password.set.failed", comment: "Set password failed error")
                }
            }
        }
    }
}