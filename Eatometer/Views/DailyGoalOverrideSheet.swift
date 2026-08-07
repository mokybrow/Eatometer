import SwiftUI

private enum DayGoalEditorField: Hashable {
    case calories
    case protein
    case fat
    case carbs
}

struct DailyGoalOverrideSheet: View {
    @Environment(\.dismiss) private var dismiss

    let day: Date
    let baseGoal: DailyNutritionGoal
    let effectiveGoal: DailyNutritionGoal
    let hasOverride: Bool
    let onSave: (DailyNutritionGoal) -> Void
    let onClearOverride: () -> Void

    @State private var draft: DailyNutritionGoal
    @State private var calorieInput: String
    @State private var proteinInput: String
    @State private var fatInput: String
    @State private var carbsInput: String
    @FocusState private var focusedField: DayGoalEditorField?

    init(
        day: Date,
        baseGoal: DailyNutritionGoal,
        effectiveGoal: DailyNutritionGoal,
        hasOverride: Bool,
        onSave: @escaping (DailyNutritionGoal) -> Void,
        onClearOverride: @escaping () -> Void
    ) {
        self.day = day
        self.baseGoal = baseGoal
        self.effectiveGoal = effectiveGoal
        self.hasOverride = hasOverride
        self.onSave = onSave
        self.onClearOverride = onClearOverride
        self._draft = State(initialValue: effectiveGoal)
        self._calorieInput = State(initialValue: String(effectiveGoal.calories))
        self._proteinInput = State(initialValue: String(effectiveGoal.proteinPercent))
        self._fatInput = State(initialValue: String(effectiveGoal.fatPercent))
        self._carbsInput = State(initialValue: String(effectiveGoal.carbsPercent))
    }

    private var selectedGoal: DailyNutritionGoal {
        draft.sanitized
    }

    private var hasUnsavedChanges: Bool {
        selectedGoal != effectiveGoal.sanitized
    }

    private var macroTotal: Int {
        draft.proteinPercent + draft.fatPercent + draft.carbsPercent
    }

    private var macroWarning: String? {
        if macroTotal < 100 {
            return String(format: NSLocalizedString("nutrition.goal.macros_remaining", comment: "Missing macro percentage warning"), 100 - macroTotal)
        }
        return nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                heroCard
                caloriesEditorCard
                macrosEditorCard
                macroSummaryCard

                if hasOverride {
                    Button(role: .destructive) {
                        clearOverride()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                            Text("today.goal.reset_button")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color.appPageBackground.ignoresSafeArea())
        .navigationTitle(Text("today.goal.custom_title"))
        .navigationBarTitleDisplayMode(.inline)
        .dismissesKeyboardInteractively()
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onChanged { _ in
                dismissKeyboard()
            }
        )
        .onChange(of: focusedField) { _, field in
            syncGoalInputFields(excluding: field)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: saveChanges) {
                    Label("common.save", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                .tint(.accentColor)
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(!hasUnsavedChanges)
                .opacity(hasUnsavedChanges ? 1 : 0.45)
            }
        }
    }

