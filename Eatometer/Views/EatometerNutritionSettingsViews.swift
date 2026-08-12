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

                Text(macroTotal == 100 ? "mealplan.help" : "mealplan.percent_warning")
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

    private var enabledCategories: [MealCategory] {
        categories.filter(\.isEnabled).sorted { $0.sortOrder < $1.sortOrder }
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
                                subtitle: Text(verbatim: formattedTime(category)),
                                accessory: .valueChevron(Text("common.edit"))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

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
        .onAppear { categories = diaryService.visibleMealCategories }
        .sheet(item: $editorTarget) { target in
            EatometerMealSettingsEditorView(
                category: target.category,
                isNew: target.isNew,
                onSave: save,
                onDelete: delete
            )
            .presentationDetents([.medium])
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

    private func delete(_ category: MealCategory) {
        categories.removeAll { $0.id == category.id }
        normalizeAndPersist()
    }

    private func normalizeAndPersist() {
        let enabledIDs = Set(categories.filter(\.isEnabled).map(\.id))
        var result = categories.map { category in
            var updated = category
            updated.isEnabled = enabledIDs.contains(category.id)
            if let order = enabledCategories.firstIndex(where: { $0.id == category.id }) {
                updated.sortOrder = order
            }
            return updated
        }
        result.sort { $0.sortOrder < $1.sortOrder }
        categories = result
        diaryService.setMealCategories(result)
    }

    private func formattedTime(_ category: MealCategory) -> String {
        String(format: "%02d:%02d", category.preferredHour, category.preferredMinute)
    }
}

private struct EatometerMealSettingsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var time: Date

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
        var components = DateComponents()
        components.hour = category.preferredHour
        components.minute = category.preferredMinute
        _time = State(initialValue: Calendar.current.date(from: components) ?? .now)
    }

    private var normalizedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                EOCard {
                    EOTextFieldRow("meals.settings.title", text: $title)
                    EORowSeparator()

                    EOListRow(title: Text("meals.settings.time")) {
                        DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
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
