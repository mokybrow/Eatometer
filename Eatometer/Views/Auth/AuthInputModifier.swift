import SwiftUI

struct AuthInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

extension View {
    func authInputStyle() -> some View {
        modifier(AuthInputModifier())
    }
}
