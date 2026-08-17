import Combine
import SwiftProtobuf
import SwiftUI
import UIKit

private enum NutritionPreferencesDestination: Identifiable, Hashable {
    case dietPlan
    case calorieGoal
    case mealSlots
    case waterGoal

    var id: Int {
        switch self {
        case .dietPlan:
            return 0
        case .calorieGoal:
            return 1
        case .mealSlots:
            return 2
        case .waterGoal:
            return 3
        }
    }
}

private enum ProfileDestination: Hashable {
    case profileDetails
    case credentialsSettings
    case notificationsSettings
    case nutritionSettings
    case managementSettings
    case adminPanel
    case appIcon
    case name
    case username
    case email
    case supporter
    case nutrition(NutritionPreferencesDestination)
}

struct ProfileSheetView: View {
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var authService: FoodAuthService
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var diaryService: FoodDiaryService
    @EnvironmentObject private var habitsService: HabitsService
    @EnvironmentObject private var supporterService: SupporterService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Binding var isPresented: Bool

    @State private var showLogoutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var birthdate = Date()
    @State private var hasBirthdate = false
    @State private var isBirthdatePickerPresented = false
    @State private var birthdateResultMessage: String?
    @State private var showBirthdateResultAlert = false
    @State private var selectedSex: User_UserSex = .preferNotToSay
    @State private var sexResultMessage: String?
    @State private var showSexResultAlert = false
    @State private var profileAppearance: ProfileAppearance = .default
    @State private var showEmailConfirmationSent = false
    @State private var emailConfirmationError: String?
    @State private var localCacheSizeText: String = "Calculating..."
    @State private var localCacheURLBytes: Int64 = 0
    @State private var localCacheTotalBytes: Int64 = 0
    @State private var isClearingCache = false
    @State private var showClearCacheConfirm = false
    @State private var isEditingProfileInfo = false
    @State private var draftFirstName = ""
    @State private var draftLastName = ""
    @State private var isSavingProfileInfo = false
    @State private var navigationPath: [ProfileDestination] = []

    private var displayUsername: String {
        let username = userService.currentUser?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !username.isEmpty {
            return username
        }
        let authUsername = authService.currentUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authUsername.isEmpty {
            return authUsername
        }
        return "Player"
    }

    private var profileNameParts: [String] {
        [
            userService.currentUser?.firstName ?? "",
            userService.currentUser?.lastName ?? ""
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private var displayProfileName: String {
        let fullName = profileNameParts.joined(separator: " ")
        return fullName.isEmpty ? displayUsername : fullName
    }

    private var profileNameRowValue: String {
        let fullName = profileNameParts.joined(separator: " ")
        if !fullName.isEmpty {
            return fullName
        }
        return NSLocalizedString("profile.name.not_set", comment: "Name not set")
    }

    private var firstNameValue: String {
        let firstName = userService.currentUser?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstName.isEmpty ? NSLocalizedString("profile.name.not_set", comment: "Name not set") : firstName
    }

    private var lastNameValue: String {
        let lastName = userService.currentUser?.lastName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return lastName.isEmpty ? NSLocalizedString("profile.name.not_set", comment: "Name not set") : lastName
    }

    private var avatarMonogramSource: String {
        let firstName = userService.currentUser?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !firstName.isEmpty {
            return firstName
        }

        let lastName = userService.currentUser?.lastName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !lastName.isEmpty {
            return lastName
        }

        return displayUsername
    }

    private var showsSupporterBadge: Bool {
        supporterService.activeTier != nil || userService.currentUser?.isSupporter == true
    }

    private var supporterBadgeTier: SupporterService.Tier? {
        if let activeTier = supporterService.activeTier {
            return activeTier
        }

        let rawTier = userService.currentUser?.supporterTier.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SupporterService.Tier(rawValue: rawTier)
    }

    private var supporterBadgeTitle: String {
        supporterBadgeTier?.fallbackTitle
            ?? NSLocalizedString("supporter.badge", comment: "Supporter badge")
    }

    private var cardBackground: Color {
        colorScheme == .light ? Color.white : Color.platformSecondarySystemBackground
    }

    private var pageBackground: Color {
        Color.platformSystemGroupedBackground
    }

    private var signOutButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : .black
    }

    private var signOutButtonForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var signOutButtonBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }

    private var legalInformationTitle: String {
        LegalContent.legalInformationTitle
    }

    private var dismissToolbarButton: some View {
        PressableIconButton(action: {
            withAnimation {
                isPresented = false
            }
            dismiss()
        }) {
            Label("common.close", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .frame(width: 48, height: 48)
        }
    }

    private var navigationContainer: some View {
        NavigationStack(path: $navigationPath) {
            contentRoot
        }
        .platformToolbarBackgroundVisibleForNavigationBar()
        .platformToolbarBackgroundColorForNavigationBar(Color.clear)
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { emailConfirmationError != nil },
            set: {
                if !$0 {
                    Task { @MainActor in
                        emailConfirmationError = nil
                    }
                }
            }
        )
    }

    private var emailValue: String {
        UserDefaults.standard.string(forKey: "userEmail")
            ?? userService.currentUser?.email
            ?? NSLocalizedString("profile.email.not_set", tableName: nil, bundle: .main, value: "No email", comment: "Email placeholder")
    }

    private var isEmailUnconfirmed: Bool {
        userService.currentUser?.emailConfirmed == false
    }

    private var emailUnverifiedTitle: String {
        NSLocalizedString(
            "profile.email.unverified",
            tableName: nil,
            bundle: .main,
            value: "Email not verified",
            comment: "Unverified email badge title"
        )
    }

