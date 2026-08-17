import SwiftUI

struct AdminPanelView: View {
    @StateObject private var adminService: AdminService

    init(authService: FoodAuthService) {
        _adminService = StateObject(wrappedValue: AdminService(authService: authService))
    }

    var body: some View {
        List {
            Section("Management") {
                NavigationLink {
                    AdminUsersView()
                        .environmentObject(adminService)
                } label: {
                    adminRow(
                        title: "Users",
                        subtitle: "Search, ban and activity",
                        systemImage: "person.3.fill"
                    )
                }

                NavigationLink {
                    AdminBroadcastsView()
                        .environmentObject(adminService)
                } label: {
                    adminRow(
                        title: "Broadcasts",
                        subtitle: "Newsletters and news pushes",
                        systemImage: "megaphone.fill"
                    )
                }

                NavigationLink {
                    AdminSupportRequestsView()
                        .environmentObject(adminService)
                } label: {
                    adminRow(
                        title: "Support",
                        subtitle: "Requests and replies",
                        systemImage: "envelope.badge.fill"
                    )
                }
            }

            Section("Moderation") {
                NavigationLink {
                    AdminProductModerationView()
                } label: {
                    adminRow(
                        title: "Products",
                        subtitle: "Public product submissions",
                        systemImage: "checkmark.square.fill"
                    )
                }
            }
        }
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func adminRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AdminUsersView: View {
    @EnvironmentObject private var adminService: AdminService

    @State private var users: [Admin_AdminUser] = []
    @State private var total: Int32 = 0
    @State private var query = ""
    @State private var role = ""
    @State private var bannedOnly = false
    @State private var actionInFlightUserID: String?

    private let pageSize: Int32 = 50

    private var canLoadMore: Bool {
        Int(total) > users.count
    }

    var body: some View {
        List {
            Section {
                Picker("Role", selection: $role) {
                    Text("All").tag("")
                    Text("User").tag("user")
                    Text("Admin").tag("admin")
                    Text("Banned").tag("banned")
                }

                Toggle("Banned only", isOn: $bannedOnly)

                Button {
                    Task { await reloadUsers(reset: true) }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            } footer: {
                Text("\(users.count) of \(total)")
            }

            if let errorMessage = adminService.lastErrorMessage, !errorMessage.isEmpty {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section("Users") {
                if users.isEmpty, !adminService.isLoading {
                    ContentUnavailableView(
                        "No users",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Try another query or refresh the list.")
                    )
                } else {
                    ForEach(users, id: \.id) { user in
                        AdminUserRow(
                            user: user,
                            isActionInFlight: actionInFlightUserID == user.id,
                            onToggleBan: {
                                Task { await toggleBan(for: user) }
                            }
                        )
                    }

                    if canLoadMore {
                        Button {
                            Task { await reloadUsers(reset: false) }
                        } label: {
                            Label("Load more", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
        }
        .navigationTitle("Users")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Email, username, name or ID")
        .onSubmit(of: .search) {
            Task { await reloadUsers(reset: true) }
        }
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                Button {
                    Task { await reloadUsers(reset: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(adminService.isLoading)
            }
        }
        .task {
            guard users.isEmpty else { return }
            await reloadUsers(reset: true)
        }
        .refreshable {
            await reloadUsers(reset: true)
        }
        .onChange(of: role) { _, _ in
            Task { await reloadUsers(reset: true) }
        }
        .onChange(of: bannedOnly) { _, _ in
            Task { await reloadUsers(reset: true) }
        }
    }

    private func reloadUsers(reset: Bool) async {
        let offset: Int32 = reset ? 0 : Int32(users.count)
        guard let response = await adminService.listUsers(
            query: query,
            role: role,
            bannedOnly: bannedOnly,
            limit: pageSize,
            offset: offset
        ) else {
            return
        }

        total = response.total
        if reset {
            users = response.users
        } else {
            users.append(contentsOf: response.users)
        }
    }

    private func toggleBan(for user: Admin_AdminUser) async {
        actionInFlightUserID = user.id
        defer { actionInFlightUserID = nil }

        let updatedUser = user.isBanned
            ? await adminService.unbanUser(id: user.id)
            : await adminService.banUser(id: user.id)

        guard let updatedUser else { return }
        if bannedOnly, !updatedUser.isBanned {
            users.removeAll { $0.id == updatedUser.id }
            total = max(0, total - 1)
            return
        }

        if let index = users.firstIndex(where: { $0.id == updatedUser.id }) {
            users[index] = updatedUser
        }
    }
}

private struct AdminUserRow: View {
    let user: Admin_AdminUser
    let isActionInFlight: Bool
    let onToggleBan: () -> Void

    /// One name field now, where there used to be three.
    ///
    /// `AdminUser` carried `username`, `first_name` and `last_name`; the proto
    /// has since reserved the last two and left a single `name`, which is what
    /// users-service actually stores. Falling back to the email and then the id
    /// as before: a row with no label at all is worse than a row labelled by
    /// the only thing known about the person.
    private var displayName: String {
        let name = user.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return user.email.isEmpty ? user.id : user.email
    }

    private var banButtonRole: ButtonRole? {
        user.isBanned ? nil : .destructive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(user.email.isEmpty ? user.id : user.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    statusPill(user.isBanned ? "Banned" : user.role.capitalized, tint: user.isBanned ? .red : .accentColor)
                    statusPill(user.emailConfirmed ? "Email ok" : "Unconfirmed", tint: user.emailConfirmed ? .green : .secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Registered")
                        .foregroundStyle(.secondary)
                    Text(adminFormattedDate(user.createdAt, emptyFallback: "Unknown"))
                }
                GridRow {
                    Text("Last action")
                        .foregroundStyle(.secondary)
                    Text(adminFormattedDate(user.lastActivityAt, emptyFallback: "Never"))
                }
            }
            .font(.caption)

            HStack {
                Text(user.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Button(role: banButtonRole, action: onToggleBan) {
                    Label(user.isBanned ? "Unban" : "Ban", systemImage: user.isBanned ? "person.fill.checkmark" : "person.fill.xmark")
                }
                .buttonStyle(.bordered)
                .disabled(isActionInFlight)
            }
        }
        .padding(.vertical, 6)
    }

    private func statusPill(_ title: String, tint: Color) -> some View {
        Text(title.isEmpty ? "User" : title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private func adminFormattedDate(_ value: String, emptyFallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return emptyFallback }

    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plainFormatter = ISO8601DateFormatter()
    plainFormatter.formatOptions = [.withInternetDateTime]

    guard let date = fractionalFormatter.date(from: trimmed) ?? plainFormatter.date(from: trimmed) else {
        return trimmed
    }

    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
