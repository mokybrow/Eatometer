import SwiftUI

struct ProfileAppearanceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let username: String
    let showsCloseButton: Bool
    let initialAppearance: ProfileAppearance
    let onSave: (ProfileAppearance) -> Void

    @State private var draft: ProfileAppearance
    @State private var emojiInput: String
    @State private var isEmojiFieldFocused = false

    init(username: String, appearance: ProfileAppearance, showsCloseButton: Bool = true, onSave: @escaping (ProfileAppearance) -> Void) {
        self.username = username
        self.showsCloseButton = showsCloseButton
        self.initialAppearance = appearance
        self.onSave = onSave
        _draft = State(initialValue: appearance)
        _emojiInput = State(initialValue: appearance.emoji ?? "")
    }

    private var hasChanges: Bool {
        draft != initialAppearance
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
            VStack(spacing: 24) {
                // Avatar preview
                ProfileAvatarView(username: username, appearance: draft, size: 108)
                    .padding(.top, 8)

                // Emoji section
                VStack(alignment: .leading, spacing: 8) {
                    Text("profile.appearance.emoji_section")
                        .font(.headline)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            ZStack {
                                EmojiOnlyTextField(
                                    placeholder: "",
                                    text: $emojiInput,
                                    autoFocus: false,
                                    fontSize: 36,
                                    isFocused: $isEmojiFieldFocused
                                )
                                .frame(width: 52, height: 52)

                                if emojiInput.isEmpty {
                                    Image(systemName: "face.smiling")
                                        .font(.system(size: 26, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                        .allowsHitTesting(false)
                                }
                            }

                               Text(NSLocalizedString("profile.appearance.emoji_placeholder", comment: "Emoji placeholder"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            if !emojiInput.isEmpty {
                                Button {
                                    draft.emoji = nil
                                    emojiInput = ""
                                    dismissEmojiKeyboard()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.secondary)
                                        .padding(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                        .onTapGesture { requestEmojiFocus() }
                    }
                    .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                    .onChange(of: emojiInput) { _, newValue in
                        draft.emoji = newValue.isEmpty ? nil : newValue
                    }
                }

                // Background color section
                VStack(alignment: .leading, spacing: 8) {
                    Text("profile.appearance.background_section")
                        .font(.headline)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 14) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 12)], spacing: 12) {
                            ForEach(ProfileAppearance.BackgroundStyle.allCases) { style in
                                Button {
                                    draft.backgroundStyle = style
                                } label: {
                                    Circle()
                                        .fill(style.color)
                                        .frame(width: 44, height: 44)
                                        .overlay {
                                            if draft.backgroundStyle == style {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .shadow(color: style.color.opacity(0.4), radius: 4, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(16)
                    .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                }

                // Monogram style section
                VStack(alignment: .leading, spacing: 8) {
                    Text("profile.appearance.letter_style_section")
                        .font(.headline)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(ProfileAppearance.MonogramStyle.allCases.enumerated()), id: \.element.id) { index, style in
                            Button {
                                draft.monogramStyle = style
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: draft.monogramStyle == style ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(draft.monogramStyle == style ? Color.accentColor : Color.secondary)

                                    Text(style.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < ProfileAppearance.MonogramStyle.allCases.count - 1 {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                    .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .navigationTitle("profile.appearance.title")
        .navigationBarTitleDisplayMode(.inline)
        .simultaneousGesture(
            TapGesture().onEnded { dismissEmojiKeyboard() }
        )
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    PressableIconButton(action: {
                        dismissEmojiKeyboard()
                        dismiss()
                    }) {
                        Label("common.cancel", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 48, height: 48)
                    }
                    .padding(16)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismissEmojiKeyboard()
                    onSave(draft)
                    dismiss()
                } label: {
                    Label("common.done", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                .disabled(!hasChanges)
                .tint(.accentColor)
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
            }
        }
    }

    private func requestEmojiFocus() {
        DispatchQueue.main.async {
            isEmojiFieldFocused = true
        }
    }

    private func dismissEmojiKeyboard() {
        isEmojiFieldFocused = false
        PlatformSupport.dismissActiveInput()
    }
}
