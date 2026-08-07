import SwiftUI

struct ActivityCenterView: View {
    @StateObject private var pushNotificationService = PushNotificationService.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                NavigationLink {
                    NotificationInboxView()
                } label: {
                    ActivityCenterTile(
                        iconName: unreadNotificationsIconName,
                        iconColor: Color.appAccent,
                        title: "profile.notifications.inbox.title",
                        subtitle: "activity.center.notifications.subtitle",
                        badgeText: unreadNotificationsBadgeText
                    )
                }
                .buttonStyle(.plain)

            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .navigationTitle(Text("activity.center.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await pushNotificationService.refreshInbox()
        }
    }

    private var unreadNotificationsIconName: String {
        pushNotificationService.unreadCount > 0 ? "bell.badge.fill" : "bell.fill"
    }

    private var unreadNotificationsBadgeText: String? {
        guard pushNotificationService.unreadCount > 0 else { return nil }
        return pushNotificationService.unreadCount > 99 ? "99+" : String(pushNotificationService.unreadCount)
    }
}

struct SocialView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var userService: UserService
    @StateObject private var pushNotificationService = PushNotificationService.shared
    @State private var mainHeaderScrollOffset: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var compactHeaderProgress: CGFloat {
        min(1, max(0, (mainHeaderScrollOffset - 30) / 30))
    }

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                scrollContent(topInset: proxy.safeAreaInsets.top)
            }

            MainHeaderCompactOverlay(
                title: "tab.social",
                username: authService.currentUsername,
                onProfileTap: { authService.showProfile = true },
                progress: compactHeaderProgress
            )
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .rootNavigationChrome("tab.social")
        .task {
            await refreshSocial()
        }
    }

    private func scrollContent(topInset: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                MainHeaderView(
                    title: "tab.social",
                    username: authService.currentUsername,
                    onProfileTap: { authService.showProfile = true }
                )
                .opacity(1 - compactHeaderProgress)
                .padding(.top, horizontalSizeClass == .regular ? 0 : topInset + 8)
                .padding(.bottom, 8)

                VStack(spacing: 10) {
                    NavigationLink {
                        FriendsView(isNested: true)
                    } label: {
                        ActivityCenterTile(
                            iconName: "person.2.fill",
                            iconColor: .appAccent,
                            title: "friends.tab.friends",
                            subtitle: "social.friends.subtitle",
                            badgeText: nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        FriendEventsView()
                    } label: {
                        ActivityCenterTile(
                            iconName: "sparkles",
                            iconColor: Color(red: 0.48, green: 0.78, blue: 0.61),
                            title: "friends.tab.events",
                            subtitle: "social.events.subtitle",
                            badgeText: nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NotificationInboxView()
                    } label: {
                        ActivityCenterTile(
                            iconName: notificationIconName,
                            iconColor: Color(red: 0.42, green: 0.68, blue: 0.92),
                            title: "profile.notifications.inbox.title",
                            subtitle: "social.notifications.subtitle",
                            badgeText: notificationBadgeText
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                    .frame(height: 24)
            }
            .padding(.horizontal, 20)
        }
        .ignoresSafeArea(edges: horizontalSizeClass == .regular ? [] : .top)
        .refreshable {
            await refreshSocial()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newValue in
            mainHeaderScrollOffset = newValue
        }
    }

    private var notificationIconName: String {
        pushNotificationService.unreadCount > 0 ? "bell.badge.fill" : "bell.fill"
    }

    private var notificationBadgeText: String? {
        guard pushNotificationService.unreadCount > 0 else { return nil }
        return pushNotificationService.unreadCount > 99 ? "99+" : String(pushNotificationService.unreadCount)
    }

    private func refreshSocial() async {
        async let friendshipsReload: Void = userService.refreshFriendships()
        async let inboxReload: Void = pushNotificationService.refreshInbox()
        await friendshipsReload
        await inboxReload
    }
}

private struct ActivityCenterTile: View {
    let iconName: String
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let badgeText: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(iconColor, in: Circle())

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.red, in: Capsule())
                        .offset(x: 5, y: -5)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}
