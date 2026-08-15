import SwiftUI

struct NotificationBellButton: View {
    @StateObject private var pushNotificationService = PushNotificationService.shared

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .foregroundStyle(.primary)

                if pushNotificationService.unreadCount > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                        .overlay(
                            Circle()
                                .stroke(Color.appPageBackground, lineWidth: 1.5)
                        )
                        .offset(x: 4, y: -3)
                }
            }
            .frame(width: 24, height: 24)
        }
        .accessibilityLabel(Text("profile.notifications.inbox.title"))
    }
}
