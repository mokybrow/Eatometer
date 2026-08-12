import SwiftUI

struct HabitEditorSheet: View {
    enum Mode {
        case create
        case edit(Habit)
    }

    let mode: Mode
    let quickTemplates: [HabitTemplate]
    let trackedTemplateIDs: Set<String>
    let onSave: (HabitEditorPayload) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var kind: HabitKind
    @State private var icon: String
    @State private var colorHex: String
    @State private var dailyTarget: Int
    @State private var unitLabel: String
    @State private var trackingMode: HabitTrackingMode
    @State private var hasDurationLimit: Bool
    @State private var targetDays: Int
    @State private var archived: Bool
    @State private var isSaving = false

    init(
        mode: Mode,
        quickTemplates: [HabitTemplate] = [],
        trackedTemplateIDs: Set<String> = [],
        clientSettings: HabitClientSettings? = nil,
        onSave: @escaping (HabitEditorPayload) async -> Bool
    ) {
        self.mode = mode
        self.quickTemplates = quickTemplates
        self.trackedTemplateIDs = trackedTemplateIDs
        self.onSave = onSave
        let resolvedSettings: HabitClientSettings
        switch mode {
        case .create:
            resolvedSettings = clientSettings ?? HabitClientSettings(trackingMode: .manual, targetDays: nil, isReminderEnabled: true)
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _kind = State(initialValue: .build)
            _icon = State(initialValue: "leaf.fill")
            _colorHex = State(initialValue: "#34C759")
            _dailyTarget = State(initialValue: 0)
            _unitLabel = State(initialValue: "")
            _archived = State(initialValue: false)
        case .edit(let habit):
            resolvedSettings = clientSettings ?? habit.clientSettings
            _name = State(initialValue: habit.name)
            _description = State(initialValue: habit.description)
            _kind = State(initialValue: habit.kind)
            _icon = State(initialValue: habit.icon)
            _colorHex = State(initialValue: habit.colorHex)
            _dailyTarget = State(initialValue: Self.resolvedDailyTarget(for: habit))
            _unitLabel = State(initialValue: habit.unitLabel)
            _archived = State(initialValue: habit.isArchived)
        }
        _trackingMode = State(initialValue: resolvedSettings.trackingMode)
        _hasDurationLimit = State(initialValue: resolvedSettings.targetDays != nil)
        _targetDays = State(initialValue: resolvedSettings.targetDays ?? 30)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isSaving
    }

    private var selectedColor: Color {
        Color(hex: colorHex) ?? .accentColor
    }

    private var shouldShowTargetCard: Bool {
        kind == .build && trackingMode == .automatic && !isNutritionGoalTemplateSelected
    }

    private var shouldKeepDailyTarget: Bool {
        trackingMode == .automatic
    }

    private var availableQuickTemplates: [HabitTemplate] {
        quickTemplates.filter { !trackedTemplateIDs.contains($0.id) }
    }

