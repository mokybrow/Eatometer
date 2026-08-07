import SwiftUI

struct ChangeEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var userService: UserService

    let showsCloseButton: Bool

    @State private var email: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showConfirmStep = false
    @State private var confirmLoading = false
    @State private var confirmError: String?
    @State private var resendDisabledUntil: Date?
    @State private var codeDigits: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedField: Int?

    var onSent: ((Bool) -> Void)? = nil

    init(showsCloseButton: Bool = true, onSent: ((Bool) -> Void)? = nil) {
        self.showsCloseButton = showsCloseButton
        self.onSent = onSent
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
                TextField("", text: $email, prompt: Text("profile.email.placeholder").foregroundColor(.secondary))
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundColor(.red) }
            }

            if showConfirmStep {
                Section {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            ForEach(0..<6, id: \.self) { index in
                                TextField("", text: $codeDigits[index])
                                    .multilineTextAlignment(.center)
                                    .font(.title2)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .frame(width: 44, height: 56)
                                    .background(Color(.secondarySystemFill))
                                    .cornerRadius(8)
                                    .focused($focusedField, equals: index)
                                    .onChange(of: codeDigits[index]) { _, newValue in
                                        let filtered = newValue.filter { $0.isNumber }
                                        let digit = String(filtered.prefix(1))
                                        if digit != newValue {
                                            codeDigits[index] = digit
                                        }
                                        if digit.count == 1 {
                                            focusedField = index < 5 ? index + 1 : nil
                                        } else if digit.isEmpty, index > 0 {
                                            focusedField = index - 1
                                        }
                                    }
                            }
                        }

                        if let confirmError { Text(confirmError).foregroundColor(.red) }

                        Button(action: { Task { await confirmCode() } }) {
                            if confirmLoading { ProgressView() }
                            else { Text("profile.email.confirm").frame(maxWidth: .infinity) }
                        }
                        .disabled(confirmLoading || combinedCode.count < 6)

                        Button(action: { Task { await resendCode() } }) {
                            Text("profile.email.resend")
                        }
                        .disabled(resendDisabled)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !showConfirmStep {
                primaryActionButton
                    .padding(.horizontal, 38)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .navigationTitle(Text("profile.email.change.title"))
        .navigationBarTitleDisplayMode(.inline)
        .dismissesKeyboardInteractively()
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
        }
    }

    private var initialButtonTitle: String {
        return NSLocalizedString("profile.email.change.action", comment: "Change email action")
    }

    private var primaryActionDisabled: Bool {
        isLoading || !isValidEmail(email)
    }

    private var primaryActionButton: some View {
        PressableIconButton(
            disabled: primaryActionDisabled,
            action: { Task { await sendConfirmation() } }
        ) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Image(systemName: "envelope.badge")
                        .font(.title3.weight(.semibold))
                }

                Text(initialButtonTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            .padding(.horizontal, 20)
            .contentShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .opacity(primaryActionDisabled ? 0.55 : 1)
        .accessibilityLabel(Text(initialButtonTitle))
    }

    private var combinedCode: String { codeDigits.joined() }

    private var resendDisabled: Bool {
        if let resendDisabledUntil { return Date() < resendDisabledUntil }
        return false
    }

    private func isValidEmail(_ value: String) -> Bool {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.contains("@") && email.contains(".")
    }

    private func sendConfirmation() async {
        errorMessage = nil
        isLoading = true
        let ok = await authService.initiateChangeEmail(newEmail: email)

        await MainActor.run {
            isLoading = false
            if ok {
                showConfirmStep = true
                startResendCooldown()
                focusedField = 0
                codeDigits = Array(repeating: "", count: 6)
            } else {
                errorMessage = NSLocalizedString("profile.email.send_failed", comment: "Email confirmation send failed error")
            }
        }
    }

    private func confirmCode() async {
        confirmError = nil
        confirmLoading = true
        let code = combinedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await authService.confirmChangeEmail(code: code)
        await MainActor.run {
            confirmLoading = false
        }

        if ok {
            await userService.fetchCurrentUser()
            await MainActor.run {
                onSent?(true)
                dismiss()
            }
        } else {
            await MainActor.run {
                confirmError = NSLocalizedString("profile.email.confirm_failed", comment: "Email confirmation failed error")
            }
        }
    }

    private func resendCode() async {
        codeDigits = Array(repeating: "", count: 6)
        await sendConfirmation()
        focusedField = 0
    }

    private func startResendCooldown() {
        resendDisabledUntil = Date().addingTimeInterval(30)
        Task {
            try? await Task.sleep(for: .seconds(30))
            await MainActor.run {
                resendDisabledUntil = nil
            }
        }
    }
}
