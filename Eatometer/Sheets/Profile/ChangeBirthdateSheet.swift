import SwiftUI

struct ChangeBirthdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userService: UserService

    let onSaveResult: (Date, Bool, String?) -> Void
    let showsCloseButton: Bool

    @State private var draftBirthdate: Date
    @State private var initialBirthdate: Date
    @State private var isLoading = false

    init(initialBirthdate: Date, showsCloseButton: Bool = true, onSaveResult: @escaping (Date, Bool, String?) -> Void) {
        self.onSaveResult = onSaveResult
        self.showsCloseButton = showsCloseButton
        _draftBirthdate = State(initialValue: initialBirthdate)
        _initialBirthdate = State(initialValue: initialBirthdate)
    }

    private var hasChanges: Bool {
        !Calendar.current.isDate(draftBirthdate, inSameDayAs: initialBirthdate)
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("profile.birthdate.select", selection: $draftBirthdate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .padding(20)
        }
        .scrollDisabled(true)
        .navigationTitle(Text("profile.birthdate.title"))
        .navigationBarTitleDisplayMode(.inline)
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
                    .disabled(!hasChanges)
                    .opacity(hasChanges ? 1 : 0.45)
                }
            }
        }
    }

    private func submit() {
        isLoading = true
        Task {
            let result = await userService.setBirthdate(draftBirthdate)
            await MainActor.run {
                isLoading = false
                if result.0 {
                    UserDefaults.standard.set(draftBirthdate.timeIntervalSince1970, forKey: "userBirthdate")
                }
                onSaveResult(draftBirthdate, result.0, result.1)
                dismiss()
            }
        }
    }
}