    private var isNutritionGoalTemplateSelected: Bool {
        let localizedName = NSLocalizedString("habits.idea.nutritionGoal", comment: "")
        let localizedDescription = NSLocalizedString("habits.template.nutritionGoal.desc", comment: "")
        return name == localizedName && description == localizedDescription && icon == "target"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                EOCard {
                    EOTextFieldRow("habits.editor.name", text: $name)
                    EORowSeparator()

                    EOToggleRow(
                        "habits.editor.manual_mark",
                        isOn: Binding(
                            get: { trackingMode == .manual },
                            set: { trackingMode = $0 ? .manual : .automatic }
                        )
                    )
                    EORowSeparator()

                    iconRow
                    EORowSeparator()

                    EOToggleRow("habits.editor.countdown", isOn: $hasDurationLimit)
                    EORowSeparator()

                    EOStepperRow(
                        title: Text(
                            verbatim: String(
                                format: NSLocalizedString("habits.editor.days_remaining_value", comment: "Days remaining"),
                                hasDurationLimit ? targetDays : 0
                            )
                        ),
                        canDecrement: hasDurationLimit && targetDays > 1,
                        canIncrement: hasDurationLimit && targetDays < 3_650,
                        onDecrement: { targetDays = max(1, targetDays - 1) },
                        onIncrement: { targetDays = min(3_650, targetDays + 1) }
                    )
                }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .eoPageBackground()
            .overlay {
                if isSaving {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .eoSheetChrome(
                "habits.editor.sheet_title",
                trailing: .confirm(isEnabled: canSave) {
                    Task { await save() }
                },
                onClose: { dismiss() }
            )
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// "Icon  ★ ⌃⌄" row — a menu field, which is what it is.
    ///
    /// It used to read "Edit ›": the word belongs on a row that pushes a screen,
    /// and `chevron.right` says the same thing again. Nothing is pushed here —
    /// a menu drops down in place — and the platform spells that
    /// `chevron.up.chevron.down`, as every other menu row in the app does.
    private var iconRow: some View {
        EOListRow(title: Text("habits.editor.icon")) {
            Menu {
                Picker("", selection: $icon) {
                    ForEach(HabitPalette.icons, id: \.self) { symbol in
                        // Named, not addressed. The tag stays the symbol, so
                        // what is stored is unchanged.
                        Label {
                            Text(verbatim: HabitPalette.title(for: symbol))
                        } icon: {
                            Image(systemName: symbol)
                        }
                        .tag(symbol)
                    }
                }
                .labelsHidden()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(selectedColor)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                }
            }
            .fixedSize()
            .accessibilityLabel(Text("habits.editor.icon"))
            .accessibilityValue(Text(verbatim: HabitPalette.title(for: icon)))
        }
    }

    private var navigationTitleKey: String {
        switch mode {
        case .create: return "habits.editor.title.create"
        case .edit: return "habits.editor.title.edit"
        }
    }

    // MARK: - Cards

    private var templatesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitleText(localizedEditorString("habits.templates.title", fallback: "Quick start"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableQuickTemplates) { template in
                        templateChip(template)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    private func templateChip(_ template: HabitTemplate) -> some View {
        let templateTint = Color(hex: template.colorHex) ?? .accentColor
        return Button {
            apply(template: template)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(templateTint.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: template.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(templateTint)
                }
                Text(LocalizedStringKey(template.nameKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(LocalizedStringKey(template.descriptionKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 180, alignment: .leading)
            .frame(minHeight: 124, alignment: .leading)
            .padding(14)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func apply(template: HabitTemplate) {
        name = NSLocalizedString(template.nameKey, comment: "")
        description = NSLocalizedString(template.descriptionKey, comment: "")
        kind = template.kind
        icon = template.icon
        colorHex = template.colorHex
        dailyTarget = template.dailyTarget
        trackingMode = .automatic
        if let unitKey = template.unitLabelKey {
            unitLabel = NSLocalizedString(unitKey, comment: "")
        } else {
            unitLabel = ""
        }
    }

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitleText(localizedEditorString("habits.editor.basic", fallback: "Basic"))
            VStack(spacing: 0) {
                TextField("habits.editor.name", text: $name)
                    .textInputAutocapitalization(.sentences)
                    .padding(.vertical, 14)
                Divider().opacity(0.4)
                TextField("habits.editor.description", text: $description, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.vertical, 14)
            }
            .padding(.horizontal, 16)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
        .padding(.horizontal, 0)
    }

    private var kindCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("habits.editor.kind")
            Picker("habits.editor.kind", selection: $kind) {
                ForEach(HabitKind.allCases, id: \.self) { value in
                    Text(LocalizedStringKey(value.titleKey)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            Text(LocalizedStringKey(kind == .build ? "habits.editor.kind.build_hint" : "habits.editor.kind.quit_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitleText(localizedEditorString("habits.editor.tracking", fallback: "Tracking"))
            Picker(localizedEditorString("habits.editor.tracking", fallback: "Tracking"), selection: $trackingMode) {
                Text(localizedEditorString("habits.tracking.automatic", fallback: "Automatic")).tag(HabitTrackingMode.automatic)
                Text(localizedEditorString("habits.tracking.manual", fallback: "Manual check")).tag(HabitTrackingMode.manual)
            }
            .pickerStyle(.segmented)

            Text(localizedEditorString(
                trackingMode == .manual ? "habits.editor.tracking.manual_hint" : "habits.editor.tracking.automatic_hint",
                fallback: trackingMode == .manual
                    ? "You will open the habit and mark completion yourself."
                    : "Eatometer will calculate progress from food and water data when it can."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitleText(localizedEditorString("habits.editor.duration", fallback: "Duration"))
            VStack(spacing: 0) {
                Toggle(localizedEditorString("habits.editor.duration.limited", fallback: "Set a number of days"), isOn: $hasDurationLimit)
                    .padding(.vertical, 10)
                if hasDurationLimit {
                    Divider().opacity(0.4)
                    Stepper(value: $targetDays, in: 1...365) {
                        HStack {
                            Text(localizedEditorString("habits.editor.duration.days", fallback: "Days"))
                            Spacer()
                            Text("\(targetDays)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 16)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("habits.editor.color")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                colorGrid
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("habits.editor.icon")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                iconGrid
            }
        }
        .padding(16)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("habits.editor.daily_target")
            Text("habits.editor.daily_target.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Stepper(value: $dailyTarget, in: 0...50) {
                    HStack {
                        Text("habits.editor.daily_target.label")
                        Spacer()
                        Text(dailyTarget == 0
                             ? NSLocalizedString("habits.editor.daily_target.none", comment: "")
                             : "\(dailyTarget)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 8)
                if dailyTarget > 0 {
                    Divider().opacity(0.4)
                    TextField("habits.editor.unit_label", text: $unitLabel)
                        .textInputAutocapitalization(.never)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var archiveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("habits.editor.archive", isOn: $archived)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
            Text("habits.editor.archive.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Grids

    private var iconGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(HabitPalette.icons, id: \.self) { sym in
                let isSelected = sym == icon
                Button {
                    icon = sym
                } label: {
                    Image(systemName: sym)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(isSelected ? selectedColor : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                // A grid of drawings reads as nothing at all through VoiceOver
                // without this — the symbol name is an address, not a label.
                .accessibilityLabel(Text(verbatim: HabitPalette.title(for: sym)))
            }
        }
    }

    private var colorGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(HabitPalette.colors, id: \.self) { hex in
                let isSelected = hex.lowercased() == colorHex.lowercased()
                Button {
                    colorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.85), lineWidth: isSelected ? 2.5 : 0)
                                .padding(2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private func sectionTitleText(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private func localizedEditorString(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "Habit editor text")
    }

    private static func resolvedDailyTarget(for habit: Habit) -> Int {
        if HabitAutomaticTracker(habit: habit) == .sugar, habit.dailyTarget <= 0 {
            return HabitTemplate.adultSugarDailyTargetGrams
        }

        return habit.dailyTarget
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        let payload = HabitEditorPayload(
            name: trimmedName,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            icon: icon,
            colorHex: colorHex,
            dailyTarget: shouldKeepDailyTarget ? dailyTarget : 0,
            unitLabel: shouldKeepDailyTarget ? unitLabel.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            archived: archived,
            clientSettings: HabitClientSettings(
                trackingMode: trackingMode,
                targetDays: hasDurationLimit ? targetDays : nil,
                isReminderEnabled: trackingMode == .manual
            )
        )
        let success = await onSave(payload)
        isSaving = false
        if success { dismiss() }
    }
}

struct HabitEditorPayload {
    let name: String
    let description: String
    let kind: HabitKind
    let icon: String
    let colorHex: String
    let dailyTarget: Int
    let unitLabel: String
    let archived: Bool
    let clientSettings: HabitClientSettings
}