    var body: some View {
        navigationContainer
        .onChange(of: navigationPath) { _, path in
            // When leaving profile details, drop edit mode and unsaved local name drafts.
            if !path.contains(.profileDetails) {
                resetProfileDetailsEditingState()
            }
        }
        .alert("profile.logout.title", isPresented: $showLogoutConfirm) {
            Button("profile.logout.action", role: .destructive) {
                authService.logout()
                userService.clearCachedProfile()
                isPresented = false
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("profile.logout.message")
        }
        .alert("profile.delete_account.title", isPresented: $showDeleteAccountConfirm) {
            Button("common.delete", role: .destructive) {
                Task {
                    _ = await userService.deleteAccount()
                    await MainActor.run {
                        authService.logout()
                        userService.clearCachedProfile()
                        isPresented = false
                    }
                }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("profile.delete_account.message")
        }
        .alert("profile.email.label", isPresented: $showEmailConfirmationSent) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("profile.email_confirmation.sent")
        }
        .alert("profile.birthdate.title", isPresented: $showBirthdateResultAlert) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(birthdateResultMessage ?? "")
        }
        .alert(NSLocalizedString("onboarding.field.sex", comment: "Sex field title"), isPresented: $showSexResultAlert) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(sexResultMessage ?? "")
        }
        .alert("profile.cache.clear.confirm.title", isPresented: $showClearCacheConfirm) {
            Button("profile.cache.clear", role: .destructive) {
                Task { await clearLocalCache() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("profile.cache.clear.confirm.message")
        }
        .alert("common.error", isPresented: errorAlertIsPresented) {
            Button("common.ok", role: .cancel) {
                Task { @MainActor in
                    emailConfirmationError = nil
                }
            }
        } message: {
            Text(emailConfirmationError ?? "")
        }
        .sheet(isPresented: $isBirthdatePickerPresented) {
            birthdatePickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        }
        .task {
            await userService.fetchCurrentUser()
            profileAppearance = userService.profileAppearance
            syncProfileNameDrafts(from: userService.currentUser)
            syncBirthdateState(from: userService.currentUser)
            syncSexState(from: userService.currentUser)
            refreshLocalCacheSize()
        }
        .onReceive(userService.$currentUser) { user in
            Task { @MainActor in
                profileAppearance = userService.profileAppearance
                syncProfileNameDrafts(from: user)
                syncBirthdateState(from: user)
                syncSexState(from: user)
            }
        }
        .onReceive(userService.$profileAppearance) { appearance in
            Task { @MainActor in
                profileAppearance = appearance
            }
        }
    }

    private var contentRoot: some View {
        ZStack(alignment: .top) {
            profileContent
                .background(pageBackground.ignoresSafeArea())
        }
        .navigationTitle(Text(NSLocalizedString("profile.section.profile", tableName: nil, bundle: .main, value: "Profile", comment: "Profile sheet title")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .platformTopBarLeading) {
                dismissToolbarButton
                    .padding(16)
            }
        }
        .navigationDestination(for: ProfileDestination.self, destination: profileDestinationView)
    }

    @ViewBuilder
    private func profileDestinationView(for destination: ProfileDestination) -> some View {
        switch destination {
        case .profileDetails:
            profileDetailsView
        case .credentialsSettings:
            credentialsSettingsView
        case .notificationsSettings:
            notificationsSettingsView
        case .nutritionSettings:
            nutritionSettingsView
        case .managementSettings:
            managementSettingsView
        case .adminPanel:
            AdminPanelView(authService: authService)
        case .appIcon:
            AppIconPickerView()
        case .name:
            ChangeProfileNameSheet(
                initialFirstName: userService.currentUser?.firstName ?? "",
                initialLastName: userService.currentUser?.lastName ?? "",
                showsCloseButton: false
            )
        case .username:
            ChangeUsernameSheet(showsCloseButton: false)
        case .email:
            emailDestinationView
        case .supporter:
            SupporterSheetView()
        case let .nutrition(destination):
            nutritionDestinationView(for: destination)
        }
    }

    private var emailDestinationView: some View {
        ChangeEmailSheet(showsCloseButton: false, onSent: { success in
            if success {
                showEmailConfirmationSent = true
            }
        })
    }

    private var birthdatePickerSheet: some View {
        ChangeBirthdateSheet(initialBirthdate: birthdate) { savedBirthdate, success, error in
            if success {
                birthdate = savedBirthdate
                hasBirthdate = true
                birthdateResultMessage = NSLocalizedString("profile.birthdate.saved", comment: "Birthdate saved")
            } else {
                birthdateResultMessage = error ?? NSLocalizedString("profile.birthdate.save_error", comment: "Birthdate save error")
            }
            showBirthdateResultAlert = true
        }
    }

    private func nutritionDestinationView(for destination: NutritionPreferencesDestination) -> some View {
        Group {
            switch destination {
            case .dietPlan:
                NutritionPreferencesSheet(mode: .dietPlan)
            case .calorieGoal:
                NutritionPreferencesSheet(mode: .calorieGoal)
            case .mealSlots:
                NutritionPreferencesSheet(mode: .mealSlots)
            case .waterGoal:
                WaterGoalSettingsView()
                    .environmentObject(diaryService)
            }
        }
    }

    private var profileContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    ProfileAvatarView(
                        username: avatarMonogramSource,
                        appearance: profileAppearance,
                        size: 92
                    )

                    Text(displayProfileName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                VStack(spacing: 0) {
                    NavigationLink(value: ProfileDestination.profileDetails) {
                        disclosureRow(
                            title: NSLocalizedString("profile.section.profile", tableName: nil, bundle: .main, value: "Profile", comment: "Profile section row")
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 16)

                    NavigationLink(value: ProfileDestination.nutritionSettings) {
                        disclosureRow(
                            title: NSLocalizedString("profile.section.nutrition", comment: "Nutrition section title")
                        )
                    }
                    .buttonStyle(.plain)

                }
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 10) {
                    Text(NSLocalizedString("profile.section.functions", tableName: nil, bundle: .main, value: "Functions", comment: "Functions section title"))
                        .font(.headline)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        NavigationLink(value: ProfileDestination.notificationsSettings) {
                            disclosureRow(
                                title: NSLocalizedString("settings.section.notifications", comment: "Notifications section title")
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 16)

                        NavigationLink(value: ProfileDestination.appIcon) {
                            disclosureRow(
                                title: NSLocalizedString("settings.app_icon.title", tableName: nil, bundle: .main, value: "App icon", comment: "App icon settings title")
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 16)

                        NavigationLink(value: ProfileDestination.managementSettings) {
                            disclosureRow(
                                title: NSLocalizedString("profile.section.management", comment: "Management section title")
                            )
                        }
                        .buttonStyle(.plain)

                        if userService.currentUser?.role == .admin {
                            Divider().padding(.leading, 16)

                            NavigationLink(value: ProfileDestination.adminPanel) {
                                disclosureRow(
                                    title: NSLocalizedString("admin.panel.title", tableName: nil, bundle: .main, value: "Admin", comment: "Admin panel row title")
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(NSLocalizedString("profile.section.privacy", tableName: nil, bundle: .main, value: "Privacy", comment: "Privacy section title"))
                        .font(.headline)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        NavigationLink(value: ProfileDestination.credentialsSettings) {
                            disclosureRow(
                                title: NSLocalizedString("profile.privacy.credentials", tableName: nil, bundle: .main, value: "Credentials", comment: "Credentials row title")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(NSLocalizedString("profile.section.information", tableName: nil, bundle: .main, value: "Information", comment: "Information section title"))
                        .font(.headline)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        Button {
                            openURL(LegalContent.publicURL)
                        } label: {
                            disclosureRow(
                                title: legalInformationTitle
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                }

                VStack(spacing: 12) {
                    PressableIconButton(action: { showDeleteAccountConfirm = true }) {
                        Text("profile.delete_account.row")
                            .font(.headline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }

                Button {
                    showLogoutConfirm = true
                } label: {
                    Text("profile.logout.action")
                        .font(.headline)
                        .foregroundColor(signOutButtonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(signOutButtonBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                                .stroke(signOutButtonBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    private var notificationsSettingsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    Button(action: openNotificationSettings) {
                        disclosureRow(title: NSLocalizedString("settings.notifications.system", comment: "Open system notification settings"))
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 16)

                    toggleSettingRow(
                        titleText: NSLocalizedString("settings.notifications.meal_reminders", comment: "Meal reminders toggle title"),
                        isOn: diaryService.mealRemindersEnabled
                    ) { newValue in
                        Task { await diaryService.setMealRemindersEnabled(newValue) }
                    }

                    Divider().padding(.leading, 16)

                    toggleSettingRow(
                        titleText: NSLocalizedString("settings.notifications.useful", comment: "Useful notifications toggle title"),
                        isOn: diaryService.usefulNotificationsEnabled
                    ) { newValue in
                        Task { await diaryService.setUsefulNotificationsEnabled(newValue) }
                    }

                    Divider().padding(.leading, 16)

                    toggleSettingRow(
                        titleText: NSLocalizedString(
                            "settings.notifications.habits",
                            tableName: nil,
                            bundle: .main,
                            value: "Habit notifications",
                            comment: "Habit notifications toggle title"
                        ),
                        isOn: diaryService.habitNotificationsEnabled,
                        tint: .orange
                    ) { newValue in
                        Task {
                            await diaryService.setHabitNotificationsEnabled(newValue)
                            HabitLocalNotificationScheduler.shared.refreshReminders(for: habitsService.habits)
                        }
                    }

                    Divider().padding(.leading, 16)

                    toggleSettingRow(
                        titleText: NSLocalizedString(
                            "settings.notifications.water_logging",
                            tableName: nil,
                            bundle: .main,
                            value: "Remind to log water",
                            comment: "Water logging notifications toggle title"
                        ),
                        isOn: diaryService.waterLoggingRemindersEnabled,
                        tint: .blue
                    ) { newValue in
                        Task { await diaryService.setWaterLoggingRemindersEnabled(newValue) }
                    }
                }
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle(Text("settings.section.notifications"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var nutritionSettingsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    NavigationLink(value: ProfileDestination.nutrition(.dietPlan)) {
                        settingRow(
                            title: "profile.nutrition.diet_plan",
                            value: diaryService.dietPlan.title
                        )
                        .accentColor(.primary)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 16)

                    NavigationLink(value: ProfileDestination.nutrition(.calorieGoal)) {
                        settingRow(
                            title: "profile.nutrition.calorie_goal",
                            value: String(format: NSLocalizedString("today.kcal_value", comment: "Calories value"), diaryService.dailyGoal.calories)
                        )
                        .accentColor(.primary)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 16)

                    NavigationLink(value: ProfileDestination.nutrition(.mealSlots)) {
                        settingRow(
                            title: "profile.nutrition.meal_slots",
                            value: String(format: NSLocalizedString("profile.meal_slots.count", comment: "Meal slots count"), diaryService.visibleMealCategories.filter(\.isEnabled).count)
                        )
                        .accentColor(.primary)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 16)

                    toggleSettingRow(
                        titleText: NSLocalizedString(
                            "profile.nutrition.track_water",
                            tableName: nil,
                            bundle: .main,
                            value: "Track water",
                            comment: "Track water toggle title"
                        ),
                        isOn: appSettings.isWaterTrackingEnabled
                    ) { newValue in
                        appSettings.setWaterTrackingEnabled(newValue)
                    }

                    if appSettings.isWaterTrackingEnabled {
                        Divider().padding(.leading, 16)

                        NavigationLink(value: ProfileDestination.nutrition(.waterGoal)) {
                            settingRow(
                                title: "profile.nutrition.water_goal",
                                value: String(format: NSLocalizedString("water.goal.preset_ml", comment: "Water goal value"), Double(diaryService.dailyWaterGoalMilliliters) / 1000.0)
                            )
                            .accentColor(.primary)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 16)

                        Menu {
                            ForEach([50, 100, 150, 200, 250, 300, 500, 750, 1000], id: \.self) { value in
                                Button {
                                    appSettings.setWaterWidgetStepMilliliters(value)
                                } label: {
                                    if appSettings.waterWidgetStepMilliliters == value {
                                        Label(
                                            String(format: NSLocalizedString("profile.nutrition.water_step_value", comment: "Water step value"), value),
                                            systemImage: "checkmark"
                                        )
                                    } else {
                                        Text(String(format: NSLocalizedString("profile.nutrition.water_step_value", comment: "Water step value"), value))
                                    }
                                }
                            }
                        } label: {
                            menuSettingRow(
                                title: "profile.nutrition.water_widget_step",
                                value: String(format: NSLocalizedString("profile.nutrition.water_step_value", comment: "Water step value"), appSettings.waterWidgetStepMilliliters)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle(Text("profile.section.nutrition"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var managementSettingsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text(NSLocalizedString("profile.cache.title", comment: "Cache row title"))
                                .foregroundStyle(.primary)
                            Spacer()
                            Button("profile.cache.clear") {
                                showClearCacheConfirm = true
                            }
                            .disabled(isClearingCache)
                            .foregroundColor(.blue)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .padding(.horizontal, 16)

                        VStack(spacing: 6) {
                            GeometryReader { geo in
                                let total = max(1, localCacheTotalBytes)
                                let urlRatio = CGFloat(localCacheURLBytes) / CGFloat(total)
                                let otherRatio = CGFloat(max(0, localCacheTotalBytes - localCacheURLBytes)) / CGFloat(total)
                                HStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.blue)
                                        .frame(width: geo.size.width * urlRatio)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.orange)
                                        .frame(width: geo.size.width * otherRatio)
                                    Spacer(minLength: 0)
                                }
                                .frame(height: 4)
                            }
                            .frame(height: 4)

                            HStack {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.blue).frame(width: 7, height: 7)
                                    Text(NSLocalizedString("profile.cache.url", comment: "URL cache label"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(ByteCountFormatter.string(fromByteCount: localCacheURLBytes, countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                HStack(spacing: 4) {
                                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                                    Text(NSLocalizedString("profile.cache.other", comment: "Other cache label"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(ByteCountFormatter.string(fromByteCount: max(0, localCacheTotalBytes - localCacheURLBytes), countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                }
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle(Text("profile.section.management"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var credentialsSettingsView: some View {
        Form {
            Section("Apple ID") {
                LabeledContent("Имя", value: userService.currentUser?.name.isEmpty == false ? userService.currentUser?.name ?? "" : "Не указано")
                emailCredentialRow
            }

            Section {
                Label("Вход выполняется только через Apple ID", systemImage: "apple.logo")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Учётная запись")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var profileDetailsView: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    ProfileAvatarView(
                        username: avatarMonogramSource,
                        appearance: profileAppearance,
                        size: 88
                    )
                    Spacer()
                }

            }

            Section("Личные данные") {
                TextField("Имя", text: $draftFirstName)
                    .textContentType(.name)
                    .submitLabel(.done)

                emailCredentialRow

                Button("Сохранить имя") {
                    let name = draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    isSavingProfileInfo = true
                    Task {
                        _ = await userService.updateName(name)
                        isSavingProfileInfo = false
                    }
                }
                .disabled(isSavingProfileInfo || draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section {
                Text("Возраст, пол, рост, вес и цель относятся только к профилю здоровья Eatometer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var legacyProfileDetailsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    // No "edit" button under it any more: the avatar is drawn
                    // from the name and there is nothing left to choose.
                    ProfileAvatarView(
                        username: avatarMonogramSource,
                        appearance: profileAppearance,
                        size: 88
                    )
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 0) {

                    if isEditingProfileInfo {
                        editableProfileTextRow(
                            title: NSLocalizedString("profile.name.first.placeholder", comment: "First name"),
                            text: $draftFirstName
                        )
                    } else {
                        profileRow(
                            title: NSLocalizedString("profile.name.first.placeholder", comment: "First name"),
                            value: firstNameValue,
                            showsDisclosure: false
                        )
                    }

                    Divider().padding(.leading, 16)

                    if isEditingProfileInfo {
                        editableProfileTextRow(
                            title: NSLocalizedString("profile.name.last.placeholder", comment: "Last name"),
                            text: $draftLastName
                        )
                    } else {
                        profileRow(
                            title: NSLocalizedString("profile.name.last.placeholder", comment: "Last name"),
                            value: lastNameValue,
                            showsDisclosure: false
                        )
                    }

                    Divider().padding(.leading, 16)

                    if isEditingProfileInfo {
                        Button {
                            isBirthdatePickerPresented = true
                        } label: {
                            HStack {
                                Text("profile.birthdate.title")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(hasBirthdate ? birthdate.formatted(.dateTime.day().month().year()) : NSLocalizedString("profile.birthdate.not_set", comment: "Birthdate not set"))
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        profileRow(
                            title: NSLocalizedString("profile.birthdate.title", comment: "Birthdate title"),
                            value: hasBirthdate ? birthdate.formatted(.dateTime.day().month().year()) : NSLocalizedString("profile.birthdate.not_set", comment: "Birthdate not set"),
                            showsDisclosure: false
                        )
                    }

                    Divider().padding(.leading, 16)

                    if isEditingProfileInfo {
                        Menu {
                            ForEach(Self.sexOptions) { option in
                                Button(option.title) {
                                    updateSex(option.value)
                                }
                            }
                        } label: {
                            HStack {
                                Text(NSLocalizedString("onboarding.field.sex", comment: "Sex field title"))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(displayName(for: selectedSex))
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        profileRow(
                            title: NSLocalizedString("onboarding.field.sex", comment: "Sex field title"),
                            value: displayName(for: selectedSex),
                            showsDisclosure: false
                        )
                    }
                }
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle(
            Text(
                NSLocalizedString(
                    "profile.section.profile",
                    tableName: nil,
                    bundle: .main,
                    value: "Profile",
                    comment: "Profile section title"
                )
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSavingProfileInfo {
                    ProgressView()
                } else {
                    Button(isEditingProfileInfo ? "common.done" : "profile.edit.action") {
                        if isEditingProfileInfo {
                            saveProfileInfoChanges()
                        } else {
                            isEditingProfileInfo = true
                        }
                    }
                }
            }
        }
    }

    private var profileEntryCard: some View {
        NavigationLink(value: ProfileDestination.profileDetails) {
            HStack(spacing: 14) {
                ProfileAvatarView(
                    username: avatarMonogramSource,
                    appearance: profileAppearance,
                    size: 58
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayProfileName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    private func profileRow(title: String, value: String? = nil, showsDisclosure: Bool = true) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private var emailCredentialRow: some View {
        HStack(spacing: 8) {
            NavigationLink(value: ProfileDestination.email) {
                HStack(spacing: 12) {
                    Text(NSLocalizedString("profile.email.label", comment: "Email"))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(emailValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if isEmailUnconfirmed {
                            Label(emailUnverifiedTitle, systemImage: "exclamationmark.circle.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func editableProfileTextRow(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            TextField("", text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.words)
                .foregroundStyle(.blue)
                .frame(maxWidth: 180)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func menuSettingRow(title: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 6) {
                Text(LocalizedStringKey(value))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func settingRow(title: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 4) {
                Text(LocalizedStringKey(value))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private enum DisclosureRowIconPlacement {
        case leading
        case trailing
    }

    private func disclosureRow(
        title: String,
        systemImage: String? = nil,
        iconColor: Color = .primary,
        iconPlacement: DisclosureRowIconPlacement = .leading
    ) -> some View {
        HStack {
            if let systemImage, iconPlacement == .leading {
                disclosureRowIcon(systemImage: systemImage, iconColor: iconColor)
            }

            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            if let systemImage, iconPlacement == .trailing {
                disclosureRowIcon(systemImage: systemImage, iconColor: iconColor)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func disclosureRowIcon(systemImage: String, iconColor: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 24)
    }

    private func toggleSettingRow(titleText: String, isOn: Bool, tint: Color = .green, onToggle: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(titleText)
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { onToggle($0) }))
                .labelsHidden()
                .tint(tint)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func refreshLocalCacheSize() {
        Task.detached(priority: .utility) {
            let bytes = Self.computeLocalCacheSizeBytes()
            let urlBytes = Int64(URLCache.shared.currentDiskUsage)
            let text = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            await MainActor.run {
                localCacheSizeText = text
                localCacheTotalBytes = bytes
                localCacheURLBytes = min(urlBytes, bytes)
            }
        }
    }

    private nonisolated static func computeLocalCacheSizeBytes() -> Int64 {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return 0
        }
        return directorySize(at: cachesURL)
    }

    private func clearLocalCache() async {
        guard !isClearingCache else { return }

        await MainActor.run {
            isClearingCache = true
            localCacheSizeText = ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)
            localCacheTotalBytes = 0
            localCacheURLBytes = 0
        }

        URLCache.shared.removeAllCachedResponses()

        if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let items = try? FileManager.default.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil) {
            for item in items {
                try? FileManager.default.removeItem(at: item)
            }
        }

        await MainActor.run {
            isClearingCache = false
            localCacheSizeText = ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)
            localCacheTotalBytes = 0
            localCacheURLBytes = 0
            refreshLocalCacheSize()
        }
    }

    private nonisolated static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }

        var total: Int64 = 0
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) {
            for case let fileURL as URL in enumerator {
                guard
                    let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                    values.isRegularFile == true,
                    let size = values.fileSize
                else {
                    continue
                }
                total += Int64(size)
            }
        }

        return total
    }

    private func syncProfileNameDrafts(from user: User_User?) {
        draftFirstName = (user?.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        draftLastName = (user?.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetProfileDetailsEditingState() {
        guard isEditingProfileInfo else { return }
        isEditingProfileInfo = false
        syncProfileNameDrafts(from: userService.currentUser)
    }

    private func saveProfileInfoChanges() {
        let firstName = draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastName = draftLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentFirstName = (userService.currentUser?.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let currentLastName = (userService.currentUser?.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard firstName != currentFirstName || lastName != currentLastName else {
            isEditingProfileInfo = false
            return
        }

        isSavingProfileInfo = true
        Task {
            let (ok, error) = await userService.setProfileName(firstName: firstName, lastName: lastName)
            await MainActor.run {
                isSavingProfileInfo = false
                if ok {
                    isEditingProfileInfo = false
                } else {
                    emailConfirmationError = error ?? NSLocalizedString("profile.name.failed", comment: "Profile name update failed")
                }
            }
        }
    }

    private func syncBirthdateState(from user: User_User?) {
        if let date = extractBirthdate(from: user) {
            birthdate = date
            hasBirthdate = true
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "userBirthdate")
        } else if let ts = UserDefaults.standard.object(forKey: "userBirthdate") as? TimeInterval {
            birthdate = Date(timeIntervalSince1970: ts)
            hasBirthdate = true
        } else {
            hasBirthdate = false
        }
    }

    private func syncSexState(from user: User_User?) {
        // Sex belongs to the Eatometer health profile and is no longer part of
        // the platform-wide user returned by UsersService.
        selectedSex = .preferNotToSay
    }

    private func updateSex(_ sex: User_UserSex) {
        let nextSex = normalizedSex(sex)
        let previousSex = selectedSex
        selectedSex = nextSex
        Task {
            let result = await userService.setSex(nextSex)
            if !result.0 {
                await MainActor.run {
                    selectedSex = previousSex
                    sexResultMessage = result.1 ?? NSLocalizedString("common.error", comment: "Fallback profile save error")
                    showSexResultAlert = true
                }
            }
        }
    }

    private func normalizedSex(_ sex: User_UserSex) -> User_UserSex {
        switch sex {
        case .male, .female, .preferNotToSay:
            return sex
        default:
            return .preferNotToSay
        }
    }

    private func displayName(for sex: User_UserSex) -> String {
        switch normalizedSex(sex) {
        case .male:
            return NSLocalizedString("onboarding.sex.male.title", comment: "Male sex option")
        case .female:
            return NSLocalizedString("onboarding.sex.female.title", comment: "Female sex option")
        case .preferNotToSay:
            return NSLocalizedString("onboarding.sex.not_set.title", comment: "Prefer not to say sex option")
        default:
            return NSLocalizedString("onboarding.sex.not_set.title", comment: "Prefer not to say sex option")
        }
    }

    private static let sexOptions: [ProfileSexOption] = [
        ProfileSexOption(id: "male", value: .male, title: NSLocalizedString("onboarding.sex.male.title", comment: "Male sex option")),
        ProfileSexOption(id: "female", value: .female, title: NSLocalizedString("onboarding.sex.female.title", comment: "Female sex option")),
        ProfileSexOption(id: "prefer_not_to_say", value: .preferNotToSay, title: NSLocalizedString("onboarding.sex.not_set.title", comment: "Prefer not to say sex option"))
    ]

    private func extractBirthdate(from user: User_User?) -> Date? {
        guard let user else { return nil }
        if let json = try? user.jsonString(), let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let val = obj["birthdate"] as? String {
                let iso = ISO8601DateFormatter()
                if let date = iso.date(from: val) { return date }
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                if let date = df.date(from: val) { return date }
                df.dateFormat = "yyyy-MM-dd"
                if let date = df.date(from: val) { return date }
            }
            if let num = obj["birthdate"] as? Double { return Date(timeIntervalSince1970: num) }
            if let num = obj["birthdate"] as? Int { return Date(timeIntervalSince1970: TimeInterval(num)) }
        }
        return nil
    }

    private func openNotificationSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }
}

private struct ProfileSexOption: Identifiable {
    let id: String
    let value: User_UserSex
    let title: String
}

struct NotificationInboxView: View {
    @StateObject private var pushNotificationService = PushNotificationService.shared
    @State private var readerItem: AppNotificationInboxItem?
    @State private var showMarkAllReadConfirmation = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var showRemoveSelectedConfirmation = false

    private var titleText: String {
        NSLocalizedString(
            "profile.notifications.inbox.title",
            tableName: nil,
            bundle: .main,
            value: "Notifications",
            comment: "Notification inbox title"
        )
    }

    private var markAllReadAccessibilityTitle: String {
        NSLocalizedString(
            "profile.notifications.mark_all_read",
            tableName: nil,
            bundle: .main,
            value: "Mark all as read",
            comment: "Mark all notifications as read"
        )
    }

    var body: some View {
        Group {
            if pushNotificationService.inboxItems.isEmpty {
                VStack {
                    Spacer()
                    emptyState
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: EOTheme.Metrics.headerSpacing) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(pushNotificationService.inboxItems.enumerated()), id: \.element.id) { index, item in
                                inboxRow(item)

                                if index < pushNotificationService.inboxItems.count - 1 {
                                    EORowSeparator()
                                }
                            }
                        }
                        .background(EOTheme.Palette.card)
                        .clipShape(
                            RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                        )

                        if !isSelecting {
                            Text("common.context_menu_hint")
                                .font(EOTheme.Typography.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, EOTheme.Metrics.cardInset)
                                .padding(.top, 4)
                        }
                    }
                    .eoCardInsets()
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .animation(.none, value: pushNotificationService.unreadCount)
            }
        }
        .eoPageBackground()
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .platformTopBarTrailing) {
                if isSelecting {
                    Button {
                        showRemoveSelectedConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.primary)
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityLabel(Text("common.delete"))

                    // A plain button rather than `role: .close`: the close role
                    // gets its own glass container, which would split the pair
                    // into two capsules instead of one group.
                    Button {
                        exitSelectionMode()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(.primary)
                    .accessibilityLabel(Text("common.close"))
                } else {
                    Menu {
                        Button {
                            showMarkAllReadConfirmation = true
                        } label: {
                            Label("profile.notifications.read_all", systemImage: "tray")
                        }
                        .disabled(pushNotificationService.unreadCount == 0)

                        Button {
                            isSelecting = true
                            selectedIDs = []
                        } label: {
                            Label("profile.notifications.choose_items", systemImage: "checkmark.circle")
                        }
                        .disabled(pushNotificationService.inboxItems.isEmpty)

                        EODestructiveMenuButton("profile.notifications.delete_all", systemImage: "trash") {
                            selectedIDs = Set(pushNotificationService.inboxItems.map(\.id))
                            showRemoveSelectedConfirmation = true
                        }
                        .disabled(pushNotificationService.inboxItems.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.primary)
                }
            }
        }
        .confirmationDialog(
            Text("profile.notifications.remove.confirm.title"),
            isPresented: $showRemoveSelectedConfirmation,
            titleVisibility: .visible
        ) {
            Button("profile.notifications.remove", role: .destructive) {
                removeSelectedNotifications()
            }
            Button("common.cancel", role: .cancel) {}
        }
        .task {
            await pushNotificationService.refreshInbox()
        }
        .alert(
            NSLocalizedString(
                "profile.notifications.mark_all_read.confirm.title",
                tableName: nil,
                bundle: .main,
                value: "Mark all as read?",
                comment: "Confirm mark all notifications as read title"
            ),
            isPresented: $showMarkAllReadConfirmation
        ) {
            Button(
                NSLocalizedString(
                    "profile.notifications.mark_all_read",
                    tableName: nil,
                    bundle: .main,
                    value: "Mark all as read",
                    comment: "Mark all notifications as read"
                )
            ) {
                markAllNotificationsAsReadWithoutAnimation()
            }
            Button(
                NSLocalizedString(
                    "common.cancel",
                    tableName: nil,
                    bundle: .main,
                    value: "Cancel",
                    comment: "Cancel"
                ),
                role: .cancel
            ) {}
        } message: {
            Text(
                NSLocalizedString(
                    "profile.notifications.mark_all_read.confirm.message",
                    tableName: nil,
                    bundle: .main,
                    value: "All notifications will be marked as read.",
                    comment: "Confirm mark all notifications as read message"
                )
            )
        }
        .sheet(item: $readerItem) { item in
            NotificationReaderSheet(
                item: item,
                onMarkAsRead: {
                    markNotificationAsReadWithoutAnimation(item.id)
                    if readerItem?.id == item.id {
                        var updated = item
                        updated.isRead = true
                        readerItem = updated
                    }
                },
                onOpenRelated: item.hasNavigationTarget ? {
                    pushNotificationService.openInboxItem(item)
                } : nil
            )
        }
    }


    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text(NSLocalizedString(
                    "profile.notifications.empty.title",
                    tableName: nil,
                    bundle: .main,
                    value: "No notifications yet",
                    comment: "Notification inbox empty title"
                ))
                .font(.headline)
                .foregroundStyle(.primary)

                Text(NSLocalizedString(
                    "profile.notifications.empty.subtitle",
                    tableName: nil,
                    bundle: .main,
                    value: "New push notifications will appear here.",
                    comment: "Notification inbox empty subtitle"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func inboxRow(_ item: AppNotificationInboxItem) -> some View {
        HStack(spacing: 0) {
            if isSelecting {
                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        selectedIDs.contains(item.id)
                            ? EOTheme.Palette.accent
                            : Color.secondary.opacity(0.4)
                    )
                    .padding(.leading, EOTheme.Metrics.cardInset)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            // The unread mark, on the leading edge and holding its space when
            // there is nothing to mark.
            //
            // It used to sit on the right, an eight-point dot tucked against
            // the chevron, where it read as part of the disclosure rather than
            // as a state of the message. Here it is where every mail client
            // puts it — the first thing on the row — and the reserved width
            // keeps titles on one line whether or not the dot is drawn.
            Circle()
                .fill(item.isRead ? Color.clear : EOTheme.Palette.accent)
                .frame(width: 9, height: 9)
                .padding(.leading, isSelecting ? 10 : EOTheme.Metrics.cardInset)
                .padding(.trailing, -2)
                .accessibilityHidden(true)

            EOListRow(
                title: Text(verbatim: item.title.isEmpty ? fallbackTitle(for: item) : item.title)
                    .fontWeight(item.isRead ? .regular : .semibold),
                subtitle: Text(verbatim: relativeDateText(for: item.receivedAt))
            ) {
                EOChevron()
            }
            // Said aloud as well as drawn: the dot is the only thing
            // distinguishing the two states, and it is invisible to VoiceOver.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                item.isRead
                    ? Text(verbatim: item.title)
                    : Text("profile.notifications.unread.accessibility \(item.title)")
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggleSelection(item.id)
            } else {
                openNotificationReader(item)
            }
        }
        .eoRowContextMenu {
            if !item.isRead {
                Button {
                    markNotificationAsReadWithoutAnimation(item.id)
                } label: {
                    Label(
                        NSLocalizedString(
                            "profile.notifications.mark_read",
                            tableName: nil,
                            bundle: .main,
                            value: "Mark as read",
                            comment: "Mark notification as read"
                        ),
                        systemImage: "envelope.open"
                    )
                }
            }

            EODestructiveMenuButton(title: Text(verbatim: deleteNotificationTitle), systemImage: "trash") {
                deleteNotification(item)
            }

            EODestructiveMenuButton(title: Text(verbatim: clearAllNotificationsTitle), systemImage: "trash") {
                deleteAllNotificationsWithoutAnimation()
            }
        }
    }

    private func toggleSelection(_ id: String) {
        withAnimation(.snappy(duration: 0.18)) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        }
    }

    private func exitSelectionMode() {
        withAnimation(.snappy(duration: 0.22)) {
            isSelecting = false
            selectedIDs = []
        }
    }

    private func removeSelectedNotifications() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }

        let offsets = IndexSet(
            pushNotificationService.inboxItems.enumerated()
                .filter { ids.contains($0.element.id) }
                .map(\.offset)
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pushNotificationService.deleteInboxItems(atOffsets: offsets)
        }
        exitSelectionMode()
    }

    private var deleteNotificationTitle: String {
        NSLocalizedString(
            "profile.notifications.delete",
            tableName: nil,
            bundle: .main,
            value: "Delete Notification",
            comment: "Delete a single notification"
        )
    }

    private var deleteActionTitle: String {
        NSLocalizedString(
            "common.delete",
            tableName: nil,
            bundle: .main,
            value: "Delete",
            comment: "Delete action"
        )
    }

    private var clearAllNotificationsTitle: String {
        NSLocalizedString(
            "profile.notifications.clear_all",
            tableName: nil,
            bundle: .main,
            value: "Clear all notifications",
            comment: "Clear all notifications action"
        )
    }

    private func openNotificationReader(_ item: AppNotificationInboxItem) {
        readerItem = item
    }

    private func markNotificationAsReadWithoutAnimation(_ id: String) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pushNotificationService.markNotificationAsRead(id: id)
        }
    }

    private func markAllNotificationsAsReadWithoutAnimation() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pushNotificationService.markAllNotificationsAsRead()
        }
    }

    private func deleteAllNotificationsWithoutAnimation() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pushNotificationService.deleteAllInboxItems()
        }
    }

    private func deleteNotification(_ item: AppNotificationInboxItem) {
        guard let index = pushNotificationService.inboxItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        pushNotificationService.deleteInboxItems(atOffsets: IndexSet(integer: index))
    }

    private func relativeDateText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func fallbackTitle(for item: AppNotificationInboxItem) -> String {
        if item.targetScreen == "diary" {
            return NSLocalizedString(
                "profile.notifications.fallback.diary",
                tableName: nil,
                bundle: .main,
                value: "Diary update",
                comment: "Fallback title for diary notification"
            )
        }

        return NSLocalizedString(
            "profile.notifications.fallback.generic",
            tableName: nil,
            bundle: .main,
            value: "Notification",
            comment: "Fallback title for generic notification"
        )
    }
}

private struct NotificationReaderSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: AppNotificationInboxItem
    let onMarkAsRead: (() -> Void)?
    let onOpenRelated: (() -> Void)?
    @State private var isRead: Bool

    private var readerText: String? {
        let preferredText = item.newsText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preferredText, !preferredText.isEmpty {
            return preferredText
        }

        let fallbackText = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackText.isEmpty ? nil : fallbackText
    }

    init(
        item: AppNotificationInboxItem,
        onMarkAsRead: (() -> Void)? = nil,
        onOpenRelated: (() -> Void)? = nil
    ) {
        self.item = item
        self.onMarkAsRead = onMarkAsRead
        self.onOpenRelated = onOpenRelated
        _isRead = State(initialValue: item.isRead)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                    readerCard
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .eoCardInsets()
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .eoPageBackground()
            .eoSheetChrome(
                title: Text(
                    NSLocalizedString(
                        "profile.notifications.fallback.generic",
                        tableName: nil,
                        bundle: .main,
                        value: "Notification",
                        comment: "Notification reader sheet title"
                    )
                ),
                onClose: { dismiss() }
            ) {
                Button {
                    guard !isRead else { return }
                    onMarkAsRead?()
                    isRead = true
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(isRead ? Color.secondary.opacity(0.35) : EOTheme.Palette.accent)
                .disabled(isRead)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var readerCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: displayTitle)
                    .font(.title3.weight(.regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, EOTheme.Metrics.cardInset)
            .padding(.top, EOTheme.Metrics.cardInset)
            .padding(.bottom, 16)

            if let displayMessageText {
                EORowSeparator()

                Text(displayMessageText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
                    .padding(.vertical, 18)
                    .frame(minHeight: 88, alignment: .topLeading)
            }

            if let onOpenRelated {
                EORowSeparator()

                Button {
                    Task { @MainActor in
                        dismiss()
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        onOpenRelated()
                    }
                } label: {
                    Text(openRelatedTitle)
                        .font(.body.weight(.regular))
                        .foregroundStyle(EOTheme.Palette.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                .fill(EOTheme.Palette.card)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
        )
    }

    private var openRelatedTitle: String {
        NSLocalizedString(
            isMealNavigationTarget ? "profile.notifications.open_meal_sheet" : "profile.notifications.open_related",
            tableName: nil,
            bundle: .main,
            value: isMealNavigationTarget ? "Open meal" : "Go",
            comment: "Open related screen from notification"
        )
    }

    private var displayTitle: String {
        if isMealNavigationTarget {
            return NSLocalizedString(
                "profile.notifications.meal_reminder.title",
                tableName: nil,
                bundle: .main,
                value: "Meal reminder",
                comment: "Notification reader title for meal reminders"
            )
        }

        return item.title.isEmpty ? fallbackTitle : item.title
    }

    private var displayMessageText: String? {
        if isMealNavigationTarget {
            return NSLocalizedString(
                "profile.notifications.meal_reminder.message",
                tableName: nil,
                bundle: .main,
                value: "Don't forget to log what you ate.",
                comment: "Notification reader message for meal reminders"
            )
        }

        return readerText
    }

    private var subtitleText: String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(item.receivedAt) {
            return item.receivedAt.formatted(date: .omitted, time: .shortened)
        }

        return item.receivedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var isMealNavigationTarget: Bool {
        if item.targetScreen == "diary" {
            return true
        }
        if hasText(item.mealID) || hasText(item.mealSlotID) {
            return true
        }
        guard let destinationURL = item.destinationURL else { return false }
        return destinationURL.host == "diary" || destinationURL.path.contains("diary")
    }

    private func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var fallbackTitle: String {
        if item.targetScreen == "diary" {
            return NSLocalizedString(
                "profile.notifications.fallback.diary",
                tableName: nil,
                bundle: .main,
                value: "Diary update",
                comment: "Fallback title for diary notification"
            )
        }

        return NSLocalizedString(
            "profile.notifications.fallback.generic",
            tableName: nil,
            bundle: .main,
            value: "Notification",
            comment: "Fallback title for generic notification"
        )
    }

}
