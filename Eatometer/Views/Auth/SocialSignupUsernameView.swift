import SwiftUI

struct SocialSignupUsernameView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var username: String
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var selectedSex: User_UserSex
    let errorMessage: String?
    let isSubmitting: Bool
    let onComplete: () -> Void

    private var primaryProgressTint: Color {
        colorScheme == .light ? .black : .white
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("auth.login.username_placeholder", text: $username)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .textContentType(.username)
                .authInputStyle()

            TextField("profile.name.first.placeholder", text: $firstName)
                .textContentType(.givenName)
                .authInputStyle()

            TextField("profile.name.last.placeholder", text: $lastName)
                .textContentType(.familyName)
                .authInputStyle()

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
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .authInputStyle()

            Text("auth.social.username.hint")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PressableIconButton(disabled: isSubmitting || username.isEmpty, action: onComplete) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(primaryProgressTint)
                        Text("auth.social.username.completing")
                            .fontWeight(.semibold)
                    } else {
                        Text("auth.social.username.complete")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .navigationTitle(Text("auth.social.username.title"))
        .navigationBarTitleDisplayMode(.inline)
        .dismissesKeyboardInteractively()
        .toolbar {
            ToolbarItem(placement: .principal) {
                EmptyView()
            }
        }
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

    private static let sexOptions: [SocialSignupSexOption] = [
        SocialSignupSexOption(id: "male", value: .male, title: NSLocalizedString("onboarding.sex.male.title", comment: "Male sex option")),
        SocialSignupSexOption(id: "female", value: .female, title: NSLocalizedString("onboarding.sex.female.title", comment: "Female sex option")),
        SocialSignupSexOption(id: "prefer_not_to_say", value: .preferNotToSay, title: NSLocalizedString("onboarding.sex.not_set.title", comment: "Prefer not to say sex option"))
    ]
}

private struct SocialSignupSexOption: Identifiable {
    let id: String
    let value: User_UserSex
    let title: String
}
