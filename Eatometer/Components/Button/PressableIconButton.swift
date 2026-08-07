import SwiftUI

struct PressableIconButton<Content: View>: View {
    let action: () -> Void
    let disabled: Bool
    let tintColor: Color?
    let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false

    init(disabled: Bool = false, tintColor: Color? = nil, action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.action = action
        self.disabled = disabled
        self.tintColor = tintColor
        self.content = content
    }

    var body: some View {
        button
            .scaleEffect(isPressed ? 1.12 : 1.0)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = pressing
                }
            }, perform: {})
            .disabled(disabled)
    }

    @ViewBuilder
    private var button: some View {
        if let tintColor {
            Button(action: action) {
                content()
            }
            .foregroundColor(colorScheme == .light ? Color.black : Color.white)
            .tint(tintColor)
            .glassEffect()
        } else {
            Button(action: action) {
                content()
            }
            .foregroundColor(colorScheme == .light ? Color.black : Color.white)
            .glassEffect()
        }
    }
}