    private var heroCard: some View {
        DayGoalCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            Calendar.current.isDateInToday(day)
                                ? NSLocalizedString("today.calendar.today_button", comment: "Today button title")
                                : day.formatted(.dateTime.day().month(.wide).year())
                        )
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: "\(max(draft.calories, 0))")
                                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.primary)

                            Text(NSLocalizedString("diary.kcal", comment: "Calories suffix"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    ZStack {
                        Circle()
                            .fill((hasOverride ? Color.blue : Color.orange).opacity(0.14))
                            .frame(width: 58, height: 58)

                        Image(systemName: hasOverride ? "calendar.badge.checkmark" : "flame.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(hasOverride ? .blue : .orange)
                    }
                }

                HStack(spacing: 10) {
                    macroSummaryPill(titleKey: "diary.protein", valueText: "\(draft.proteinPercent)%", tint: .green)
                    macroSummaryPill(titleKey: "diary.fat", valueText: "\(draft.fatPercent)%", tint: WeeklyMacroBarColors.fat)
                    macroSummaryPill(titleKey: "diary.carbs", valueText: "\(draft.carbsPercent)%", tint: .blue)
                }
            }
        }
    }

    private var caloriesEditorCard: some View {
        DayGoalCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("today.goal.calories_section")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 16) {
                    goalAdjustButton(
                        systemImage: "minus",
                        labelKey: "recipe.editor.decrease",
                        disabled: draft.calories <= 100,
                        action: { adjustCalories(by: -50) }
                    )

                    HStack(spacing: 10) {
                        TextField(text: $calorieInput, prompt: Text("common.zero_placeholder").foregroundStyle(.secondary)) {
                            Text("today.goal.calories_section")
                        }
                        .focused($focusedField, equals: .calories)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .frame(maxWidth: .infinity)
                        .onChange(of: calorieInput) { _, newValue in
                            guard focusedField == .calories else { return }
                            handleCaloriesInputChange(newValue)
                        }

                        Text(NSLocalizedString("diary.kcal", comment: "Calories suffix"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )

                    goalAdjustButton(
                        systemImage: "plus",
                        labelKey: "recipe.editor.increase",
                        disabled: draft.calories >= 10000,
                        action: { adjustCalories(by: 50) }
                    )
                }

            }
        }
    }

    private var macrosEditorCard: some View {
        DayGoalCard {
            VStack(alignment: .leading, spacing: 18) {
                macroEditorRow(
                    titleKey: "diary.protein",
                    input: $proteinInput,
                    grams: Int((Double(draft.proteinPercent) * Double(max(draft.calories, 0)) / 100.0) / 4.0),
                    focusedField: .protein,
                    tint: .green,
                    decreaseDisabled: draft.proteinPercent <= 0,
                    increaseDisabled: draft.proteinPercent >= 100,
                    onTextChange: {
                        handleMacroInputChange($0, field: .protein, component: \.proteinPercent) {
                            proteinInput = $0
                        }
                    },
                    onDecrease: { adjustMacroPercent(by: -5, component: \.proteinPercent) },
                    onIncrease: { adjustMacroPercent(by: 5, component: \.proteinPercent) }
                )

                Divider()

                macroEditorRow(
                    titleKey: "diary.fat",
                    input: $fatInput,
                    grams: Int((Double(draft.fatPercent) * Double(max(draft.calories, 0)) / 100.0) / 9.0),
                    focusedField: .fat,
                    tint: .orange,
                    decreaseDisabled: draft.fatPercent <= 0,
                    increaseDisabled: draft.fatPercent >= 100,
                    onTextChange: {
                        handleMacroInputChange($0, field: .fat, component: \.fatPercent) {
                            fatInput = $0
                        }
                    },
                    onDecrease: { adjustMacroPercent(by: -5, component: \.fatPercent) },
                    onIncrease: { adjustMacroPercent(by: 5, component: \.fatPercent) }
                )

                Divider()

                macroEditorRow(
                    titleKey: "diary.carbs",
                    input: $carbsInput,
                    grams: Int((Double(draft.carbsPercent) * Double(max(draft.calories, 0)) / 100.0) / 4.0),
                    focusedField: .carbs,
                    tint: .blue,
                    decreaseDisabled: draft.carbsPercent <= 0,
                    increaseDisabled: draft.carbsPercent >= 100,
                    onTextChange: {
                        handleMacroInputChange($0, field: .carbs, component: \.carbsPercent) {
                            carbsInput = $0
                        }
                    },
                    onDecrease: { adjustMacroPercent(by: -5, component: \.carbsPercent) },
                    onIncrease: { adjustMacroPercent(by: 5, component: \.carbsPercent) }
                )
            }
        }
    }

    private var macroSummaryCard: some View {
        DayGoalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("onboarding.macro.total")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Text("\(macroTotal)%")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(macroTotal == 100 ? Color.primary : Color.orange)
                }

                if let macroWarning {
                    Label(macroWarning, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 10) {
                    statPill(title: NSLocalizedString("today.goal.base_title", comment: "Base goal title"), value: "\(baseGoal.calories) \(NSLocalizedString("diary.kcal", comment: "Calories suffix"))", tint: .secondary)
                    statPill(title: NSLocalizedString("diary.goal", comment: "Goal"), value: "\(selectedGoal.calories) \(NSLocalizedString("diary.kcal", comment: "Calories suffix"))", tint: .blue)
                }
            }
        }
    }

    private func macroEditorRow(
        titleKey: LocalizedStringKey,
        input: Binding<String>,
        grams: Int,
        focusedField: DayGoalEditorField,
        tint: Color,
        decreaseDisabled: Bool,
        increaseDisabled: Bool,
        onTextChange: @escaping (String) -> Void,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titleKey)
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                goalAdjustButton(
                    systemImage: "minus",
                    labelKey: "recipe.editor.decrease",
                    disabled: decreaseDisabled,
                    action: onDecrease
                )

                VStack(alignment: .center, spacing: 4) {
                    ZStack {
                        TextField(text: input, prompt: Text("common.zero_placeholder").foregroundStyle(.secondary)) {
                            Text(titleKey)
                        }
                        .focused($focusedField, equals: focusedField)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .frame(width: 64)
                        .onChange(of: input.wrappedValue) { _, newValue in
                            guard self.focusedField == focusedField else { return }
                            onTextChange(newValue)
                        }

                        HStack {
                            Spacer()

                            Text("%")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Text(String(format: NSLocalizedString("recipe.grams_value", comment: "Grams value"), grams))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint.opacity(0.8))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                        .fill(tint.opacity(0.08))
                )

                goalAdjustButton(
                    systemImage: "plus",
                    labelKey: "recipe.editor.increase",
                    disabled: increaseDisabled,
                    action: onIncrease
                )
            }
        }
    }

    private func goalAdjustButton(
        systemImage: String,
        labelKey: LocalizedStringKey,
        disabled: Bool,
        size: CGFloat = 52,
        action: @escaping () -> Void
    ) -> some View {
        PressableIconButton(disabled: disabled, action: action) {
            Label(labelKey, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: size <= 40 ? 15 : 18, weight: .semibold))
                .frame(width: size, height: size)
                .opacity(disabled ? 0.45 : 1)
        }
    }

    private func macroSummaryPill(titleKey: LocalizedStringKey, valueText: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(valueText)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }

    private func statPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func syncGoalInputFields(excluding excludedField: DayGoalEditorField? = nil) {
        normalizeGoalDraftIfNeeded()

        if excludedField != .calories {
            calorieInput = String(draft.calories)
        }

        if excludedField != .protein {
            proteinInput = String(draft.proteinPercent)
        }

        if excludedField != .fat {
            fatInput = String(draft.fatPercent)
        }

        if excludedField != .carbs {
            carbsInput = String(draft.carbsPercent)
        }
    }

    private func normalizeGoalDraftIfNeeded() {
        if draft.calories < 100 {
            draft.calories = 100
        }

        draft.proteinPercent = min(max(draft.proteinPercent, 0), 100)
        draft.fatPercent = min(max(draft.fatPercent, 0), 100)
        draft.carbsPercent = min(max(draft.carbsPercent, 0), 100)
    }

    private func handleCaloriesInputChange(_ newValue: String) {
        let digits = newValue.filter(\.isNumber)
        if digits != newValue {
            calorieInput = digits
        }

        guard !digits.isEmpty else {
            draft.calories = 0
            return
        }

        let clampedValue = min(Int(digits) ?? draft.calories, 10000)
        draft.calories = clampedValue

        let normalizedValue = String(clampedValue)
        if digits != normalizedValue && clampedValue == 10000 {
            calorieInput = normalizedValue
        }
    }

    private func handleMacroInputChange(
        _ newValue: String,
        field: DayGoalEditorField,
        component: WritableKeyPath<DailyNutritionGoal, Int>,
        updateText: (String) -> Void
    ) {
        let digits = newValue.filter(\.isNumber)
        if digits != newValue {
            updateText(digits)
        }

        guard !digits.isEmpty else {
            setMacroPercent(0, component: component)
            syncGoalInputFields(excluding: field)
            return
        }

        let clampedValue = min(Int(digits) ?? 0, 100)
        setMacroPercent(clampedValue, component: component)

        let normalizedValue = String(clampedValue)
        if digits != normalizedValue && clampedValue == 100 {
            updateText(normalizedValue)
        }

        syncGoalInputFields(excluding: field)
    }

    private func adjustCalories(by delta: Int) {
        dismissKeyboard()
        let baseCalories = max(draft.calories, 100)
        draft.calories = min(max(baseCalories + delta, 100), 10000)
        syncGoalInputFields()
    }

    private func adjustMacroPercent(by delta: Int, component: WritableKeyPath<DailyNutritionGoal, Int>) {
        dismissKeyboard()
        setMacroPercent(draft[keyPath: component] + delta, component: component)
        syncGoalInputFields()
    }

    private func saveChanges() {
        dismissKeyboard()
        onSave(selectedGoal)
        dismiss()
    }

    private func clearOverride() {
        dismissKeyboard()
        onClearOverride()
        dismiss()
    }

    private func dismissKeyboard() {
        focusedField = nil
        syncGoalInputFields()
    }

    private func setMacroPercent(_ newValue: Int, component: WritableKeyPath<DailyNutritionGoal, Int>) {
        draft[keyPath: component] = min(max(newValue, 0), 100)

        var overflow = max(0, macroTotal - 100)
        guard overflow > 0 else { return }

        let otherComponents: [WritableKeyPath<DailyNutritionGoal, Int>] = [\.proteinPercent, \.fatPercent, \.carbsPercent]
            .filter { $0 != component }

        for keyPath in otherComponents.reversed() {
            guard overflow > 0 else { break }
            let currentValue = draft[keyPath: keyPath]
            let reduction = min(currentValue, overflow)
            draft[keyPath: keyPath] -= reduction
            overflow -= reduction
        }

        if overflow > 0 {
            draft[keyPath: component] = max(0, draft[keyPath: component] - overflow)
        }

        syncGoalInputFields(excluding: focusedField)
    }
}

private struct DayGoalCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}
