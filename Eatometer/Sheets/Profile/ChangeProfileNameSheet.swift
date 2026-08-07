import SwiftUI

struct ChangeProfileNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userService: UserService

    let showsCloseButton: Bool

    @State private var firstName: String
    @State private var lastName: String
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let initialFirstName: String
    private let initialLastName: String

    init(initialFirstName: String = "", initialLastName: String = "", showsCloseButton: Bool = true) {
        let trimmedFirstName = initialFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = initialLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.initialFirstName = trimmedFirstName
        self.initialLastName = trimmedLastName
        self.showsCloseButton = showsCloseButton
        _firstName = State(initialValue: trimmedFirstName)
        _lastName = State(initialValue: trimmedLastName)
    }

    private var normalizedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        normalizedFirstName != initialFirstName || normalizedLastName != initialLastName
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
            Section(header: Text("profile.name.label")) {
                TextField(
                    "",
                    text: $firstName,
                    prompt: Text("profile.name.first.placeholder").foregroundColor(.secondary)
                )
                .textInputAutocapitalization(.words)

                TextField(
                    "",
                    text: $lastName,
                    prompt: Text("profile.name.last.placeholder").foregroundColor(.secondary)
                )
                .textInputAutocapitalization(.words)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(Text("profile.name.title"))
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

    private func submit() {
        isLoading = true
        errorMessage = nil

        Task {
            let (ok, error) = await userService.setProfileName(
                firstName: normalizedFirstName,
                lastName: normalizedLastName
            )

            await MainActor.run {
                isLoading = false
                if ok {
                    dismiss()
                } else {
                    errorMessage = error ?? NSLocalizedString("profile.name.failed", comment: "Profile name update failed")
                }
            }
        }
    }
}