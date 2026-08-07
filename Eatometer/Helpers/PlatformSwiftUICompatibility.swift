import SwiftUI

extension ToolbarItemPlacement {
    static var platformTopBarLeading: ToolbarItemPlacement {
        .topBarLeading
    }

    static var platformTopBarTrailing: ToolbarItemPlacement {
        .topBarTrailing
    }
}

extension View {
    func platformNavigationBarHidden(_ hidden: Bool) -> some View {
        self.navigationBarHidden(hidden)
    }

    func platformToolbarBackgroundHiddenForNavigationBar() -> some View {
        self.toolbarBackground(.hidden, for: .navigationBar)
    }

    func platformToolbarBackgroundVisibleForNavigationBar() -> some View {
        self.toolbarBackground(.visible, for: .navigationBar)
    }

    func platformToolbarBackgroundColorForNavigationBar(_ color: Color) -> some View {
        self.toolbarBackground(color, for: .navigationBar)
    }
}