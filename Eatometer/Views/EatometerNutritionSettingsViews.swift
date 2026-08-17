import SwiftUI

struct EatometerEmailEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: FoodAuthService

    @State private var email: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmationSent = false

    private let initialEmail: String

    init(email: String) {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        initialEmail = value
        _email = State(initialValue: value)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSave: Bool {
        normalizedEmail.contains("@") && normalizedEmail != initialEmail.lowercased() && !isSaving
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.headerSpacing) {
                EOCard {
                    EOTextFieldRow("profile.email.placeholder", text: $email, showsClearButton: false)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)

                    EORowSeparator()
                    EOInlineActionRow("common.save", isEnabled: canSave, action: save)
                }

                Text("profile.email.help")
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
                    .padding(.top, 4)

                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(EOTheme.Typography.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, EOTheme.Metrics.cardInset)
                }
            }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .eoPageBackground()
        .navigationTitle("profile.email.label")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isSaving { ProgressView().controlSize(.large) } }
        .alert("profile.email.label", isPresented: $confirmationSent) {
            Button("common.ok") { dismiss() }
        } message: {
            Text("profile.email_confirmation.sent")
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        Task {
            let success = await authService.initiateChangeEmail(newEmail: normalizedEmail)
            isSaving = false
            if success {
                confirmationSent = true
            } else {
                errorMessage = NSLocalizedString("profile.email.send_failed", comment: "Email change failed")
            }
        }
    }
}

struct EatometerMealPlanSettingsView: View {
    @EnvironmentObject private var diaryService: FoodDiaryService
    @State private var goal = DailyNutritionGoal.default

    private var macroTotal: Int {
        goal.proteinPercent + goal.carbsPercent + goal.fatPercent
    }

    /// What to do next, rather than what the rule is.
    ///
    /// The line under the card used to say "must add up to 100%" whether the
    /// total was 94 or 137 — true both times, useful neither time, and it left
    /// the arithmetic to the reader while the app already knew the answer.
    /// Now it names the number that is missing, or the one that is over.
    private var macroHint: String {
        let remaining = 100 - macroTotal
        if remaining > 0 {
            return String(
                format: NSLocalizedString("mealplan.remaining", comment: "How much of the split is unassigned"),
                remaining
            )
        }
        if remaining < 0 {
            return String(
                format: NSLocalizedString("mealplan.over", comment: "How far over 100 the split is"),
                -remaining
            )
        }
        return NSLocalizedString("mealplan.help", comment: "Meal plan help")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.headerSpacing) {
                EOCard {
                    // Typed as well as stepped: a plan is a figure someone
                    // arrived at, not something to be nudged to in fifties.
                    EOStepperFieldRow(
                        title: Text(verbatim: EOStepperFieldRow.title(
                            NSLocalizedString("mealplan.calories", comment: "Calories"),
                            unit: NSLocalizedString("diary.kcal", comment: "Calories unit")
                        )),
                        value: $goal.calories,
                        range: 500...10_000,
                        step: 50
                    )
                    EORowSeparator()

                    macroRow("diary.protein", percent: $goal.proteinPercent, grams: goal.calories * goal.proteinPercent / 400)
                    EORowSeparator()

                    macroRow("diary.carbs", percent: $goal.carbsPercent, grams: goal.calories * goal.carbsPercent / 400)
                    EORowSeparator()

                    macroRow("diary.fat", percent: $goal.fatPercent, grams: goal.calories * goal.fatPercent / 900)

                    EORowSeparator()

                    EOInlineActionRow(
                        "common.save",
                        isEnabled: macroTotal == 100 && goal != diaryService.dailyGoal
                    ) {
                        // The keypad has no return key and this row is not the
                        // keyboard, so a figure still being typed has not been
                        // settled against the allowed range yet. Putting the
                        // keyboard away is what settles it.
                        PlatformSupport.dismissActiveInput()
                        diaryService.setDailyGoal(goal)
                    }
                }

                Text(verbatim: macroHint)
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(macroTotal == 100 ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
                    .padding(.top, 4)
            }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        // The number pad has no return key and the rows no longer put a Done
        // button above it, so dragging the page is what puts it away.
        .dismissesKeyboardInteractively()
        .eoPageBackground()
        .navigationTitle("profile.nutrition.meal_plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { goal = diaryService.dailyGoal }
    }

    /// Mock-up row: "Protein, %" with the gram value underneath, then the share
    /// and a stepper.
    ///
    /// The share used to be part of the title, which made it read-only. Three
    /// shares have to add up to exactly 100, and getting there in fives is a
    /// puzzle when the answer — 30, 25, 45 — is already known.
    private func macroRow(_ titleKey: String, percent: Binding<Int>, grams: Int) -> some View {
        EOStepperFieldRow(
            title: Text(verbatim: EOStepperFieldRow.title(
                NSLocalizedString(titleKey, comment: "Macro"),
                unit: "%"
            )),
            subtitle: Text(verbatim: String(format: NSLocalizedString("mealplan.grams", comment: "Macro grams"), grams)),
            value: percent,
            range: 0...100,
            step: 5
        )
    }
}

private struct MealSettingsEditorTarget: Identifiable {
    let id = UUID()
    let category: MealCategory
    let isNew: Bool
}

struct EatometerMealsSettingsView: View {
    @EnvironmentObject private var diaryService: FoodDiaryService
    @State private var categories: [MealCategory] = []
    @State private var editorTarget: MealSettingsEditorTarget?
    /// The list as the service last had it, to tell a real change from a redraw.
    @State private var loadedCategories: [MealCategory] = []

