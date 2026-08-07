import SwiftUI

struct UsernameLoginView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var diaryService: FoodDiaryService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private let onResetCodeSent: (() -> Void)?
    private let onPasswordResetSuccess: (() -> Void)?

    @State private var username: String
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showForgotPasswordHint = false
    @State private var isShowingResetPassword = false
    @FocusState private var focusField: Field?

    init(prefilledUsername: String = "") {
        _username = State(initialValue: prefilledUsername)
        self.onResetCodeSent = nil
        self.onPasswordResetSuccess = nil
    }

    init(prefilledUsername: String = "", onResetCodeSent: (() -> Void)? = nil, onPasswordResetSuccess: (() -> Void)? = nil) {
        _username = State(initialValue: prefilledUsername)
        self.onResetCodeSent = onResetCodeSent
        self.onPasswordResetSuccess = onPasswordResetSuccess
    }

    private enum Field {
        case username
        case password
    }

    private var primaryProgressTint: Color {
        colorScheme == .light ? .black : .white
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("auth.login.username_placeholder", text: $username)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .textContentType(.username)
                .focused($focusField, equals: .username)
                .authInputStyle()

            PasswordInputField(
                placeholder: "auth.login.password_placeholder",
                text: $password,
                isVisible: $isPasswordVisible
            )
                .textContentType(.password)
                .focused($focusField, equals: .password)
                .authInputStyle()
                .submitLabel(.go)
                .onSubmit { submit() }
                .padding(.bottom, 10)

            if let message = errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PressableIconButton(disabled: isSubmitting, action: submit) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(primaryProgressTint)
                        Text("auth.login.submitting")
                            .fontWeight(.semibold)
                    } else {
                        Text("auth.login.submit")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }

            Spacer(minLength: 0)

            Group {
                if showForgotPasswordHint {
                    Button(action: { isShowingResetPassword = true }) {
                        Text("auth.login.forgot_password")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .underline()
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(24)
        .contentShape(Rectangle())
        .onTapGesture { focusField = nil }
        .navigationTitle(Text("auth.login.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                closeButton
            }

            ToolbarItem(placement: .principal) { EmptyView() }
        }
        .navigationDestination(isPresented: $isShowingResetPassword) {
            ResetPasswordView(
                onResetCodeSent: {
                    if let onResetCodeSent {
                        onResetCodeSent()
                    } else {
                        dismiss()
                    }
                },
                onPasswordResetSuccess: {
                    if let onPasswordResetSuccess {
                        onPasswordResetSuccess()
                    } else {
                        dismiss()
                    }
                }
            )
        }
    }

    private func submit() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            errorMessage = NSLocalizedString("auth.login.empty_credentials", comment: "Login empty credentials error")
            showForgotPasswordHint = false
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                _ = try await authService.login(username: trimmedUsername, password: password)
                await userService.fetchCurrentUser()
                diaryService.setScope(userID: userService.currentUserID)
                Task {
                    await diaryService.warmUpNutritionStatistics()
                }
                await MainActor.run {
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = mapError(error)
                    showForgotPasswordHint = true
                }
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
        }
        .disabled(isSubmitting)
        .accessibilityLabel(Text(NSLocalizedString("Close", comment: "Login close button")))
    }

    private func mapError(_ error: Error) -> String {
        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("unauthenticated") {
            return NSLocalizedString("auth.login.invalid_credentials", comment: "Invalid credentials error")
        }
        return NSLocalizedString("auth.login.failed", comment: "Login failed error")
    }
}
