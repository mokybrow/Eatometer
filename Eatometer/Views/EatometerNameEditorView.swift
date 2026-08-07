import SwiftUI

struct EatometerNameEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userService: UserService

    @State private var name: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let initialName: String

    init(name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        initialName = value
        _name = State(initialValue: value)
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !normalizedName.isEmpty && normalizedName != initialName && !isSaving
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.headerSpacing) {
                EOCard {
                    EOTextFieldRow("profile.name.label", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)

                    EORowSeparator()
                    EOInlineActionRow("common.save", isEnabled: canSave, action: save)
                }

                Text("profile.name.help")
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
                    .padding(.top, 4)

                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(EOTheme.Typography.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, EOTheme.Metrics.cardInset)
                }
            }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .eoPageBackground()
        .navigationTitle("profile.name.label")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isSaving {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil

        Task {
            let result = await userService.updateName(normalizedName)
            isSaving = false
            if result.0 {
                dismiss()
            } else {
                errorMessage = result.1 ?? NSLocalizedString("profile.name.failed", comment: "Name update failed")
            }
        }
    }
}
