import SwiftUI

enum NutritionPreferencesMode {
    case dietPlan
    case calorieGoal
    case mealSlots
    case widgetRings
}

private enum GoalEditorField: Hashable {
    case calories
    case protein
    case fat
    case carbs
}

private struct MealSlotPreset: Identifiable, Hashable {
    let id: String
    let symbolName: String
    let preferredHour: Int

    var title: String {
        switch id {
        case "breakfast":
            return NSLocalizedString("meal.breakfast", comment: "Breakfast meal title")
        case "lunch":
            return NSLocalizedString("meal.lunch", comment: "Lunch meal title")
        case "dinner":
            return NSLocalizedString("meal.dinner", comment: "Dinner meal title")
        case "snack":
            return NSLocalizedString("meal.snack", comment: "Snack meal title")
        case "drink":
            return NSLocalizedString("meal.drink", comment: "Drink meal title")
        case "outside":
            return NSLocalizedString("meal.outside", comment: "Outside meal title")
        default:
            return NSLocalizedString("meal.custom_default", comment: "Default custom meal title")
        }
    }

    static let all: [MealSlotPreset] = [
        MealSlotPreset(id: "breakfast", symbolName: "sunrise.fill", preferredHour: 8),
        MealSlotPreset(id: "lunch", symbolName: "sun.max.fill", preferredHour: 13),
        MealSlotPreset(id: "dinner", symbolName: "moon.stars.fill", preferredHour: 19),
        MealSlotPreset(id: "snack", symbolName: "leaf.fill", preferredHour: 16),
        MealSlotPreset(id: "drink", symbolName: "cup.and.saucer.fill", preferredHour: 11),
        MealSlotPreset(id: "outside", symbolName: "takeoutbag.and.cup.and.straw.fill", preferredHour: 18)
    ]
}

struct NutritionPreferencesSheet: View {
    @EnvironmentObject private var diaryService: FoodDiaryService
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let mode: NutritionPreferencesMode
    private let mealSlotsCoordinateSpace = "nutrition-meal-slots-reorder"

    @State private var goalDraft: DailyNutritionGoal
    @State private var categoriesDraft: [MealCategory]
    @State private var armedCategoryID: String?
    @State private var draggedCategoryID: String?
    @State private var draggedCategoryFrame: CGRect = .zero
    @State private var draggedCategoryOffset: CGSize = .zero
    @State private var mealSlotFrames: [String: CGRect] = [:]
    @State private var calorieInput: String
    @State private var proteinInput: String
    @State private var fatInput: String
    @State private var carbsInput: String
    @State private var preferredTimeDrafts: [String: Date]
    @State private var dietPlanDraft: DietPlanOption
    @State private var initialGoal: DailyNutritionGoal?
    @State private var initialCategories: [MealCategory]?
    @State private var initialDietPlan: DietPlanOption?
    @State private var widgetRingMetricsDraft: [AppSettings.NutritionWidgetRingMetric]
    @State private var initialWidgetRingMetrics: [AppSettings.NutritionWidgetRingMetric]?
    @FocusState private var focusedGoalField: GoalEditorField?

    init(mode: NutritionPreferencesMode) {
        self.mode = mode
        self._goalDraft = State(initialValue: .default)
        self._categoriesDraft = State(initialValue: MealCategory.default)
        self._calorieInput = State(initialValue: String(DailyNutritionGoal.default.calories))
        self._proteinInput = State(initialValue: String(DailyNutritionGoal.default.proteinPercent))
        self._fatInput = State(initialValue: String(DailyNutritionGoal.default.fatPercent))
        self._carbsInput = State(initialValue: String(DailyNutritionGoal.default.carbsPercent))
        self._preferredTimeDrafts = State(initialValue: [:])
        self._dietPlanDraft = State(initialValue: .balanced)
        self._widgetRingMetricsDraft = State(initialValue: AppSettings.defaultNutritionWidgetRingMetrics)
    }

