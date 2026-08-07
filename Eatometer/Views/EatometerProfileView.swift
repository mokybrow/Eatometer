import SwiftUI

private enum EatometerProfileRoute: Hashable {
    case name
    case appIcon
    case email
    case mealPlan
    case meals
    case waterPlan
}

struct EatometerProfileView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var diaryService: FoodDiaryService
    @EnvironmentObject private var habitsService: HabitsService

    @StateObject private var appIconManager = AppIconManager.shared

    @State private var showLogoutConfirmation = false
    @State private var isNotificationsPresented = false

    private var name: String {
        let value = userService.currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? NSLocalizedString("profile.name.not_set", comment: "Name is not set") : value
    }

    private var email: String {
        let value = userService.currentUser?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? NSLocalizedString("profile.email.not_set", comment: "Email is not set") : value
    }

    private var emailStatus: String {
        userService.currentUser?.emailConfirmed == true
            ? NSLocalizedString("profile.email.verified", tableName: nil, bundle: .main, value: "Verified", comment: "Verified email")
            : NSLocalizedString("profile.email.unverified", tableName: nil, bundle: .main, value: "Not verified", comment: "Unverified email")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                profileHeader

                EOSection("profile.section.general") {
                    editRow(title: "profile.name.label", route: .name)
                    EORowSeparator()
                    NavigationLink(value: EatometerProfileRoute.appIcon) {
                        EOListRow(
                            title: Text("settings.app_icon.title"),
                            accessory: .valueChevron(Text(appIconManager.selected.titleKey))
                        )
                    }
                    .buttonStyle(.plain)
                }

                EOSection("profile.section.security") {
                    editRow(title: "profile.email.label", subtitle: Text(verbatim: emailStatus), route: .email)
                }

                EOSection("profile.section.nutrition") {
                    editRow(title: "profile.nutrition.meal_plan", route: .mealPlan)
                    EORowSeparator()
                    editRow(title: "profile.nutrition.meals", route: .meals)
                    EORowSeparator()
                    editRow(title: "profile.nutrition.water_plan", route: .waterPlan)
                    EORowSeparator()
                    EOToggleRow(
                        "profile.nutrition.water_tracker",
                        isOn: Binding(
                            get: { appSettings.isWaterTrackingEnabled },
                            set: { appSettings.setWaterTrackingEnabled($0) }
                        )
                    )
                    EORowSeparator()
                    EOToggleRow(
                        "profile.nutrition.health_sync",
                        isOn: asyncToggle(
                            get: { diaryService.healthSyncEnabled },
                            set: { await diaryService.setHealthSyncEnabled($0) }
                        )
                    )
                }

                EOSection("settings.section.notifications") {
                    EOToggleRow(
                        "settings.notifications.meal_reminders",
                        isOn: asyncToggle(
                            get: { diaryService.mealRemindersEnabled },
                            set: { await diaryService.setMealRemindersEnabled($0) }
                        )
                    )
                    EORowSeparator()
                    EOToggleRow(
                        "settings.notifications.water_logging",
                        isOn: asyncToggle(
                            get: { diaryService.waterLoggingRemindersEnabled },
                            set: { await diaryService.setWaterLoggingRemindersEnabled($0) }
                        )
                    )
                    EORowSeparator()
                    EOToggleRow(
                        "settings.notifications.habits",
                        isOn: asyncToggle(
                            get: { diaryService.habitNotificationsEnabled },
                            set: {
                                await diaryService.setHabitNotificationsEnabled($0)
                                HabitLocalNotificationScheduler.shared.refreshReminders(for: habitsService.habits)
                            }
                        )
                    )
                    EORowSeparator()
                    EOToggleRow(
                        "settings.notifications.useful",
                        isOn: asyncToggle(
                            get: { diaryService.usefulNotificationsEnabled },
                            set: { await diaryService.setUsefulNotificationsEnabled($0) }
                        )
                    )
                }

                EOCard {
                    Button {
                        showLogoutConfirmation = true
                    } label: {
                        Text("profile.logout.action")
                            .font(EOTheme.Typography.rowTitle)
                            .foregroundStyle(EOTheme.Palette.destructive)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, EOTheme.Metrics.rowVerticalPadding)
                            .frame(minHeight: EOTheme.Metrics.rowMinHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .eoCardInsets()

                VStack(alignment: .leading, spacing: 12) {
                    EOFootnote("profile.health_data.footer")
                    EOFootnote("profile.footer")
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .eoPageBackground()
        .navigationTitle("profile.section.profile")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                Button {
                    isNotificationsPresented = true
                } label: {
                    Image(systemName: "bell")
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(Text("profile.notifications.inbox.title"))
            }
        }
        .navigationDestination(for: EatometerProfileRoute.self) { route in
            destination(for: route)
        }
        .navigationDestination(isPresented: $isNotificationsPresented) {
            NotificationInboxView()
        }
        .task {
            _ = await userService.fetchCurrentUser()
        }
        .alert("profile.logout.title", isPresented: $showLogoutConfirmation) {
            Button("profile.logout.action", role: .destructive) {
                authService.logout()
                userService.clearCachedProfile()
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("profile.logout.message")
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 10) {
            ProfileAvatarView(
                username: name,
                appearance: userService.profileAppearance,
                size: 96
            )

            Text(name)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    /// "Name … Edit ›" row that pushes an editor.
    private func editRow(
        title: LocalizedStringKey,
        subtitle: Text? = nil,
        route: EatometerProfileRoute
    ) -> some View {
        NavigationLink(value: route) {
            EOListRow(
                title: Text(title),
                subtitle: subtitle,
                accessory: .valueChevron(Text("common.edit"))
            )
        }
        .buttonStyle(.plain)
    }

    private func asyncToggle(
        get: @escaping () -> Bool,
        set: @escaping (Bool) async -> Void
    ) -> Binding<Bool> {
        Binding(
            get: get,
            set: { value in
                Task { await set(value) }
            }
        )
    }

    @ViewBuilder
    private func destination(for route: EatometerProfileRoute) -> some View {
        switch route {
        case .name:
            EatometerNameEditorView(name: userService.currentUser?.name ?? "")
        case .appIcon:
            AppIconPickerView()
        case .email:
            EatometerEmailEditorView(email: userService.currentUser?.email ?? "")
        case .mealPlan:
            EatometerMealPlanSettingsView()
        case .meals:
            EatometerMealsSettingsView()
        case .waterPlan:
            WaterGoalSettingsView()
        }
    }
}
