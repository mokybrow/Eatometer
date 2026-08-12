import SwiftUI

enum EatometerBiologicalSex: String, Sendable, Equatable, CaseIterable {
    case female
    case male
    case other
    case notSet
}

struct EatometerOnboardingView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var diaryService: FoodDiaryService

    @State private var step: Step = .welcome
    @State private var age = 24
    @State private var weight = 72
    @State private var height = 175
    @State private var sex: Sex = .notSpecified
    @State private var activity: Activity = .medium
    @State private var goal: Goal = .maintain
    @State private var isHealthAccessEnabled = false
    @State private var isSaving = false
    @State private var stepDirection = 1

    private enum Step: Int, CaseIterable {
        case welcome
        case parameters
        case goal
        case finishing
    }

    private enum Sex: String, CaseIterable, Identifiable {
        case female
        case male
        case notSpecified

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .female: "onboarding.sex.female.title"
            case .male: "onboarding.sex.male.title"
            case .notSpecified: "onboarding.sex.not_set.title"
            }
        }

        var serviceValue: EatometerBiologicalSex {
            switch self {
            case .female: .female
            case .male: .male
            case .notSpecified: .notSet
            }
        }
    }

    private enum Activity: String, CaseIterable, Identifiable {
        case low = "light"
        case medium = "moderate"
        case high = "active"

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .low: "onboarding.activity.light.title"
            case .medium: "onboarding.activity.moderate.title"
            case .high: "onboarding.activity.active.title"
            }
        }

        var multiplier: Double {
            switch self {
            case .low: 1.375
            case .medium: 1.55
            case .high: 1.725
            }
        }
    }

    private enum Goal: String, CaseIterable, Identifiable {
        case lose
        case maintain
        case gain

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .lose: "onboarding.goal.lose.title"
            case .maintain: "onboarding.goal.maintain.title"
            case .gain: "onboarding.goal.gain.title"
            }
        }

        var multiplier: Double {
            switch self {
            case .lose: 0.85
            case .maintain: 1
            case .gain: 1.15
            }
        }
    }

    private var recommendedCalories: Int {
        let base = 10 * Double(weight) + 6.25 * Double(height) - 5 * Double(age) - 78
        return max(1200, min(5200, Int((base * activity.multiplier * goal.multiplier).rounded())))
    }

    /// Slide direction of the step transition: +1 forward, -1 back.
    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: stepDirection >= 0 ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: stepDirection >= 0 ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EOTheme.Palette.pageBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // A ZStack lets the outgoing and incoming pages overlap while
                    // they slide; `.id(step)` gives each step its own identity so
                    // SwiftUI actually runs the transition.
                    ZStack {
                        pageContent
                            .id(step)
                            .transition(stepTransition)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    if step != .finishing {
                        footer
                            .transition(.opacity)
                    }
                }
            }
            .toolbar {
                if step != .welcome && step != .finishing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            moveBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .tint(.primary)
                        .accessibilityLabel(Text("onboarding.action.back"))
                    }
                }
            }
            .tint(.primary)
        }
        .task(id: step) {
            guard step == .finishing, !isSaving else { return }
            isSaving = true
            await saveProfile()
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch step {
        case .welcome:
            welcomePage
        case .parameters:
            parametersPage
        case .goal:
            goalPage
        case .finishing:
            finishingPage
        }
    }

    // MARK: - Step 1 · Welcome

    private var welcomePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                Text("onboarding.new.welcome")
                    .font(EOTheme.Typography.screenTitle)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 32)

                feature("bolt.square", color: .yellow, key: "onboarding.new.feature.native")
                feature("leaf", color: .green, key: "onboarding.new.feature.focus")
                feature("barcode.viewfinder", color: .indigo, key: "onboarding.new.feature.barcode")
                feature("square.and.arrow.up", color: .purple, key: "onboarding.new.feature.share")
                feature("heart.text.square", color: .red, key: "onboarding.new.feature.health")
                legalFeature
            }
            .padding(.horizontal, 26)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
    }

    private func feature(_ systemImage: String, color: Color, key: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(color)
                .frame(width: 38, alignment: .center)

            Text(key)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Last row of the welcome list – same layout, but the copy carries the
    /// tappable "Terms of Use" link.
    private var legalFeature: some View {
        let markdown = LegalContent.markdown(for: .auth)
        let attributed = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)

        return HStack(alignment: .top, spacing: 18) {
            Image(systemName: "doc.text")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.mint)
                .frame(width: 38, alignment: .center)

            Text(attributed)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Step 2 · Parameters

    private var parametersPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                Text("onboarding.new.parameters")
                    .font(EOTheme.Typography.screenTitle)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                EOCard {
                    EOToggleRow("onboarding.field.health_access", isOn: healthAccessBinding)
                    EORowSeparator()

                    EOStepperRow(
                        title: Text("onboarding.field.age"),
                        subtitle: Text(verbatim: "\(age)"),
                        canDecrement: age > 13,
                        canIncrement: age < 100,
                        onDecrement: { age = max(13, age - 1) },
                        onIncrement: { age = min(100, age + 1) }
                    )
                    EORowSeparator()

                    menuRow(title: Text("onboarding.field.sex"), selection: $sex) { $0.title }
                    EORowSeparator()

                    EOStepperRow(
                        title: Text("onboarding.field.weight"),
                        subtitle: Text(verbatim: "\(weight) kg"),
                        canDecrement: weight > 35,
                        canIncrement: weight < 220,
                        onDecrement: { weight = max(35, weight - 1) },
                        onIncrement: { weight = min(220, weight + 1) }
                    )
                    EORowSeparator()

                    Group {
                        EOStepperRow(
                            title: Text("onboarding.field.height"),
                            subtitle: Text(verbatim: "\(height) cm"),
                            canDecrement: height > 140,
                            canIncrement: height < 220,
                            onDecrement: { height = max(140, height - 1) },
                            onIncrement: { height = min(220, height + 1) }
                        )
                        EORowSeparator()

                        menuRow(title: Text("onboarding.field.activity"), selection: $activity) { $0.title }
                    }
                }

                Text("onboarding.new.parameters.help")
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
            }
            .padding(.horizontal, EOTheme.Metrics.screenInset)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
    }

    private var healthAccessBinding: Binding<Bool> {
        Binding(
            get: { isHealthAccessEnabled },
            set: { newValue in
                isHealthAccessEnabled = newValue
                Task { await applyHealthAccess(newValue) }
            }
        )
    }

    /// Enabling the switch asks for permission and, when granted, pre-fills the
    /// fields below from the Health app.
    ///
    /// Read-only on purpose: onboarding just needs sex, height, weight and
    /// activity. Writing meals back to Health is a separate switch in Settings,
    /// so the system sheet here doesn't list nutrients the user hasn't logged yet.
    private func applyHealthAccess(_ enabled: Bool) async {
        guard enabled else {
            isHealthAccessEnabled = false
            return
        }

        let granted = await HealthKitService.shared.requestReadAuthorization()
        isHealthAccessEnabled = granted
        guard granted else { return }

        let profile = await HealthKitService.shared.readProfile()
        guard !profile.isEmpty else { return }

        withAnimation(.snappy(duration: 0.25)) {
            if let value = profile.ageYears { age = min(max(value, 13), 100) }
            if let value = profile.heightCentimeters { height = min(max(value, 140), 220) }
            if let value = profile.weightKilograms { weight = min(max(value, 35), 220) }
            if let value = profile.biologicalSex {
                switch value {
                case .female: sex = .female
                case .male: sex = .male
                case .other, .notSet: sex = .notSpecified
                }
            }
        }
    }

    /// Row whose trailing accessory is an inline menu with the
    /// `chevron.up.chevron.down` affordance from the mock-ups.
    private func menuRow<Value>(
        title: Text,
        selection: Binding<Value>,
        titleFor: @escaping (Value) -> LocalizedStringKey
    ) -> some View where Value: CaseIterable & Hashable & Identifiable, Value.AllCases: RandomAccessCollection, Value.AllCases.Element == Value {
        EOListRow(title: title) {
            Menu {
                Picker("", selection: selection) {
                    ForEach(Value.allCases) { option in
                        Text(titleFor(option)).tag(option)
                    }
                }
                .labelsHidden()
            } label: {
                HStack(spacing: 6) {
                    Text(titleFor(selection.wrappedValue))
                        .font(EOTheme.Typography.rowValue)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EOTheme.Palette.accent)
                }
            }
            .fixedSize()
        }
    }

    // MARK: - Step 3 · Goal

    private var goalPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                Text("onboarding.new.goal")
                    .font(EOTheme.Typography.screenTitle)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                EOCard {
                    menuRow(title: Text("onboarding.new.choose_goal"), selection: $goal) { $0.title }
                        .padding(.vertical, 8)
                }

                Text("onboarding.new.goal.help")
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
            }
            .padding(.horizontal, EOTheme.Metrics.screenInset)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 4 · Finishing

    /// One line, centred, and nothing else.
    ///
    /// This page used to fire six icons out of the app icon on a staggered
    /// spring. The burst took longer than the work it was covering, so it read
    /// as a wait the app had invented rather than as progress — and it played
    /// again in full even when the profile had already been saved. A sentence
    /// held just long enough to read says the same thing and gets out of the
    /// way.
    private var finishingPage: some View {
        Text("onboarding.new.finishing")
            .font(EOTheme.Typography.screenTitle)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, EOTheme.Metrics.screenInset)
    }

    // MARK: - Footer

    private var footer: some View {
        EOPrimaryButton(
            step == .goal ? "onboarding.action.finish" : "onboarding.action.continue"
        ) {
            moveForward()
        }
        .padding(.bottom, 28)
    }

    private func moveForward() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        stepDirection = 1
        withAnimation(.snappy(duration: 0.32)) {
            step = next
        }
    }

    private func moveBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        stepDirection = -1
        withAnimation(.snappy(duration: 0.32)) {
            step = previous
        }
    }

    private func saveProfile() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))

        appSettings.setWaterTrackingEnabled(true)
        diaryService.setDailyGoal(
            DailyNutritionGoal(
                calories: recommendedCalories,
                proteinPercent: 20,
                fatPercent: 35,
                carbsPercent: 45
            )
        )
        await diaryService.updateEatometerProfile(
            heightCentimeters: height,
            weightKilograms: weight,
            ageYears: age,
            biologicalSex: sex.serviceValue,
            activityLevel: activity.rawValue,
            goal: goal.rawValue
        )
        // Held to the deadline rather than delayed by a fixed amount: the save
        // above is a network call, so a flat sleep makes a slow save slower and
        // still flashes the page past unread when the save is quick. Waiting
        // until a moment measured from the page appearing gives the same second
        // on screen either way, and costs nothing when the save already took
        // longer than that.
        try? await Task.sleep(until: deadline, clock: .continuous)
        await diaryService.markCalorieOnboardingSeen()
    }
}