    var body: some View {
        Group {
            if mode == .dietPlan {
                dietPlanContent
            } else if mode == .calorieGoal {
                calorieGoalContent
            } else if mode == .widgetRings {
                widgetRingsContent
            } else {
                mealSlotsContent
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    resetDrafts()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(action: saveChanges) {
                    Label("common.save", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .tint(.accentColor)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .clipShape(Circle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
            }
        }
        .task {
            goalDraft = diaryService.dailyGoal
            categoriesDraft = diaryService.visibleMealCategories
            dietPlanDraft = diaryService.dietPlan
            widgetRingMetricsDraft = appSettings.nutritionWidgetRingMetrics
            rebalanceGoalSharesIfNeeded()
            syncGoalInputFields()
            syncPreferredTimeDrafts()
            initialGoal = goalDraft
            initialCategories = categoriesDraft
            initialDietPlan = dietPlanDraft
            initialWidgetRingMetrics = widgetRingMetricsDraft
        }
        .onChange(of: focusedGoalField) { _, field in
            syncGoalInputFields(excluding: field)
        }
    }

    private var navigationTitle: Text {
        switch mode {
        case .dietPlan:
            return Text("profile.nutrition.diet_plan")
        case .calorieGoal:
            return Text("profile.nutrition.calorie_goal")
        case .mealSlots:
            return Text("profile.nutrition.meal_slots")
        case .widgetRings:
            return Text("settings.widget_rings.title")
        }
    }

    private var selectedGoal: DailyNutritionGoal {
        goalDraft.sanitized
    }

    private var hasChanges: Bool {
        if mode == .dietPlan {
            return initialDietPlan != nil && dietPlanDraft != initialDietPlan
        } else if mode == .calorieGoal {
            let goalChanged = initialGoal != nil && selectedGoal != initialGoal
            return goalChanged
        } else if mode == .widgetRings {
            return initialWidgetRingMetrics != nil && widgetRingMetricsDraft != initialWidgetRingMetrics
        } else {
            return initialCategories != nil && categoriesDraft != initialCategories
        }
    }

    private var widgetRingSelectionIsValid: Bool {
        widgetRingMetricsDraft.count == 3
    }

    private var canSave: Bool {
        hasChanges && (mode != .widgetRings || widgetRingSelectionIsValid)
    }

    private var dietPlanContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(DietPlanOption.allCases) { plan in
                    dietPlanOptionButton(for: plan)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color.appPageBackground.ignoresSafeArea())
    }

    private var calorieGoalContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("today.goal.calories_section")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                    caloriesEditorCard
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("diary.base_goal")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                    macrosEditorCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color.appPageBackground.ignoresSafeArea())
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
    }

