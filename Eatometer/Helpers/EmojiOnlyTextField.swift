import SwiftUI
import UIKit

struct EmojiOnlyTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var autoFocus: Bool = false
    var fontSize: CGFloat = 34
    var isFocused: Binding<Bool> = .constant(false)

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused)
    }

    func makeUIView(context: Context) -> EmojiKeyboardTextField {
        let textField = EmojiKeyboardTextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.text = text
        textField.font = .systemFont(ofSize: fontSize)
        textField.textAlignment = .center
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.returnKeyType = .done
        textField.backgroundColor = .clear
        textField.tintColor = .clear
        return textField
    }

    func updateUIView(_ uiView: EmojiKeyboardTextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if isFocused.wrappedValue {
            guard uiView.window != nil, !uiView.isFirstResponder else { return }
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
            return
        }

        if uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
            return
        }

        guard autoFocus, !context.coordinator.didAutoFocus, uiView.window != nil else {
            return
        }

        context.coordinator.didAutoFocus = true
        DispatchQueue.main.async {
            uiView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var isFocused: Binding<Bool>
        var didAutoFocus = false

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self._text = text
            self.isFocused = isFocused
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFocused.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFocused.wrappedValue = false
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let currentText = textField.text ?? ""
            guard let stringRange = Range(range, in: currentText) else {
                return false
            }

            let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
            let result = sanitizedEmojiText(updatedText)
            text = result
            textField.text = result
            return false
        }

        func textFieldShouldClear(_ textField: UITextField) -> Bool {
            text = ""
            isFocused.wrappedValue = false
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            isFocused.wrappedValue = false
            return true
        }
    }
}

final class EmojiKeyboardTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        for inputMode in UITextInputMode.activeInputModes where inputMode.primaryLanguage == "emoji" {
            return inputMode
        }
        return super.textInputMode
    }
}

private func sanitizedEmojiText(_ value: String) -> String {
    value
        .firstEmojiCharacter()
        .map(String.init) ?? ""
}

private extension String {
    func firstEmojiCharacter() -> Character? {
        for character in self {
            if character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.properties.isEmoji }) {
                return character
            }
        }
        return nil
    }
}