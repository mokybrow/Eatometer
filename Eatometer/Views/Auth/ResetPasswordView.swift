import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @Environment(\.dismiss) private var dismiss
    private let onResetCodeSent: (() -> Void)?
    private let onPasswordResetSuccess: (() -> Void)?

    @State private var email = ""
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var deepLinkCode: String
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isNewPasswordVisible = false
    @State private var isConfirmPasswordVisible = false

    private var isDeepLinkMode: Bool {
        !deepLinkCode.isEmpty
    }

    init(onResetCodeSent: (() -> Void)? = nil, onPasswordResetSuccess: (() -> Void)? = nil) {
        _deepLinkCode = State(initialValue: "")
        self.onResetCodeSent = onResetCodeSent
        self.onPasswordResetSuccess = onPasswordResetSuccess
    }

    init(initialCode: String, onResetCodeSent: (() -> Void)? = nil, onPasswordResetSuccess: (() -> Void)? = nil) {
        _deepLinkCode = State(initialValue: initialCode.trimmingCharacters(in: .whitespacesAndNewlines))
        self.onResetCodeSent = onResetCodeSent
        self.onPasswordResetSuccess = onPasswordResetSuccess
    }

    var body: some View {
        VStack(spacing: 10) {
            if !isDeepLinkMode {
                TextField("auth.reset.email_placeholder", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .authInputStyle()
                    .padding(.bottom, 10)
            }

            if let m = message {
                Text(m)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if !isDeepLinkMode {
                PressableIconButton(disabled: isSubmitting, action: sendReset) {
                    Text(isSubmitting ? "auth.reset.sending_code" : "auth.reset.send_code")
                        .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
            } else {
                PasswordInputField(
                    placeholder: "auth.reset.new_password_placeholder",
                    text: $newPassword,
                    isVisible: $isNewPasswordVisible
                )
                    .authInputStyle()

                PasswordInputField(
                    placeholder: "auth.registration.confirm_password_placeholder",
                    text: $confirmPassword,
                    isVisible: $isConfirmPasswordVisible
                )
                    .authInputStyle()

                PressableIconButton(disabled: isSubmitting, action: submitNewPassword) {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.primary)
                        }

                        Text("common.save")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
            }

            Spacer()
        }
        .padding(24)
        .navigationTitle(Text("auth.reset.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                closeButton
            }

            ToolbarItem(placement: .principal) { EmptyView() }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: isDeepLinkMode ? "xmark" : "chevron.left")
                .font(.body.weight(.semibold))
        }
        .disabled(isSubmitting)
        .accessibilityLabel(Text(NSLocalizedString(isDeepLinkMode ? "Close" : "Back", comment: "Reset password leading button")))
    }

    private func sendReset() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = NSLocalizedString("auth.reset.email_invalid", comment: "Reset password invalid email error")
            return
        }
        isSubmitting = true
        message = nil
        Task {
            do {
                let ok = try await authService.forgotPassword(email: trimmed)
                await MainActor.run {
                    isSubmitting = false
                    if ok {
                        if let onResetCodeSent {
                            onResetCodeSent()
                        } else {
                            dismiss()
                        }
                    } else {
                        message = NSLocalizedString("auth.reset.send_failed", comment: "Reset password send failed message")
                    }
                }
            } catch {
                await MainActor.run {
                    message = NSLocalizedString("auth.reset.send_failed", comment: "Reset password send failed message")
                    isSubmitting = false
                }
            }
        }
    }

    private func submitNewPassword() {
        let codeTrim = deepLinkCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPass = newPassword
        let confirmPass = confirmPassword
        guard !codeTrim.isEmpty else {
            message = NSLocalizedString("Open the reset link from your email and try again.", comment: "Reset password deep-link required error")
            return
        }
        guard newPass.count >= 6 else {
            message = NSLocalizedString("auth.reset.validation_error", comment: "Reset password validation error")
            return
        }
        guard newPass == confirmPass else {
            message = NSLocalizedString("Passwords do not match.", comment: "Reset password validation error")
            return
        }
        isSubmitting = true
        message = nil
        Task {
            let ok = await authService.resetPassword(email: "", code: codeTrim, newPassword: newPass)
            await MainActor.run {
                isSubmitting = false
                if ok {
                    if let onPasswordResetSuccess {
                        onPasswordResetSuccess()
                    } else {
                        message = NSLocalizedString("auth.reset.success", comment: "Reset password success message")
                        dismiss()
                    }
                } else {
                    message = NSLocalizedString("auth.reset.failed", comment: "Reset password failed message")
                }
            }
        }
    }
}