    private var widgetRingsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                widgetRingsCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color.appPageBackground.ignoresSafeArea())
    }

    private var calorieGoalHeroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("diary.base_goal")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(verbatim: "\(max(goalDraft.calories, 0))")
                        .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)

                    Text(NSLocalizedString("diary.kcal", comment: "Calories suffix"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 58, height: 58)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            Text(NSLocalizedString("diary.base_goal_desc", comment: "Base goal description"))
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                macroSummaryPill(titleKey: "diary.protein", valueText: "\(goalDraft.proteinPercent)%", tint: .green)
                macroSummaryPill(titleKey: "diary.fat", valueText: "\(goalDraft.fatPercent)%", tint: WeeklyMacroBarColors.fat)
                macroSummaryPill(titleKey: "diary.carbs", valueText: "\(goalDraft.carbsPercent)%", tint: .blue)
            }

            Text(
                String(
                    format: NSLocalizedString("today.goal.macro_split", comment: "Macro split line"),
                    goalDraft.proteinPercent,
                    goalDraft.fatPercent,
                    goalDraft.carbsPercent
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private var caloriesEditorCard: some View {
        NutritionGoalCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    goalAdjustButton(
                        systemImage: "minus",
                        labelKey: "recipe.editor.decrease",
                        disabled: goalDraft.calories <= 100,
                        action: { adjustCalories(by: -50) }
                    )

                    HStack(spacing: 10) {
                        TextField(text: $calorieInput, prompt: Text("common.zero_placeholder").foregroundStyle(.secondary)) {
                            Text("today.goal.calories_section")
                        }
                        .focused($focusedGoalField, equals: .calories)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .frame(maxWidth: .infinity)
                        .onChange(of: calorieInput) { _, newValue in
                            guard focusedGoalField == .calories else { return }
                            handleCaloriesInputChange(newValue)
                        }

                        Text(NSLocalizedString("diary.kcal", comment: "Calories suffix"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )

                    goalAdjustButton(
                        systemImage: "plus",
                        labelKey: "recipe.editor.increase",
                        disabled: goalDraft.calories >= 10000,
                        action: { adjustCalories(by: 50) }
                    )
                }

                Text(NSLocalizedString("diary.base_goal_desc", comment: "Base goal description"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var macrosEditorCard: some View {
        NutritionGoalCard {
            VStack(alignment: .leading, spacing: 18) {
                macroEditorRow(
                    titleKey: "diary.protein",
                    input: $proteinInput,
                    grams: Int((Double(goalDraft.proteinPercent) * Double(max(goalDraft.calories, 0)) / 100.0) / 4.0),
                    focusedField: .protein,
                    tint: .green,
                    decreaseDisabled: goalDraft.proteinPercent <= 0,
                    increaseDisabled: goalDraft.proteinPercent >= 100,
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
                    grams: Int((Double(goalDraft.fatPercent) * Double(max(goalDraft.calories, 0)) / 100.0) / 9.0),
                    focusedField: .fat,
                    tint: .orange,
                    decreaseDisabled: goalDraft.fatPercent <= 0,
                    increaseDisabled: goalDraft.fatPercent >= 100,
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
                    grams: Int((Double(goalDraft.carbsPercent) * Double(max(goalDraft.calories, 0)) / 100.0) / 4.0),
                    focusedField: .carbs,
                    tint: .blue,
                    decreaseDisabled: goalDraft.carbsPercent <= 0,
                    increaseDisabled: goalDraft.carbsPercent >= 100,
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
        NutritionGoalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("\(macroTotal)%")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(macroTotal == 100 ? Color.primary : Color.orange)

                    Spacer(minLength: 0)

                    Text("onboarding.macro.helper")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if let macroWarning {
                    Label(macroWarning, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var widgetRingsCard: some View {
        NutritionGoalCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(widgetRingsTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(widgetRingsHelper)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(widgetRingsCounterTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text("\(widgetRingMetricsDraft.count)/3")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(widgetRingSelectionIsValid ? Color.primary : Color.orange)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(AppSettings.NutritionWidgetRingMetric.allCases) { metric in
                        widgetRingMetricButton(for: metric)
                    }
                }

                if !widgetRingSelectionIsValid {
                    Label(widgetRingsWarning, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var mealSlotsOverviewCard: some View {
        NutritionGoalCard {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("nutrition.mealslots.goal_share")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("\(goalShareTotal)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)

                    if let goalShareWarning {
                        Label(goalShareWarning, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 58, height: 58)

                    Image(systemName: "fork.knife")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private var mealSlotsContent: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    ForEach(Array(categoriesDraft.enumerated()), id: \.element.id) { _, category in
                        mealCategoryEditor(for: category, isHighlighted: isMealSlotArmed(category.id))
                            .opacity(draggedCategoryID == category.id ? 0.001 : 1)
                            .background(mealSlotFrameReader(for: category.id))
                            .contentShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                            .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 10) {
                                armMealSlotIfNeeded(category.id)
                            }
                    }

                    Button {
                        addCategory()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)

                            Text("nutrition.mealslots.add")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Spacer(minLength: 0)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
                        .opacity(canAddCategory ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAddCategory)

                    if let goalShareWarning {
                        Label(goalShareWarning, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDisabled(draggedCategoryID != nil)

            if let draggedCategory = draggedCategory {
                mealSlotDragPreview(for: draggedCategory, frame: draggedCategoryFrame)
                    .offset(
                        x: draggedCategoryFrame.minX + draggedCategoryOffset.width,
                        y: draggedCategoryFrame.minY + draggedCategoryOffset.height
                    )
                    .zIndex(10)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: mealSlotsCoordinateSpace)
        .onPreferenceChange(MealSlotFramePreferenceKey.self) { frames in
            mealSlotFrames.merge(frames) { _, new in new }
        }
        .simultaneousGesture(mealSlotTrackingGesture)
        .background(Color.appPageBackground.ignoresSafeArea())
    }

    private var draggedCategory: MealCategory? {
        guard let draggedCategoryID else { return nil }
        return categoriesDraft.first(where: { $0.id == draggedCategoryID })
    }

    private func isMealSlotArmed(_ id: String) -> Bool {
        draggedCategoryID == nil && armedCategoryID == id
    }

    private func mealSlotDragPreview(for category: MealCategory, frame: CGRect) -> some View {
        return ZStack(alignment: .topLeading) {
            Color.clear

            mealCategoryEditor(for: category)
                .frame(width: frame.width, alignment: .leading)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .compositingGroup()
        .shadow(color: .black.opacity(0.14), radius: 22, y: 10)
    }

    private func mealSlotFrameReader(for id: String) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: MealSlotFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named(mealSlotsCoordinateSpace))]
                )
        }
    }

    private var mealSlotTrackingGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(mealSlotsCoordinateSpace))
            .onChanged { value in
                guard let activeID = draggedCategoryID ?? armedCategoryID else { return }
                guard hypot(value.translation.width, value.translation.height) > 4 else { return }

                if draggedCategoryID == nil {
                    beginMealSlotDrag(for: activeID)
                }

                guard draggedCategoryID == activeID else { return }
                draggedCategoryOffset = value.translation
                updateMealSlotReorder()
            }
            .onEnded { _ in
                if draggedCategoryID != nil {
                    finishMealSlotDrag()
                } else if armedCategoryID != nil {
                    armedCategoryID = nil
                }
            }
    }

    private func armMealSlotIfNeeded(_ id: String) {
        guard armedCategoryID != id, draggedCategoryID == nil else { return }
        armedCategoryID = id
        triggerReorderActivationHaptic()
    }

    private func beginMealSlotDrag(for id: String) {
        guard let frame = mealSlotFrames[id], frame.width > 0, frame.height > 0 else { return }
        armedCategoryID = nil
        draggedCategoryID = id
        draggedCategoryFrame = frame
        draggedCategoryOffset = .zero
    }

    private func updateMealSlotReorder() {
        guard let draggedCategoryID,
              let fromIndex = categoriesDraft.firstIndex(where: { $0.id == draggedCategoryID }) else {
            return
        }

        let draggedMidY = draggedCategoryFrame.midY + draggedCategoryOffset.height
        guard let targetIndex = categoriesDraft.indices.first(where: { index in
            let candidate = categoriesDraft[index]
            guard candidate.id != draggedCategoryID,
                  let frame = mealSlotFrames[candidate.id] else {
                return false
            }
            return draggedMidY >= frame.minY && draggedMidY <= frame.maxY
        }), targetIndex != fromIndex else {
            return
        }

        withAnimation(.snappy(duration: 0.22)) {
            let movedCategory = categoriesDraft.remove(at: fromIndex)
            categoriesDraft.insert(movedCategory, at: targetIndex)
            for position in categoriesDraft.indices {
                categoriesDraft[position].sortOrder = position
            }
        }
    }

    private func finishMealSlotDrag() {
        guard draggedCategoryID != nil else { return }
        withAnimation(.snappy(duration: 0.18)) {
            armedCategoryID = nil
            draggedCategoryID = nil
            draggedCategoryOffset = .zero
            draggedCategoryFrame = .zero
        }
    }

    private func triggerReorderActivationHaptic() {
        PlatformFeedback.performSoftImpact()
    }

    private var goalShareTotal: Int {
        categoriesDraft.reduce(0) { $0 + max($1.goalSharePercent, 0) }
    }

    private var canAddCategory: Bool {
        firstAvailablePreset() != nil
    }

    private var goalShareWarning: String? {
        if goalShareTotal < 100 {
            return String(format: NSLocalizedString("nutrition.mealslots.goal_share_remaining", comment: "Remaining goal share warning"), 100 - goalShareTotal)
        }
        return nil
    }

    private var macroTotal: Int {
        goalDraft.proteinPercent + goalDraft.fatPercent + goalDraft.carbsPercent
    }

    private var macroWarning: String? {
        if macroTotal < 100 {
            return String(format: NSLocalizedString("nutrition.goal.macros_remaining", comment: "Missing macro percentage warning"), 100 - macroTotal)
        }
        return nil
    }

    private func mealCategoryEditor(for category: MealCategory, isHighlighted: Bool = false) -> some View {
        let id = category.id
        return NutritionGoalCard(isHighlighted: isHighlighted) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    mealTypeButton(for: id)

                    Button(role: .destructive) {
                        removeCategory(id: id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.headline)
                            .foregroundStyle(.red)
                            .frame(width: 44, height: 44)
                            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .opacity(categoriesDraft.count == 1 ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(categoriesDraft.count == 1)
                }

                Divider()

                HStack(spacing: 12) {
                    Text("nutrition.mealslots.preferred_time")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    preferredTimePicker(for: id)
                }
            }
        }
    }

    private func mealTypeButton(for id: String) -> some View {
        let currentPresetID = selectedPreset(for: id)?.id

        return Menu {
            ForEach(MealSlotPreset.all) { preset in
                let isUnavailable = isPresetUsed(preset, excluding: id)

                Button {
                    applyPreset(preset, to: id)
                } label: {
                    HStack(spacing: 10) {
                        Label(preset.title, systemImage: preset.symbolName)

                        Spacer(minLength: 12)

                        if currentPresetID == preset.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .disabled(isUnavailable)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: binding(for: id, keyPath: \.symbolName).wrappedValue)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.appPageBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(categoryDisplayTitle(for: id))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 0)
            .background(Color.appPageBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func preferredTimePicker(for id: String) -> some View {
        DatePicker(
            "",
            selection: preferredTimeBinding(for: id),
            displayedComponents: [.hourAndMinute]
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .frame(maxWidth: 132, alignment: .trailing)
    }

    private func formattedPreferredTime(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private func preferredTimeBinding(for id: String) -> Binding<Date> {
        Binding(
            get: {
                preferredTimeDrafts[id] ?? defaultPreferredTime(for: id)
            },
            set: { newValue in
                preferredTimeDrafts[id] = newValue
                binding(for: id, keyPath: \.preferredHour).wrappedValue = Calendar.current.component(.hour, from: newValue)
                binding(for: id, keyPath: \.preferredMinute).wrappedValue = Calendar.current.component(.minute, from: newValue)
            }
        )
    }

    private func defaultPreferredTime(for id: String) -> Date {
        let hour = binding(for: id, keyPath: \.preferredHour).wrappedValue
        let minute = binding(for: id, keyPath: \.preferredMinute).wrappedValue
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func syncPreferredTimeDrafts() {
        preferredTimeDrafts = Dictionary(
            uniqueKeysWithValues: categoriesDraft.map { category in
                (category.id, Calendar.current.date(bySettingHour: category.preferredHour, minute: category.preferredMinute, second: 0, of: Date()) ?? Date())
            }
        )
    }

    private func selectedPreset(for id: String) -> MealSlotPreset? {
        guard let index = indexOfCategory(withID: id) else { return nil }
        return selectedPreset(for: categoriesDraft[index])
    }

    private func selectedPreset(for category: MealCategory) -> MealSlotPreset? {
        let trimmedTitle = category.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let titleMatch = MealSlotPreset.all.first(where: {
            $0.title.compare(trimmedTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return titleMatch
        }

        return MealSlotPreset.all.first(where: { $0.id == category.id })
    }

    private func isPresetUsed(_ preset: MealSlotPreset, excluding id: String? = nil) -> Bool {
        categoriesDraft.contains { category in
            guard category.id != id else { return false }
            return selectedPreset(for: category)?.id == preset.id
        }
    }

    private func firstAvailablePreset(excluding id: String? = nil) -> MealSlotPreset? {
        MealSlotPreset.all.first { !isPresetUsed($0, excluding: id) }
    }

    private func redistributeOverflow(from index: Int) {
        var overflow = max(0, goalShareTotal - 100)
        guard overflow > 0 else { return }

        for currentIndex in categoriesDraft.indices.reversed() where currentIndex != index {
            guard overflow > 0 else { break }
            let currentValue = categoriesDraft[currentIndex].goalSharePercent
            let reduction = min(currentValue, overflow)
            categoriesDraft[currentIndex].goalSharePercent -= reduction
            overflow -= reduction
        }

        if overflow > 0 {
            categoriesDraft[index].goalSharePercent = max(0, categoriesDraft[index].goalSharePercent - overflow)
        }
    }

    private func applyPreset(_ preset: MealSlotPreset, to id: String) {
        guard !isPresetUsed(preset, excluding: id) else { return }
        guard selectedPreset(for: id)?.id != preset.id else { return }
        binding(for: id, keyPath: \.title).wrappedValue = preset.title
        binding(for: id, keyPath: \.symbolName).wrappedValue = preset.symbolName
        binding(for: id, keyPath: \.preferredHour).wrappedValue = preset.preferredHour
        binding(for: id, keyPath: \.isEnabled).wrappedValue = true
        preferredTimeDrafts[id] = Calendar.current.date(bySettingHour: preset.preferredHour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func categoryDisplayTitle(for id: String) -> String {
        guard let index = indexOfCategory(withID: id) else {
            return NSLocalizedString("meal.custom_default", comment: "Default custom meal title")
        }
        return categoriesDraft[index].displayTitle
    }

    private func addCategory() {
        guard let preset = firstAvailablePreset() else { return }

        let nextIndex = categoriesDraft.count
        let category = MealCategory(
            id: preset.id,
            title: preset.title,
            symbolName: preset.symbolName,
            sortOrder: nextIndex,
            isEnabled: true,
            preferredHour: preset.preferredHour,
            preferredMinute: 0,
            goalSharePercent: max(5, 100 / max(nextIndex + 1, 1))
        )

        categoriesDraft.append(category)
        preferredTimeDrafts[category.id] = Calendar.current.date(bySettingHour: preset.preferredHour, minute: 0, second: 0, of: Date()) ?? Date()
        rebalanceGoalSharesIfNeeded()
    }

    private func removeCategory(id: String) {
        guard categoriesDraft.count > 1, let index = indexOfCategory(withID: id) else { return }
        categoriesDraft.remove(at: index)
        preferredTimeDrafts.removeValue(forKey: id)
        for position in categoriesDraft.indices {
            categoriesDraft[position].sortOrder = position
        }
        rebalanceGoalSharesIfNeeded()
    }

    private func indexOfCategory(withID id: String) -> Int? {
        categoriesDraft.firstIndex(where: { $0.id == id })
    }

    private func binding<Value>(for id: String, keyPath: WritableKeyPath<MealCategory, Value>) -> Binding<Value> {
        Binding(
            get: {
                guard let index = indexOfCategory(withID: id) else {
                    return MealCategory.default[0][keyPath: keyPath]
                }
                return categoriesDraft[index][keyPath: keyPath]
            },
            set: { newValue in
                guard let index = indexOfCategory(withID: id) else { return }
                categoriesDraft[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func goalShareBinding(for id: String) -> Binding<Int> {
        Binding(
            get: {
                guard let index = indexOfCategory(withID: id) else { return 0 }
                return categoriesDraft[index].goalSharePercent
            },
            set: { newValue in
                setGoalShare(newValue, for: id)
            }
        )
    }

    private func setGoalShare(_ newValue: Int, for id: String) {
        guard let index = indexOfCategory(withID: id) else { return }
        let clampedValue = min(max(newValue, 0), 100)

        guard categoriesDraft.count > 1 else {
            categoriesDraft[index].goalSharePercent = 100
            return
        }

        categoriesDraft[index].goalSharePercent = clampedValue
        if goalShareTotal > 100 {
            redistributeOverflow(from: index)
        }
    }

    private func rebalanceGoalSharesIfNeeded() {
        guard goalShareTotal > 100 else { return }
        distributeGoalShare(100, across: Array(categoriesDraft.indices))
    }

    private func rebalanceGoalSharesEvenly() {
        let indices = Array(categoriesDraft.indices)
        distributeGoalShare(100, across: indices)
    }

    private func macroEditorRow(
        titleKey: LocalizedStringKey,
        input: Binding<String>,
        grams: Int,
        focusedField: GoalEditorField,
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
                        .focused($focusedGoalField, equals: focusedField)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .frame(width: 64)
                        .onChange(of: input.wrappedValue) { _, newValue in
                            guard self.focusedGoalField == focusedField else { return }
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

    private func widgetRingMetricButton(for metric: AppSettings.NutritionWidgetRingMetric) -> some View {
        let selectionIndex = widgetRingMetricsDraft.firstIndex(of: metric)
        let isSelected = selectionIndex != nil
        let isDisabled = !isSelected && widgetRingMetricsDraft.count >= 3

        return Button {
            toggleWidgetRingMetric(metric)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(metric.tint)
                    .frame(width: 10, height: 10)

                Text(metric.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let selectionIndex {
                    Text("\(selectionIndex + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(metric.tint, in: Circle())
                } else {
                    Image(systemName: isDisabled ? "lock.fill" : "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isDisabled ? .tertiary : .secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                    .fill(metric.tint.opacity(isSelected ? 0.18 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                    .stroke(metric.tint.opacity(isSelected ? 0.35 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }

    private var widgetRingsTitle: String {
        NSLocalizedString("settings.widget_rings.title", tableName: nil, bundle: .main, value: "Widget rings", comment: "Widget rings settings title")
    }

    private var widgetRingsHelper: String {
        NSLocalizedString("settings.widget_rings.helper", tableName: nil, bundle: .main, value: "Choose three metrics. The selection order is used from outer ring to inner ring.", comment: "Widget rings settings helper")
    }

    private var widgetRingsCounterTitle: String {
        NSLocalizedString("settings.widget_rings.counter", tableName: nil, bundle: .main, value: "Selected", comment: "Widget rings selected counter label")
    }

    private var widgetRingsWarning: String {
        NSLocalizedString("settings.widget_rings.warning", tableName: nil, bundle: .main, value: "Choose exactly 3 rings.", comment: "Widget rings warning")
    }

    private func syncGoalInputFields(excluding excludedField: GoalEditorField? = nil) {
        normalizeGoalDraftIfNeeded()

        if excludedField != .calories {
            calorieInput = String(goalDraft.calories)
        }

        if excludedField != .protein {
            proteinInput = String(goalDraft.proteinPercent)
        }

        if excludedField != .fat {
            fatInput = String(goalDraft.fatPercent)
        }

        if excludedField != .carbs {
            carbsInput = String(goalDraft.carbsPercent)
        }
    }

    private func normalizeGoalDraftIfNeeded() {
        if goalDraft.calories < 100 {
            goalDraft.calories = 100
        }

        goalDraft.proteinPercent = min(max(goalDraft.proteinPercent, 0), 100)
        goalDraft.fatPercent = min(max(goalDraft.fatPercent, 0), 100)
        goalDraft.carbsPercent = min(max(goalDraft.carbsPercent, 0), 100)
    }

    private func handleCaloriesInputChange(_ newValue: String) {
        let digits = newValue.filter(\.isNumber)
        if digits != newValue {
            calorieInput = digits
        }

        guard !digits.isEmpty else {
            goalDraft.calories = 0
            return
        }

        let clampedValue = min(Int(digits) ?? goalDraft.calories, 10000)
        goalDraft.calories = clampedValue

        let normalizedValue = String(clampedValue)
        if digits != normalizedValue && clampedValue == 10000 {
            calorieInput = normalizedValue
        }
    }

    private func handleMacroInputChange(
        _ newValue: String,
        field: GoalEditorField,
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

    private func dietPlanOptionButton(for plan: DietPlanOption) -> some View {
        let isSelected = dietPlanDraft == plan
        let split = plan.macroSplit
        let tint = dietPlanTint(for: plan)

        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                dietPlanDraft = plan
                goalDraft = plan.applying(to: goalDraft)
                syncGoalInputFields()
            }
        } label: {
            NutritionGoalCard(isHighlighted: isSelected) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: plan.symbolName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 44, height: 44)
                            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // Takes the width left over by the symbol and the tick
                        // rather than sharing it with a Spacer.
                        //
                        // A Spacer here was the reason the description broke over
                        // three narrow lines with a gap beside it: an HStack
                        // splits its width between the flexible children, and a
                        // Spacer is as flexible as text, so the description was
                        // offered about half of what was free and wrapped inside
                        // it. Pushing the tick out with a frame instead leaves
                        // the description everything the row is not using.
                        VStack(alignment: .leading, spacing: 5) {
                            Text(plan.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            Text(plan.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(isSelected ? tint : Color.secondary.opacity(0.35))
                    }

                    HStack(spacing: 10) {
                        macroSummaryPill(titleKey: "diary.protein", valueText: "\(split.proteinPercent)%", tint: .green)
                        macroSummaryPill(titleKey: "diary.fat", valueText: "\(split.fatPercent)%", tint: WeeklyMacroBarColors.fat)
                        macroSummaryPill(titleKey: "diary.carbs", valueText: "\(split.carbsPercent)%", tint: .blue)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(plan.title))
    }

    private func dietPlanTint(for plan: DietPlanOption) -> Color {
        switch plan {
        case .balanced:
            return .indigo
        case .highProtein:
            return .red
        case .lowerCarb:
            return .green
        case .mediterranean:
            return .teal
        case .intermittent:
            return .blue
        }
    }

    private func adjustCalories(by delta: Int) {
        dismissKeyboard()
        let baseCalories = max(goalDraft.calories, 100)
        goalDraft.calories = min(max(baseCalories + delta, 100), 10000)
        syncGoalInputFields()
    }

    private func adjustMacroPercent(by delta: Int, component: WritableKeyPath<DailyNutritionGoal, Int>) {
        dismissKeyboard()
        setMacroPercent(goalDraft[keyPath: component] + delta, component: component)
        syncGoalInputFields()
    }

    private func toggleWidgetRingMetric(_ metric: AppSettings.NutritionWidgetRingMetric) {
        if let selectionIndex = widgetRingMetricsDraft.firstIndex(of: metric) {
            widgetRingMetricsDraft.remove(at: selectionIndex)
            return
        }

        guard widgetRingMetricsDraft.count < 3 else { return }
        widgetRingMetricsDraft.append(metric)
    }

    private func saveChanges() {
        dismissKeyboard()

        if mode == .dietPlan {
            diaryService.setDietPlan(dietPlanDraft)
        } else if mode == .calorieGoal {
            diaryService.setDailyGoal(selectedGoal)
        } else if mode == .widgetRings {
            appSettings.setNutritionWidgetRingMetrics(widgetRingMetricsDraft)
        } else {
            diaryService.setMealCategories(categoriesDraft)
        }

        dismiss()
    }

    private func resetDrafts() {
        if let initialGoal {
            goalDraft = initialGoal
            syncGoalInputFields()
        }

        if let initialCategories {
            categoriesDraft = initialCategories
            syncPreferredTimeDrafts()
        }

        if let initialDietPlan {
            dietPlanDraft = initialDietPlan
        }

        if let initialWidgetRingMetrics {
            widgetRingMetricsDraft = initialWidgetRingMetrics
        }
    }

    private func dismissKeyboard() {
        focusedGoalField = nil
        syncGoalInputFields()
    }

    private func distributeGoalShare(_ total: Int, across indices: [Int]) {
        guard !indices.isEmpty else { return }
        let baseShare = total / indices.count
        let remainder = total % indices.count

        for (offset, index) in indices.enumerated() {
            categoriesDraft[index].goalSharePercent = baseShare + (offset < remainder ? 1 : 0)
        }
    }

    private func setMacroPercent(_ newValue: Int, component: WritableKeyPath<DailyNutritionGoal, Int>) {
        goalDraft[keyPath: component] = min(max(newValue, 0), 100)

        var overflow = max(0, macroTotal - 100)
        guard overflow > 0 else { return }

        let otherComponents: [WritableKeyPath<DailyNutritionGoal, Int>] = [\.proteinPercent, \.fatPercent, \.carbsPercent]
            .filter { $0 != component }

        for keyPath in otherComponents.reversed() {
            guard overflow > 0 else { break }
            let currentValue = goalDraft[keyPath: keyPath]
            let reduction = min(currentValue, overflow)
            goalDraft[keyPath: keyPath] -= reduction
            overflow -= reduction
        }

        if overflow > 0 {
            goalDraft[keyPath: component] = max(0, goalDraft[keyPath: component] - overflow)
        }

        syncGoalInputFields(excluding: focusedGoalField)
    }
}

private struct NutritionGoalCard<Content: View>: View {
    let isHighlighted: Bool
    @ViewBuilder let content: Content

    init(isHighlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHighlighted ? Color.platformSystemGray5 : Color.appCardBackground,
                in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
            )
            .animation(.easeInOut(duration: 0.16), value: isHighlighted)
    }
}

private struct MealSlotFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
