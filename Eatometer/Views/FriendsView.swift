import SwiftUI

private enum FriendsTab: String, CaseIterable, Hashable, Identifiable {
    case events
    case friends
    case incoming
    case outgoing
    case declined
    case search

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .events:
            return "sparkles"
        case .friends:
            return "person.2.fill"
        case .incoming:
            return "tray.and.arrow.down.fill"
        case .outgoing:
            return "paperplane.fill"
        case .declined:
            return "xmark.circle.fill"
        case .search:
            return "plus"
        }
    }

    var emptyIconName: String {
        switch self {
        case .events:
            return "sparkles"
        case .friends:
            return "person.2"
        case .incoming:
            return "tray"
        case .outgoing:
            return "clock"
        case .declined:
            return "checkmark.circle"
        case .search:
            return "magnifyingglass"
        }
    }

    var tint: Color {
        switch self {
        case .friends, .search:
            return .appAccent
        case .events:
            return .teal
        case .incoming:
            return .blue
        case .outgoing:
            return .orange
        case .declined:
            return .red
        }
    }

    var title: String {
        switch self {
        case .events:
            return localizedFriendsText("friends.tab.events", fallback: "Events")
        case .friends:
            return localizedFriendsText("friends.tab.friends", fallback: "Friends")
        case .incoming:
            return localizedFriendsText("friends.tab.incoming", fallback: "Incoming")
        case .outgoing:
            return localizedFriendsText("friends.tab.outgoing", fallback: "Outgoing")
        case .declined:
            return localizedFriendsText("friends.tab.declined", fallback: "Declined")
        case .search:
            return localizedFriendsText("friends.tab.search", fallback: "Search")
        }
    }
}

private struct FriendDashboardTile: Identifiable {
    let tab: FriendsTab
    let count: Int

    var id: FriendsTab { tab }
}

private func localizedFriendsText(_ key: String, fallback: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
}

struct FriendsView: View {
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var userService: UserService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let isNested: Bool
    @State private var mainHeaderScrollOffset: CGFloat = 0

    init(isNested: Bool = false) {
        self.isNested = isNested
    }

    private var compactHeaderProgress: CGFloat {
        min(1, max(0, (mainHeaderScrollOffset - 30) / 30))
    }

    var body: some View {
        Group {
            if isNested {
                nestedContent
            } else {
                standaloneContent
            }
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .task {
            await userService.refreshFriendships()
        }
    }

    private var standaloneContent: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                scrollContent(topInset: proxy.safeAreaInsets.top)
            }

