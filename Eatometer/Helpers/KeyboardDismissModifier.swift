import SwiftUI

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
    }
}

extension View {
    func dismissesKeyboardInteractively() -> some View {
        modifier(KeyboardDismissModifier())
    }
}