    /// The meals in the order they happen.
    ///
    /// Sorted by time rather than by a position anybody has to maintain. A meal
    /// plan is a day, and a day already has an order — one that the reader
    /// states when they set the time. Letting them arrange the rows as well
    /// meant two orders that could disagree, and nothing in the app could say
    /// which of the two was meant when they did.
    ///
    /// The name breaks a tie, so two meals set to the same minute do not swap
    /// places between one read and the next.
    private var enabledCategories: [MealCategory] {
        categories.filter(\.isEnabled).sorted(by: Self.chronologically)
    }

    /// `nonisolated` because it is passed to `sorted(by:)`, which calls it from
    /// a plain synchronous context. It is a comparison of two values and reads
    /// nothing from the view, so there is no state for the main actor to be
    /// protecting here.
    private nonisolated static func chronologically(_ lhs: MealCategory, _ rhs: MealCategory) -> Bool {
        let left = lhs.preferredHour * 60 + lhs.preferredMinute
        let right = rhs.preferredHour * 60 + rhs.preferredMinute
        if left != right { return left < right }
        return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.headerSpacing) {
                EOCard {
                    EOCardHeaderRow("meals.settings.add", systemImage: "plus") {
                        presentNewMeal()
                    }
                    .disabled(enabledCategories.count >= 5)
                    .opacity(enabledCategories.count >= 5 ? 0.5 : 1)

                    ForEach(enabledCategories) { category in
                        EORowSeparator()

                        Button {
                            editorTarget = MealSettingsEditorTarget(category: category, isNew: false)
                        } label: {
                            EOListRow(
                                title: Text(verbatim: category.displayTitle),
                                subtitle: Text(verbatim: rowSubtitle(for: category)),
                                accessory: .valueChevron(Text("common.edit"))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(verbatim: shareHint)
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(shareTotal == 100 ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
                    .padding(.top, 4)

                Text("meals.settings.help")
                    .font(EOTheme.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
                    .padding(.top, 4)
            }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .eoPageBackground()
        .navigationTitle("profile.nutrition.meals")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            categories = diaryService.visibleMealCategories
            loadedCategories = categories
            // Meals saved before the order followed the clock still carry
            // whatever positions they were dragged into. Renumbering on the
            // way in puts them right once, rather than showing one order here
            // and another everywhere the stored `sortOrder` is read.
            normalizeAndPersist()
        }
        .sheet(item: $editorTarget) { target in
            EatometerMealSettingsEditorView(
                category: target.category,
                isNew: target.isNew,
                onSave: save,
                onDelete: delete
            )
            // Sheets do not inherit the environment of the view that
            // presented them; without this the editor's calorie preview has no
            // goal to work from.
            .environmentObject(diaryService)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func presentNewMeal() {
        let index = enabledCategories.count
        let category = MealCategory(
            id: UUID().uuidString,
            title: "",
            symbolName: "fork.knife",
            sortOrder: index,
            isEnabled: true,
            preferredHour: 12,
            goalSharePercent: 0
        )
        editorTarget = MealSettingsEditorTarget(category: category, isNew: true)
    }

    private func save(_ category: MealCategory) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
        normalizeAndPersist()
    }

    // MARK: - Shares

    private var shareTotal: Int {
        enabledCategories.reduce(0) { $0 + max($1.goalSharePercent, 0) }
    }

    /// The same wording as the meal plan, for the same reason: the reader
    /// should be told the number that is missing, not the rule they already
    /// know.
    private var shareHint: String {
        let remaining = 100 - shareTotal
        if remaining > 0 {
            return String(
                format: NSLocalizedString("mealplan.remaining", comment: "How much is unassigned"),
                remaining
            )
        }
        if remaining < 0 {
            return String(
                format: NSLocalizedString("mealplan.over", comment: "How far over 100"),
                -remaining
            )
        }
        return NSLocalizedString("meals.settings.share.help", comment: "Meal shares help")
    }

    /// Time and share on one line, which is all a row needs to say.
    ///
    /// The share was briefly a stepper of its own under every meal. Four meals
    /// meant four extra rows on a screen that is a list of four things, and the
    /// card stopped reading as a list. It belongs in the editor, next to the
    /// name and the time it is set with; here it is only reported.
    private func rowSubtitle(for category: MealCategory) -> String {
        let time = formattedTime(category)
        guard category.goalSharePercent > 0 else { return time }
        let share = String(
            format: NSLocalizedString("meals.settings.share.value", comment: "Meal share"),
            category.goalSharePercent
        )
        return "\(time) · \(share)"
    }

    private func delete(_ category: MealCategory) {
        categories.removeAll { $0.id == category.id }
        normalizeAndPersist()
    }

    /// Renumbers the meals by the clock and saves them.
    ///
    /// `sortOrder` is still what the rest of the app and the backend read, so
    /// it is not removed — it is derived. Changing a meal's time to seven in
    /// the morning is what moves it to the top; there is no second place to say
    /// so and no way for the two to fall out of step.
    private func normalizeAndPersist() {
        let enabled = categories.filter(\.isEnabled).sorted(by: Self.chronologically)
        let positions = Dictionary(
            uniqueKeysWithValues: enabled.enumerated().map { ($0.element.id, $0.offset) }
        )

        var result = categories.map { category -> MealCategory in
            var updated = category
            // Disabled meals are parked after every enabled one rather than
            // left on whatever number they last held, which would otherwise
            // collide with a position now in use.
            updated.sortOrder = positions[category.id] ?? (enabled.count + updated.sortOrder)
            return updated
        }
        result.sort { $0.sortOrder < $1.sortOrder }
        categories = result

        // Only written when it actually differs. This also runs on every
        // appearance, to renumber meals saved before the order followed the
        // clock, and saving an unchanged list each time would be a write —
        // and a sync — for nothing.
        guard result != loadedCategories else { return }
        loadedCategories = result
        diaryService.setMealCategories(result)
    }

    private func formattedTime(_ category: MealCategory) -> String {
        String(format: "%02d:%02d", category.preferredHour, category.preferredMinute)
    }
}

private struct EatometerMealSettingsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var diaryService: FoodDiaryService

    @State private var title: String
    @State private var time: Date
    @State private var sharePercent: Int
    /// Whether the reader has chosen to write the name themselves.
    @State private var usesCustomTitle: Bool

    let category: MealCategory
    let isNew: Bool
    let onSave: (MealCategory) -> Void
    let onDelete: (MealCategory) -> Void

    init(category: MealCategory, isNew: Bool, onSave: @escaping (MealCategory) -> Void, onDelete: @escaping (MealCategory) -> Void) {
        self.category = category
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: category.title)
        // An existing meal whose name is not one of the presets was named by
        // hand, so the field opens showing it rather than hiding it behind a
        // menu that would not have it.
        let trimmed = category.title.trimmingCharacters(in: .whitespacesAndNewlines)
        _usesCustomTitle = State(initialValue: !trimmed.isEmpty && !Self.presetTitles.contains(trimmed))
        var components = DateComponents()
        components.hour = category.preferredHour
        components.minute = category.preferredMinute
        _time = State(initialValue: Calendar.current.date(from: components) ?? .now)
        _sharePercent = State(initialValue: category.goalSharePercent)
    }

    private var normalizedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What the share works out to in calories, so the percentage means
    /// something without the reader doing the multiplication.
    private var shareCaloriesText: String {
        let calories = Int((Double(diaryService.dailyGoal.calories) * Double(sharePercent) / 100).rounded())
        return String(
            format: NSLocalizedString("meals.settings.share.calories", comment: "Share in calories"),
            calories
        )
    }

    /// The names offered before anyone has to type one.
    ///
    /// Typing was the only way to name a meal, which had two consequences.
    /// "Обед" and "обед " became two different meals that the diary then had to
    /// tell apart on every read; and every free-text name is one more string
    /// the app can never match to a known meal type, so slots multiplied until
    /// the lists that iterate them began to labour.
    ///
    /// Localised titles rather than raw keys, because these end up stored on
    /// the category and shown as-is.
    private static var presetTitles: [String] {
        ["meal.breakfast", "meal.lunch", "meal.dinner", "meal.snack", "meal.drink", "meal.outside"]
            .map { NSLocalizedString($0, comment: "Meal slot preset") }
    }

    @ViewBuilder
    private var presetRow: some View {
        Menu {
            ForEach(Self.presetTitles, id: \.self) { preset in
                Button {
                    usesCustomTitle = false
                    title = preset
                } label: {
                    if title == preset, !usesCustomTitle {
                        Label(preset, systemImage: "checkmark")
                    } else {
                        Text(verbatim: preset)
                    }
                }
            }

            Divider()

            // Kept, because six names cannot cover every way of eating. It is
            // the exception now rather than the only road.
            Button {
                usesCustomTitle = true
            } label: {
                if usesCustomTitle {
                    Label("meals.settings.preset.custom", systemImage: "checkmark")
                } else {
                    Text("meals.settings.preset.custom")
                }
            }
        } label: {
            EOListRow(
                title: Text("meals.settings.preset"),
                accessory: .valueChevron(
                    Text(verbatim: usesCustomTitle
                        ? NSLocalizedString("meals.settings.preset.custom", comment: "Custom name")
                        : (normalizedTitle.isEmpty ? "—" : normalizedTitle))
                )
            )
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                EOCard {
                    presetRow
                    if usesCustomTitle {
                        EORowSeparator()
                        EOTextFieldRow("meals.settings.title", text: $title)
                    }
                    EORowSeparator()

                    EOListRow(title: Text("meals.settings.time")) {
                        DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    EORowSeparator()

                    // Set here, alongside the name and the time, because this
                    // is the sheet where a meal is described. In the list it
                    // was a fourth control under every row and turned a list of
                    // four meals into sixteen lines.
                    EOStepperFieldRow(
                        title: Text(verbatim: EOStepperFieldRow.title(
                            NSLocalizedString("meals.settings.share", comment: "Meal share of the daily goal"),
                            unit: "%"
                        )),
                        subtitle: Text(verbatim: shareCaloriesText),
                        value: $sharePercent,
                        range: 0...100,
                        step: 5
                    )
                }

                if !isNew {
                    EOCard {
                        EOInlineActionRow("common.delete", tint: EOTheme.Palette.destructive) {
                            onDelete(category)
                            dismiss()
                        }
                    }
                }
            }
            .eoCardInsets()
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .eoPageBackground()
            .eoSheetChrome(
                isNew ? "meals.settings.add" : "meals.settings.edit",
                trailing: .confirm(isEnabled: !normalizedTitle.isEmpty, action: save),
                onClose: { dismiss() }
            )
        }
    }

    private func save() {
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
        var updated = category
        updated.title = normalizedTitle
        updated.preferredHour = timeComponents.hour ?? 12
        updated.preferredMinute = timeComponents.minute ?? 0
        updated.goalSharePercent = min(max(sharePercent, 0), 100)
        updated.symbolName = symbol(for: updated.preferredHour)
        updated.isEnabled = true
        onSave(updated)
        dismiss()
    }

    private func symbol(for hour: Int) -> String {
        switch hour {
        case 5..<11: return "sunrise.fill"
        case 11..<17: return "sun.max.fill"
        case 17..<24: return "moon.stars.fill"
        default: return "fork.knife"
        }
    }
}