            MainHeaderCompactOverlay(
                title: "tab.friends",
                username: authService.currentUsername,
                onProfileTap: { authService.showProfile = true },
                progress: compactHeaderProgress
            )
        }
        .rootNavigationChrome("tab.friends")
    }

    private var nestedContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if let errorMessage = userService.friendsErrorMessage, !errorMessage.isEmpty {
                    errorCard(errorMessage)
                }

                primaryTiles
                addTile
                friendsListSection

                Spacer()
                    .frame(height: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable {
            await userService.refreshFriendships()
        }
        .navigationTitle(Text("tab.friends"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func scrollContent(topInset: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                MainHeaderView(
                    title: "tab.friends",
                    username: authService.currentUsername,
                    onProfileTap: { authService.showProfile = true }
                )
                .opacity(1 - compactHeaderProgress)
                .padding(.top, horizontalSizeClass == .regular ? 0 : topInset + 8)

                if let errorMessage = userService.friendsErrorMessage, !errorMessage.isEmpty {
                    errorCard(errorMessage)
                }

                primaryTiles
                addTile
                friendsListSection

                Spacer()
                    .frame(height: 24)
            }
            .padding(.horizontal, 20)
        }
        .ignoresSafeArea(edges: horizontalSizeClass == .regular ? [] : .top)
        .refreshable {
            await userService.refreshFriendships()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newValue in
            mainHeaderScrollOffset = newValue
        }
    }

    private var primaryTiles: some View {
        LazyVGrid(columns: dashboardColumns, spacing: 10) {
            ForEach(dashboardTiles) { item in
                metricTile(tab: item.tab, count: item.count)
            }
        }
    }

    private var dashboardColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: max(1, min(3, dashboardTiles.count)))
    }

    private var dashboardTiles: [FriendDashboardTile] {
        [
            FriendDashboardTile(tab: .incoming, count: userService.incomingFriendRequests.count),
            FriendDashboardTile(tab: .declined, count: userService.declinedFriendRequests.count)
        ]
    }

    private func metricTile(tab: FriendsTab, count: Int) -> some View {
        NavigationLink {
            routeDestination(for: tab)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tab.tint)
                    .frame(width: 34, height: 34)
                    .background(tab.tint.opacity(0.12), in: Circle())

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(tab.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 34, alignment: .topLeading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var addTile: some View {
        NavigationLink {
            routeDestination(for: .search)
        } label: {
            smallTileContent(
                title: NSLocalizedString("common.add", comment: "Add action"),
                iconName: FriendsTab.search.iconName,
                tint: FriendsTab.search.tint,
                count: nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("common.add"))
    }

    @ViewBuilder
    private var friendsListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizedFriendsText("friends.tab.friends", fallback: "Friends"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            if userService.friends.isEmpty {
                centeredPlaceholder(tab: .friends, key: "friends.empty", fallback: "No friends yet", minHeight: 180)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(userService.friends.enumerated()), id: \.element.id) { index, friendship in
                        FriendRow(profile: friendship.profile, canViewActivity: true) {
                            EmptyView()
                        }

                        if index < userService.friends.count - 1 {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
            }
        }
    }

    private func smallTileContent(title: String, iconName: String, tint: Color, count: Int?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())

            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private func routeDestination(for tab: FriendsTab) -> some View {
        switch tab {
        case .events:
            FriendEventsView()
        case .friends, .incoming, .declined:
            FriendStatusListView(tab: tab)
        case .outgoing:
            EmptyView()
        case .search:
            FriendSearchView()
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private enum FriendActivityEventKind {
    case meals(Int)
    case calories(Int)
    case water(Int)
    case waterGoal(Int)
    case streak(Int)

    init?(key: String, value: Int) {
        switch key {
        case "meals": self = .meals(value)
        case "calories": self = .calories(value)
        case "water": self = .water(value)
        case "waterGoal": self = .waterGoal(value)
        case "streak": self = .streak(value)
        default: return nil
        }
    }

    var id: String {
        switch self {
        case .meals:
            return "meals"
        case .calories:
            return "calories"
        case .water:
            return "water"
        case .waterGoal:
            return "water-goal"
        case .streak:
            return "streak"
        }
    }

    var sortRank: Int {
        switch self {
        case .waterGoal:
            return 0
        case .streak:
            return 1
        case .meals:
            return 2
        case .calories:
            return 3
        case .water:
            return 4
        }
    }

    var iconName: String {
        switch self {
        case .meals:
            return "fork.knife"
        case .calories:
            return "flame.fill"
        case .water, .waterGoal:
            return "drop.fill"
        case .streak:
            return "flame.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .meals:
            return .appAccent
        case .calories:
            return .orange
        case .water, .waterGoal:
            return .blue
        case .streak:
            return .appHighlight
        }
    }
}

private struct FriendActivityEvent: Identifiable {
    let id: String
    let profile: EatometerFriendProfile
    let kind: FriendActivityEventKind

    init?(stored: StoredFriendEvent) {
        guard let kind = FriendActivityEventKind(key: stored.kind, value: stored.value) else {
            return nil
        }
        self.id = stored.id
        self.profile = stored.profile
        self.kind = kind
    }

    var title: String {
        switch kind {
        case .meals(let count):
            return String(
                format: localizedFriendsText("friends.events.meals", fallback: "%@ logged %d meals today"),
                profile.displayName,
                count
            )
        case .calories(let calories):
            return String(
                format: localizedFriendsText("friends.events.calories", fallback: "%@ tracked %d kcal today"),
                profile.displayName,
                calories
            )
        case .water(let milliliters):
            return String(
                format: localizedFriendsText("friends.events.water", fallback: "%@ logged %@ water"),
                profile.displayName,
                friendWaterAmountText(milliliters)
            )
        case .waterGoal(let milliliters):
            return String(
                format: localizedFriendsText("friends.events.water_goal", fallback: "%@ reached the water goal (%@)"),
                profile.displayName,
                friendWaterAmountText(milliliters)
            )
        case .streak(let days):
            return String(
                format: localizedFriendsText("friends.events.streak", fallback: "%@ keeps a %d-day diary streak"),
                profile.displayName,
                days
            )
        }
    }

    var subtitle: String {
        "@\(profile.username)"
    }
}

private func friendWaterAmountText(_ milliliters: Int) -> String {
    if milliliters >= 1000 {
        return String(
            format: NSLocalizedString("water.goal.preset_ml", comment: "Water amount in liters"),
            Double(milliliters) / 1000.0
        )
    }

    return "\(milliliters) \(NSLocalizedString("water.ml", comment: "Milliliters unit"))"
}

struct FriendEventsView: View {
    @EnvironmentObject private var userService: UserService

    private var events: [FriendActivityEvent] {
        userService.friendActivityEvents.compactMap(FriendActivityEvent.init(stored:))
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if events.isEmpty {
                        centeredPlaceholder(tab: .events, key: "friends.events.empty", fallback: "No friend activity yet", minHeight: 260)
                    } else {
                        FriendEventsListCard(events: events)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, events.isEmpty ? 0 : 12)
                .padding(.bottom, events.isEmpty ? 0 : 24)
                .frame(minHeight: proxy.size.height, alignment: events.isEmpty ? .center : .top)
            }
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .navigationTitle(Text(FriendsTab.events.title))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await userService.refreshFriendships()
        }
    }
}

private struct FriendEventsListCard: View {
    let events: [FriendActivityEvent]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                FriendActivityEventRow(event: event)

                if index < events.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}

private struct FriendActivityEventRow: View {
    let event: FriendActivityEvent

    var body: some View {
        NavigationLink {
            FriendProfileView(profile: event.profile, canViewActivity: true)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarView(username: event.profile.avatarSource, appearance: event.profile.appearance, size: 48)

                    Image(systemName: event.kind.iconName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(event.kind.tint)
                        .frame(width: 22, height: 22)
                        .background(Color.appCardBackground, in: Circle())
                        .overlay(Circle().stroke(event.kind.tint.opacity(0.18), lineWidth: 1))
                        .offset(x: 3, y: 3)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(event.subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

private struct FriendStatusListView: View {
    @EnvironmentObject private var userService: UserService
    let tab: FriendsTab
    @State private var actionInFlightID: String?

    private var items: [EatometerFriendship] {
        switch tab {
        case .events:
            return []
        case .friends:
            return userService.friends
        case .incoming:
            return userService.incomingFriendRequests
        case .outgoing:
            return userService.outgoingFriendRequests
        case .declined:
            return userService.declinedFriendRequests
        case .search:
            return []
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if items.isEmpty {
                        centeredPlaceholder(tab: tab, key: emptyKey, fallback: emptyFallback, minHeight: 260)
                    } else {
                        listCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, items.isEmpty ? 0 : 12)
                .padding(.bottom, items.isEmpty ? 0 : 24)
                .frame(minHeight: proxy.size.height, alignment: items.isEmpty ? .center : .top)
            }
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .navigationTitle(Text(tab.title))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await userService.refreshFriendships()
        }
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, friendship in
                FriendRow(profile: friendship.profile, canViewActivity: tab == .friends) {
                    trailingAction(for: friendship)
                }

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private func trailingAction(for friendship: EatometerFriendship) -> some View {
        switch tab {
        case .events:
            EmptyView()
        case .friends:
            actionButton(systemImage: "person.fill.xmark", tint: .red, id: "remove-\(friendship.id)") {
                await userService.removeFriend(friendUserID: friendship.profile.id)
            }
        case .incoming:
            HStack(spacing: 6) {
                actionButton(systemImage: "checkmark", tint: .green, id: "accept-\(friendship.id)") {
                    await userService.respondFriendRequest(requesterUserID: friendship.profile.id, accept: true)
                }
                actionButton(systemImage: "xmark", tint: .red, id: "decline-\(friendship.id)") {
                    await userService.respondFriendRequest(requesterUserID: friendship.profile.id, accept: false)
                }
            }
        case .outgoing:
            statusPill(systemImage: "clock", tint: .secondary)
        case .declined:
            actionButton(systemImage: "trash", tint: .red, id: "dismiss-\(friendship.id)") {
                await userService.dismissDeclinedFriendRequest(requesterUserID: friendship.profile.id)
            }
        case .search:
            EmptyView()
        }
    }

    private var emptyKey: String {
        switch tab {
        case .events:
            return "friends.events.empty"
        case .friends:
            return "friends.empty"
        case .incoming:
            return "friends.incoming.empty"
        case .outgoing:
            return "friends.outgoing.empty"
        case .declined:
            return "friends.declined.empty"
        case .search:
            return "friends.search.empty"
        }
    }

    private var emptyFallback: String {
        switch tab {
        case .events:
            return "No friend activity yet"
        case .friends:
            return "No friends yet"
        case .incoming:
            return "No incoming requests"
        case .outgoing:
            return "No outgoing requests"
        case .declined:
            return "No declined requests"
        case .search:
            return "No users found"
        }
    }

    private func actionButton(
        systemImage: String,
        tint: Color,
        id: String,
        action: @escaping () async -> Bool
    ) -> some View {
        Button {
            actionInFlightID = id
            Task {
                _ = await action()
                await MainActor.run {
                    actionInFlightID = nil
                }
            }
        } label: {
            actionButtonLabel(systemImage: systemImage, tint: tint, isLoading: actionInFlightID == id)
        }
        .buttonStyle(.plain)
        .disabled(actionInFlightID != nil)
    }
}

private struct FriendSearchView: View {
    @EnvironmentObject private var userService: UserService
    @State private var searchText = ""
    @State private var actionInFlightID: String?

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    searchFieldCard

                    searchResults(minHeight: max(260, proxy.size.height - 104))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .navigationTitle(Text(localizedFriendsText("friends.tab.search", fallback: "Search")))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: searchText) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await userService.searchFriends(query: searchText)
        }
        .refreshable {
            await userService.searchFriends(query: searchText)
        }
    }

    @ViewBuilder
    private func searchResults(minHeight: CGFloat) -> some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            centeredPlaceholder(tab: .search, key: "friends.search.empty_query", fallback: "Search", minHeight: minHeight)
        } else if userService.friendSearchResults.isEmpty {
            centeredPlaceholder(tab: .search, key: "friends.search.empty", fallback: "No users found", minHeight: minHeight)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(userService.friendSearchResults.enumerated()), id: \.element.id) { index, profile in
                    let friendProfile = userService.friends.first { $0.profile.id == profile.id }?.profile
                    FriendRow(
                        profile: profile,
                        canViewActivity: friendProfile != nil,
                        activityProfile: friendProfile
                    ) {
                        searchAction(for: profile)
                    }

                    if index < userService.friendSearchResults.count - 1 {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var searchFieldCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            TextField(
                localizedFriendsText("friends.search.placeholder", fallback: "Username or name"),
                text: $searchText
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private func searchAction(for profile: EatometerFriendProfile) -> some View {
        if userService.friends.contains(where: { $0.profile.id == profile.id }) {
            statusPill(systemImage: "checkmark", tint: .green)
        } else if userService.outgoingFriendRequests.contains(where: { $0.profile.id == profile.id }) {
            statusPill(systemImage: "clock", tint: .secondary)
        } else if userService.incomingFriendRequests.contains(where: { $0.profile.id == profile.id }) {
            statusPill(systemImage: "arrow.down", tint: .appAccent)
        } else {
            actionButton(systemImage: "plus", tint: .appAccent, id: "send-\(profile.id)") {
                let success = await userService.sendFriendRequest(to: profile.id)
                await userService.searchFriends(query: searchText)
                return success
            }
        }
    }

    private func actionButton(
        systemImage: String,
        tint: Color,
        id: String,
        action: @escaping () async -> Bool
    ) -> some View {
        Button {
            actionInFlightID = id
            Task {
                _ = await action()
                await MainActor.run {
                    actionInFlightID = nil
                }
            }
        } label: {
            actionButtonLabel(systemImage: systemImage, tint: tint, isLoading: actionInFlightID == id)
        }
        .buttonStyle(.plain)
        .disabled(actionInFlightID != nil)
    }
}

private func actionButtonLabel(systemImage: String, tint: Color, isLoading: Bool) -> some View {
    Group {
        if isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
        }
    }
    .frame(width: 36, height: 36)
    .foregroundStyle(tint)
    .background(tint.opacity(0.12), in: Circle())
}

private func statusPill(systemImage: String, tint: Color) -> some View {
    Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 34, height: 34)
        .background(tint.opacity(0.11), in: Circle())
}

private func centeredPlaceholder(tab: FriendsTab, key: String, fallback: String, minHeight: CGFloat) -> some View {
    VStack(spacing: 12) {
        Image(systemName: tab.emptyIconName)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(Color.secondary)
            .frame(width: 66, height: 66)
            .background(Color.secondary.opacity(0.10), in: Circle())

        Text(localizedFriendsText(key, fallback: fallback))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 260)
    }
    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
    .padding(.horizontal, 14)
}

private struct FriendRow<Trailing: View>: View {
    let profile: EatometerFriendProfile
    var canViewActivity = false
    var activityProfile: EatometerFriendProfile?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                FriendProfileView(profile: activityProfile ?? profile, canViewActivity: canViewActivity)
            } label: {
                HStack(spacing: 12) {
                    ProfileAvatarView(username: profile.avatarSource, appearance: profile.appearance, size: 46)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("@\(profile.username)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct FriendProfileView: View {
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var catalogService: FoodCatalogService
    let profile: EatometerFriendProfile
    let canViewActivity: Bool
    @State private var isLoadingProfile = false
    @State private var didLoadProfile = false
    @State private var visibleCatalog: FriendVisibleCatalog?
    @State private var isLoadingVisibleCatalog = false
    @State private var didLoadVisibleCatalog = false

    private var displayedProfile: EatometerFriendProfile {
        guard canViewActivity else { return profile }
        return userService.friends.first { $0.profile.id == profile.id }?.profile ?? profile
    }

    private var displayedCatalog: FriendVisibleCatalog? {
        visibleCatalog?.filtered(allowFriendsVisibility: canViewActivity)
    }

    private var shouldShowProfileSkeleton: Bool {
        canViewActivity && isLoadingProfile && !didLoadProfile
    }

    private var shouldShowCatalogSkeleton: Bool {
        isLoadingVisibleCatalog && !didLoadVisibleCatalog
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            Group {
                if shouldShowProfileSkeleton {
                    profileSkeletonView
                } else {
                    VStack(spacing: 16) {
                        heroCard
                        if canViewActivity {
                            todayMetricsGrid
                        } else {
                            activityPendingCard
                        }
                        catalogContent

                        Spacer()
                            .frame(height: 20)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .navigationTitle(Text(displayedProfile.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: profile.id) {
            await refreshProfileIfNeeded()
            await loadVisibleCatalog()
        }
    }

    private func refreshProfileIfNeeded() async {
        guard canViewActivity else { return }
        isLoadingProfile = true
        await userService.refreshFriendships()
        didLoadProfile = true
        isLoadingProfile = false
    }

    private func loadVisibleCatalog() async {
        isLoadingVisibleCatalog = true
        defer {
            didLoadVisibleCatalog = true
            isLoadingVisibleCatalog = false
        }

        visibleCatalog = await catalogService.loadVisibleCatalog(for: profile.id)
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            ProfileAvatarView(username: displayedProfile.avatarSource, appearance: displayedProfile.appearance, size: 104)
                // Cut to the avatar's own outline, so the ring follows it
                // rather than describing a circle that is no longer there.
                .overlay(ProfileAvatarView.shape(size: 104).stroke(Color.primary.opacity(0.10), lineWidth: 1))

            VStack(spacing: 4) {
                Text(displayedProfile.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text("@\(displayedProfile.username)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private var profileSkeletonView: some View {
        VStack(spacing: 16) {
            skeletonHeroCard
            skeletonMetricsGrid

            Spacer()
                .frame(height: 20)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var skeletonHeroCard: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 104, height: 104)

            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 150, height: 20)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 96, height: 14)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private var skeletonMetricsGrid: some View {
        LazyVGrid(columns: metricColumns, spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                skeletonMetricCard
            }
        }
    }

    private var skeletonMetricCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 42, height: 42)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .frame(width: 82, height: 12)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 104, height: 22)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .redacted(reason: .placeholder)
    }

    private var activityPendingCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, height: 54)
                .background(Color.secondary.opacity(0.10), in: Circle())

            Text(localizedFriendsText("friends.profile.wait_acceptance", fallback: "Activity appears after the request is accepted."))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .padding(.horizontal, 18)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var catalogContent: some View {
        if shouldShowCatalogSkeleton {
            visibleCatalogSkeleton
        } else if let displayedCatalog, !displayedCatalog.isEmpty {
            visibleCatalogCard(displayedCatalog)
        } else if didLoadVisibleCatalog {
            visibleCatalogEmptyCard
        }
    }

    private func visibleCatalogCard(_ catalog: FriendVisibleCatalog) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 32, height: 32)
                    .background(Color.appAccent.opacity(0.12), in: Circle())

                Text(localizedFriendsText("friends.profile.visible_library", fallback: "Visible library"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }

            if !catalog.products.isEmpty {
                visibleCatalogSection(title: NSLocalizedString("products.title", comment: "Products section"), items: catalog.products) { product in
                    NavigationLink {
                        ProductDetailView(productID: product.id, initialProduct: product)
                    } label: {
                        visibleCatalogRow(
                            iconName: "basket.fill",
                            tint: .green,
                            title: product.name,
                            subtitle: productSubtitle(product),
                            showsIcon: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !catalog.recipes.isEmpty {
                visibleCatalogSection(title: NSLocalizedString("recipes.title", comment: "Recipes section"), items: catalog.recipes) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipeID: recipe.id, initialRecipe: recipe)
                    } label: {
                        visibleCatalogRow(
                            iconName: "fork.knife",
                            tint: .orange,
                            title: recipe.title,
                            subtitle: recipeSubtitle(recipe),
                            showsIcon: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !catalog.mealTemplates.isEmpty {
                visibleCatalogSection(title: NSLocalizedString("today.meals.title", comment: "Meals section"), items: catalog.mealTemplates) { mealTemplate in
                    NavigationLink {
                        MealTemplateDetailView(mealTemplateID: mealTemplate.id, initialMealTemplate: mealTemplate)
                    } label: {
                        visibleCatalogRow(
                            iconName: "square.stack.3d.up.fill",
                            tint: .mint,
                            title: mealTemplate.title,
                            subtitle: mealTemplateSubtitle(mealTemplate),
                            showsIcon: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private func visibleCatalogSection<Item: Identifiable, Content: View>(
        title: String,
        items: [Item],
        @ViewBuilder row: @escaping (Item) -> Content
    ) -> some View {
        VisibleCatalogSection(title: title, items: items, row: row)
    }

    private func visibleCatalogRow(
        iconName: String,
        tint: Color,
        title: String,
        subtitle: String,
        emoji: String = "",
        showsIcon: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            if showsIcon {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.13))

                    if !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(emoji)
                            .font(.system(size: 19))
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var visibleCatalogSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 142, height: 18)

            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.14))
                            .frame(width: 160, height: 13)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.secondary.opacity(0.10))
                            .frame(width: 96, height: 10)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .redacted(reason: .placeholder)
    }

    private var visibleCatalogEmptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(Color.secondary.opacity(0.10), in: Circle())

            Text(localizedFriendsText("friends.profile.visible_library.empty", fallback: "No visible recipes, products or rations yet."))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, minHeight: 156)
        .padding(.horizontal, 16)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private func productSubtitle(_ product: ProductSummary) -> String {
        let kcal = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        let calories = "\(product.caloriesPer100g) \(kcal) / 100\(NSLocalizedString("unit.grams.short", comment: "Grams unit short title"))"
        let brand = product.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty ? calories : "\(brand) · \(calories)"
    }

    private func recipeSubtitle(_ recipe: RecipeSummary) -> String {
        let kcal = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        return "\(recipe.caloriesPerServing) \(kcal) · \(recipe.servings)x"
    }

    private func mealTemplateSubtitle(_ mealTemplate: MealTemplateSummary) -> String {
        let kcal = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        let itemCount = String(format: NSLocalizedString("library.count.products", comment: "Products count"), mealTemplate.items.count)
        return "\(mealTemplate.calories) \(kcal) · \(itemCount)"
    }

    private var todayMetricsGrid: some View {
        LazyVGrid(columns: metricColumns, spacing: 10) {
            ForEach(todayMetrics) { metric in
                metricCard(metric)
            }
        }
    }

    private var caloriesValueText: String {
        let unit = NSLocalizedString("diary.kcal", comment: "Calories suffix")
        return "\(displayedProfile.caloriesToday) \(unit)"
    }

    private var waterValueText: String {
        let unit = NSLocalizedString("water.ml", comment: "Milliliters unit")
        if displayedProfile.waterGoalMilliliters > 0 {
            return "\(displayedProfile.waterTodayMilliliters) / \(displayedProfile.waterGoalMilliliters) \(unit)"
        }
        return "\(displayedProfile.waterTodayMilliliters) \(unit)"
    }

    private var streakValueText: String {
        String(
            format: NSLocalizedString("habits.detail.overview.days", comment: "Number of days"),
            displayedProfile.foodLoggingStreakDays
        )
    }

    private var mealsValueText: String {
        "\(displayedProfile.mealsLoggedToday)"
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var todayMetrics: [FriendProfileMetric] {
        var metrics = [
            FriendProfileMetric(
                id: "calories",
                title: localizedFriendsText("friends.calories_today", fallback: "Calories today"),
                value: caloriesValueText,
                iconName: "flame.fill",
                tint: .orange
            )
        ]

        if displayedProfile.waterTrackingEnabled {
            metrics.append(
                FriendProfileMetric(
                    id: "water",
                    title: localizedFriendsText("friends.water_today", fallback: "Water today"),
                    value: waterValueText,
                    iconName: "drop.fill",
                    tint: .blue
                )
            )
        }

        metrics.append(
            contentsOf: [
                FriendProfileMetric(
                    id: "streak",
                    title: localizedFriendsText("friends.logging_streak", fallback: "Diary streak"),
                    value: streakValueText,
                    iconName: "flame.circle.fill",
                    tint: .red
                ),
                FriendProfileMetric(
                    id: "meals",
                    title: localizedFriendsText("friends.meals_today", fallback: "Meals today"),
                    value: mealsValueText,
                    iconName: "fork.knife",
                    tint: .appAccent
                )
            ]
        )

        return metrics
    }

    private func metricCard(_ metric: FriendProfileMetric) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: metric.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(metric.tint)
                .frame(width: 42, height: 42)
                .background(metric.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            Spacer(minLength: 0)

            Text(metric.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(metric.value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}

private struct FriendProfileMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let iconName: String
    let tint: Color
}

private struct VisibleCatalogSection<Item: Identifiable, Content: View>: View {
    let title: String
    let items: [Item]
    let row: (Item) -> Content

    init(title: String, items: [Item], @ViewBuilder row: @escaping (Item) -> Content) {
        self.title = title
        self.items = items
        self.row = row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 2)
                .padding(.bottom, 8)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 54)
                }
            }
        }
    }
}
