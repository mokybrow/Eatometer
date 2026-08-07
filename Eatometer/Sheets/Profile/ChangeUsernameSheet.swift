import SwiftUI

struct ChangeUsernameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userService: UserService

    let showsCloseButton: Bool

    @State private var username: String = ""
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
                TextField("", text: $username, prompt: Text("profile.username.placeholder").foregroundColor(.secondary))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundColor(.red) }
            }
        }
        .navigationTitle(Text("profile.username.title"))
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

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = NSLocalizedString("profile.username.empty", comment: "Empty username error")
            return
        }

        isLoading = true
        errorMessage = nil
        Task {
            let (ok, taken, error) = await userService.changeNickname(newNickname: trimmed)
            await MainActor.run {
                isLoading = false
                if ok {
                    dismiss()
                } else if taken {
                    errorMessage = NSLocalizedString("profile.username.taken", comment: "Username taken error")
                } else {
                    errorMessage = error ?? NSLocalizedString("profile.username.failed", comment: "Username update failed error")
                }
            }
        }
    }
}