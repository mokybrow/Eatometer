import SwiftUI
import GRPCCore

struct RegistrationView: View {
    private enum RegistrationStep: Int, CaseIterable {
        case credentials
        case profile
        case demographics
    }

    private enum DuplicateRegistrationField {
        case email
        case username
        case unknown
    }

    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var diaryService: FoodDiaryService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var selectedSex: User_UserSex = .preferNotToSay
    @State private var registrationStep: RegistrationStep = .credentials
    @State private var stepTransitionDirection = 1
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusField: Field?

    private enum Field {
        case firstName
        case lastName
        case username
        case email
    }

    private var primaryProgressTint: Color {
        colorScheme == .light ? .black : .white
    }

    var body: some View {
        ZStack(alignment: .top) {
            registrationPage
                .id(registrationStep)
                .transition(stepTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .navigationTitle(Text("auth.registration.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { EmptyView() }
            ToolbarItem(placement: .topBarLeading) {
                if registrationStep == .credentials {
                    closeButton
                } else {
                    backChevronButton
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
        .accessibilityLabel(Text(NSLocalizedString("Close", comment: "Registration close button")))
    }

    private var registrationPage: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    stepContent

                    if let message = errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dismissesKeyboardInteractively()

            VStack(spacing: 10) {
                bottomActionButton
                registrationLegalText
            }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
    }

    private var backChevronButton: some View {
        Button(action: handleBackAction) {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
        }
        .disabled(isSubmitting)
        .accessibilityLabel(Text(NSLocalizedString("Back", comment: "Registration back button")))
    }

    private var stepTransition: AnyTransition {
        let insertionEdge: Edge = stepTransitionDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = stepTransitionDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private var stepContent: some View {
        switch registrationStep {
        case .credentials:
            credentialsStep
        case .profile:
            profileStep
        case .demographics:
            demographicsStep
        }
    }

    private var credentialsStep: some View {
        VStack(spacing: 10) {
            TextField("auth.registration.email_placeholder", text: $email)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .focused($focusField, equals: .email)
                .authInputStyle()

            PasswordInputField(
                placeholder: "auth.registration.password_placeholder",
                text: $password,
                isVisible: $isPasswordVisible
            )
            .textContentType(.newPassword)
            .authInputStyle()

            PasswordInputField(
                placeholder: "auth.registration.confirm_password_placeholder",
                text: $confirmPassword,
                isVisible: $isConfirmPasswordVisible
            )
            .textContentType(.newPassword)
            .authInputStyle()
        }
    }

    private var profileStep: some View {
        VStack(spacing: 10) {
            TextField("auth.registration.username_placeholder", text: $username)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .textContentType(.username)
                .focused($focusField, equals: .username)
                .authInputStyle()

            TextField("profile.name.last.placeholder", text: $lastName)
                .textContentType(.familyName)
                .focused($focusField, equals: .lastName)
                .authInputStyle()

            TextField("profile.name.first.placeholder", text: $firstName)
                .textContentType(.givenName)
                .focused($focusField, equals: .firstName)
                .authInputStyle()
        }
    }

    private var demographicsStep: some View {
        VStack(spacing: 10) {
            Menu {
                ForEach(Self.sexOptions) { option in
                    Button(option.title) {
                        selectedSex = option.value
                    }
                }
            } label: {
                HStack {
                    Text(NSLocalizedString("onboarding.field.sex", comment: "Sex field title"))
                    Spacer()
                    Text(displayName(for: selectedSex))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .tint(.primary)
            .authInputStyle()

        }
    }

    private var bottomActionButton: some View {
        PressableIconButton(disabled: isSubmitting, action: handlePrimaryAction) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(primaryProgressTint)
                    Text("auth.registration.submitting")
                        .fontWeight(.semibold)
                } else {
                    Text(primaryActionTitle)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
    }

    private var registrationLegalText: some View {
        let markdown = LegalContent.markdown(for: .auth)
        let attributedText = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)

        return Text(attributedText)
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var primaryActionTitle: LocalizedStringKey {
        switch registrationStep {
        case .credentials, .profile:
            return "auth.registration.next"
        case .demographics:
            return "auth.registration.submit"
        }
    }

    private func handlePrimaryAction() {
        switch registrationStep {
        case .credentials:
            advanceFromCredentials()
        case .profile:
            advanceFromProfile()
        case .demographics:
            submit()
        }
    }

    private func handleBackAction() {
        guard !isSubmitting else { return }
        errorMessage = nil
        focusField = nil

        switch registrationStep {
        case .credentials:
            dismiss()
        case .profile:
            setRegistrationStep(.credentials)
        case .demographics:
            setRegistrationStep(.profile)
        }
    }

    private func setRegistrationStep(_ step: RegistrationStep) {
        guard step != registrationStep else { return }
        stepTransitionDirection = step.rawValue > registrationStep.rawValue ? 1 : -1
        withAnimation(.easeInOut(duration: 0.28)) {
            registrationStep = step
        }
    }

    private func advanceFromCredentials() {
        guard validateCredentialsStep() else { return }
        errorMessage = nil
        focusField = .username
        setRegistrationStep(.profile)
    }

    private func advanceFromProfile() {
        guard validateProfileStep() else { return }
        errorMessage = nil
        focusField = nil
        setRegistrationStep(.demographics)
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard validateCredentialsStep() else {
            setRegistrationStep(.credentials)
            return
        }
        guard validateProfileStep() else {
            setRegistrationStep(.profile)
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                _ = try await authService.register(email: trimmedEmail, username: trimmedUsername, password: password)
                if !trimmedFirstName.isEmpty || !trimmedLastName.isEmpty {
                    _ = await userService.setProfileName(firstName: trimmedFirstName, lastName: trimmedLastName)
                }
                _ = await userService.setSex(selectedSex)
                await userService.fetchCurrentUser()
                diaryService.setScope(userID: userService.currentUserID)
                diaryService.requireCalorieOnboardingForNewAccount()
                await MainActor.run {
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = mapError(error)
                    switch duplicateRegistrationField(for: error) {
                    case .email:
                        setRegistrationStep(.credentials)
                    case .username:
                        setRegistrationStep(.profile)
                    case .unknown:
                        if isDuplicateAccountError(error) {
                            setRegistrationStep(.credentials)
                        }
                    }
                }
            }
        }
    }

    private func isDuplicateAccountError(_ error: Error) -> Bool {
        if let rpcError = error as? RPCError, rpcError.code == .alreadyExists {
            return true
        }

        let nsError = error as NSError
        let localized = error.localizedDescription.lowercased()
        let described = String(describing: error).lowercased()
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription.lowercased() ?? ""
        let all = [localized, described, underlying].joined(separator: " | ")

        if all.contains("email already in use")
            || all.contains("email already taken")
            || all.contains("username already in use")
            || all.contains("already exists")
            || all.contains("alreadyexists")
            || all.contains("grpc_code\":\"alreadyexists")
            || all.contains("status: alreadyexists")
            || all.contains("code: alreadyexists") {
            return true
        }

        return (all.contains("email") && (all.contains("exist") || all.contains("taken") || all.contains("duplicate")))
            || (all.contains("username") && (all.contains("exist") || all.contains("taken") || all.contains("in use")))
            || all.contains("duplicate")
            || (all.contains("user") && all.contains("exist"))
    }

    private func mapError(_ error: Error) -> String {
        let message: String
        switch duplicateRegistrationField(for: error) {
        case .username:
            message = NSLocalizedString("auth.registration.username_taken", comment: "Registration username taken error")
        case .email:
            message = NSLocalizedString("auth.registration.email_exists", comment: "Registration email exists error")
        case .unknown:
            let lowered = error.localizedDescription.lowercased()
            if isDuplicateAccountError(error) {
                if lowered.contains("username") || lowered.contains("user already") {
                    message = NSLocalizedString("auth.registration.username_taken", comment: "Registration username taken error")
                } else {
                    message = NSLocalizedString("auth.registration.email_exists", comment: "Registration email exists error")
                }
            } else if lowered.contains("taken") {
                message = NSLocalizedString("auth.registration.taken", comment: "Registration taken error")
            } else {
                message = NSLocalizedString("auth.registration.failed", comment: "Registration failed error")
            }
        }
        return message.isEmpty ? NSLocalizedString("auth.registration.failed", comment: "Registration failed error") : message
    }

    private func duplicateRegistrationField(for error: Error) -> DuplicateRegistrationField {
        guard isDuplicateAccountError(error) else {
            return .unknown
        }

        let nsError = error as NSError
        let localized = error.localizedDescription.lowercased()
        let described = String(describing: error).lowercased()
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription.lowercased() ?? ""
        let all = [localized, described, underlying].joined(separator: " | ")

        if all.contains("username") || all.contains("user already") {
            return .username
        }
        if all.contains("email") {
            return .email
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return duplicateRegistrationField(for: underlyingError)
        }

        return .unknown
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.contains("@") && email.contains(".")
    }

    private func validateCredentialsStep() -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmedEmail) else {
            errorMessage = NSLocalizedString("auth.registration.email_invalid", comment: "Registration invalid email error")
            return false
        }
        guard password.count >= 6 else {
            errorMessage = NSLocalizedString("auth.registration.password_short", comment: "Registration short password error")
            return false
        }
        guard password == confirmPassword else {
            errorMessage = NSLocalizedString("auth.registration.password_mismatch", comment: "Registration password mismatch error")
            return false
        }
        return true
    }

    private func validateProfileStep() -> Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            errorMessage = NSLocalizedString("auth.registration.username_required", comment: "Registration username required error")
            return false
        }
        return true
    }

    private func displayName(for sex: User_UserSex) -> String {
        switch normalizedSex(sex) {
        case .male:
            return NSLocalizedString("onboarding.sex.male.title", comment: "Male sex option")
        case .female:
            return NSLocalizedString("onboarding.sex.female.title", comment: "Female sex option")
        case .preferNotToSay:
            return NSLocalizedString("onboarding.sex.not_set.title", comment: "Prefer not to say sex option")
        default:
            return NSLocalizedString("onboarding.sex.not_set.title", comment: "Prefer not to say sex option")
        }
    }

    private func normalizedSex(_ sex: User_UserSex) -> User_UserSex {
        switch sex {
        case .male, .female, .preferNotToSay:
            return sex
        default:
            return .preferNotToSay
        }
    }

    private static let sexOptions: [RegistrationSexOption] = [
        RegistrationSexOption(id: "male", value: .male, title: NSLocalizedString("onboarding.sex.male.title", comment: "Male sex option")),
        RegistrationSexOption(id: "female", value: .female, title: NSLocalizedString("onboarding.sex.female.title", comment: "Female sex option")),
        RegistrationSexOption(id: "prefer_not_to_say", value: .preferNotToSay, title: NSLocalizedString("onboarding.sex.not_set.title", comment: "Prefer not to say sex option"))
    ]
}

private struct RegistrationSexOption: Identifiable {
    let id: String
    let value: User_UserSex
    let title: String
}
