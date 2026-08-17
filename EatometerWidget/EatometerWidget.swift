import WidgetKit
import SwiftUI
import AppIntents
import UIKit

private final class WidgetLocalizationBundleToken {}

private enum WidgetLocalization {
    static let bundle = Bundle(for: WidgetLocalizationBundleToken.self)

    static func string(_ key: String, defaultValue: String, comment: String) -> String {
        NSLocalizedString(
            key,
            tableName: nil,
            bundle: bundle,
            value: defaultValue,
            comment: comment
        )
    }
}

private extension EatometerWidgetAccent {
    var color: Color {
        Color(widgetHex: hexValue) ?? .accentColor
    }
}

/// The four nutrition colours, matching the app's own.
///
/// Kept here rather than imported: the widget extension does not build the
/// app's design system, and four literals that must not drift are better
/// stated once than repeated at each ring.
enum EatometerWidgetPalette {
    static let calories = Color(red: 1.0, green: 0.196, blue: 0.529)    // #FF3287
    static let protein = Color(red: 0.0, green: 0.792, blue: 0.871)     // #00CADE
    static let carbs = Color(red: 0.302, green: 0.886, blue: 0.0)       // #4DE200
    static let fat = Color(red: 0.906, green: 0.576, blue: 0.047)       // #E79310
}

/// Text on a system background is `.primary` and `.secondary`, whatever the
/// style.
///
/// These used to hand-mix a near-black and a translucent white per style,
/// which was necessary while the tiles painted their own gradients. On
/// `systemBackground` the system's own label colours are already the right
/// ones, and they follow the appearance — and Increase Contrast — without
/// being recomputed. Transparent tiles sit on the wallpaper and still need
/// the opaque pair.
private func widgetPrimaryText(style: EatometerWidgetVisualStyle, isDark: Bool) -> Color {
    guard style == .transparent else { return .primary }
    return isDark ? .white : Color(red: 0.09, green: 0.09, blue: 0.10)
}

private func widgetSecondaryText(style: EatometerWidgetVisualStyle, isDark: Bool) -> Color {
    guard style == .transparent else { return .secondary }
    return isDark ? .white.opacity(0.76) : Color.black.opacity(0.58)
}

private struct EatometerWidgetChromeModifier: ViewModifier {
    let style: EatometerWidgetVisualStyle

    func body(content: Content) -> some View {
        content
            .background(backgroundView)
            .containerBackground(for: .widget) {
                backgroundView
            }
    }

    /// One plain surface, and the system decides what colour it is.
    ///
    /// The tiles used to be two stacked gradients with the accent washed over
    /// the top, in a different arrangement per style. Against the rings — which
    /// are four saturated colours and the only thing on the tile that should
    /// carry any — that read as noise, and a tinted card cannot be white in
    /// light mode and dark in dark mode without being written twice and kept
    /// in step by hand.
    ///
    /// `systemBackground` is the colour the system already uses for a sheet of
    /// paper: white on a light device, near-black on a dark one, and it follows
    /// the appearance changing underneath the widget without being told.
    @ViewBuilder
    private var backgroundView: some View {
        if style == .transparent {
            Color.clear
        } else {
            Color(uiColor: .systemBackground)
        }
    }
}

private extension View {
    func eatometerWidgetChrome(style: EatometerWidgetVisualStyle) -> some View {
        modifier(EatometerWidgetChromeModifier(style: style))
    }
}

struct WaterWidgetEntry: TimelineEntry {
    let date: Date
    let intakeMilliliters: Int
    let goalMilliliters: Int
    let adjustmentMilliliters: Int
    let style: EatometerWidgetVisualStyle
    let accent: EatometerWidgetAccent
}

struct WaterWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WaterWidgetEntry {
        WaterWidgetEntry(
            date: .now,
            intakeMilliliters: 900,
            goalMilliliters: 2000,
            adjustmentMilliliters: 200,
            style: .glass,
            accent: .blue
        )
    }

    func snapshot(for configuration: WaterWidgetConfigurationIntent, in context: Context) async -> WaterWidgetEntry {
        makeEntry(
            style: .glass,
            accent: .blue
        )
    }

    func timeline(for configuration: WaterWidgetConfigurationIntent, in context: Context) async -> Timeline<WaterWidgetEntry> {
        let entry = makeEntry(
            style: .glass,
            accent: .blue
        )
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    private func makeEntry(style: EatometerWidgetVisualStyle, accent: EatometerWidgetAccent) -> WaterWidgetEntry {
        let state = EatometerWidgetStore.loadWaterState()
        return WaterWidgetEntry(
            date: .now,
            intakeMilliliters: state.intake,
            goalMilliliters: state.goal,
            adjustmentMilliliters: EatometerWidgetStore.loadWaterWidgetStep(),
            style: style,
            accent: accent
        )
    }
}

struct WaterWidgetView: View {
    let entry: WaterWidgetEntry

    private let waterDeepLink = URL(string: "eatometer://water")

    private var progressText: String {
        String.localizedStringWithFormat(
            WidgetLocalization.string(
                "water.subtitle",
                defaultValue: "%d / %d ml",
                comment: "Water widget progress"
            ),
            entry.intakeMilliliters,
            entry.goalMilliliters
        )
    }

    private var progressRatio: Double {
        guard entry.goalMilliliters > 0 else { return 0 }
        return min(max(Double(entry.intakeMilliliters) / Double(entry.goalMilliliters), 0), 1)
    }

    /// Built from stock controls, so the system can restyle it.
    ///
    /// This used to be a hand-drawn glass: two custom `Shape`s filling the tile
    /// bottom-up with a gradient, a stroked surface line, and buttons made of a
    /// circle and a symbol. It looked right in exactly one appearance. A widget
    /// is rendered by the system in several — light, dark, the tinted and
    /// glass treatments the device applies to the whole Home Screen — and it
    /// does that by re-colouring standard controls. A gradient built from fixed
    /// opacities is not a control; it stays the colour it was written as while
    /// everything around it changes.
    ///
    /// `Gauge` and a bordered `Button` are controls. They take the tint the
    /// system hands them and follow the theme without knowing it exists.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(progressText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Gauge(value: progressRatio) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(.blue)

            Spacer(minLength: 0)

            waterControls
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .eatometerWidgetChrome(style: entry.style)
        .widgetURL(waterDeepLink)
    }

    /// Minus and plus, and nothing else.
    ///
    /// There was a third button hard-coded to +50 ml beside them. It duplicated
    /// what plus already did — the step is a setting, and somebody who wants 50
    /// sets 50 — while taking a third of a row that has to stay tappable at
    /// this size.
    /// One at each end, with the row between them.
    ///
    /// Both were bunched against the left edge, which left a third of the tile
    /// empty and put two 30-point targets a few points apart — the two things
    /// you least want adjacent when one adds water and the other takes it away.
    /// Pushed apart, each has the corner it sits nearest, and a mis-tap has to
    /// cross the tile to happen.
    private var waterControls: some View {
        HStack(spacing: 0) {
            waterControlButton(systemImage: "minus", delta: -entry.adjustmentMilliliters)
                .disabled(entry.intakeMilliliters <= 0)

            Spacer(minLength: 8)

            waterControlButton(systemImage: "plus", delta: entry.adjustmentMilliliters)
        }
        .frame(maxWidth: .infinity)
    }

    private func waterControlButton(systemImage: String, delta: Int) -> some View {
        Button(intent: AdjustWaterIntakeIntent(delta: delta)) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        // Stock styling, on purpose: `.bordered` is what the system knows how
        // to re-render for a tinted or glass Home Screen. A `Circle().fill()`
        // behind a symbol would arrive as a solid disc of the wrong colour.
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.blue)
    }
}

struct EatometerWidget: Widget {
    static let kind: String = EatometerWidgetStore.waterWidgetKind

    private var displayNameText: String {
        WidgetLocalization.string(
            "water.title",
            defaultValue: "Water",
            comment: "Water widget display name"
        )
    }

    private var descriptionText: String {
        WidgetLocalization.string(
            "widget.gallery.water.description.v2",
            defaultValue: "Track water and adjust it directly from the widget.",
            comment: "Water widget gallery description"
        )
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: WaterWidgetConfigurationIntent.self, provider: WaterWidgetProvider()) { entry in
            WaterWidgetView(entry: entry)
        }
        .configurationDisplayName(displayNameText)
        .description(descriptionText)
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}

private struct QuickMealWidgetEntry: TimelineEntry {
    let date: Date
    let calories: Int
    let caloriesGoal: Int
    let mealCategories: [EatometerMealCategorySummary]
    let meals: [EatometerTodayMealSummary]
    let style: EatometerWidgetVisualStyle
    let accent: EatometerWidgetAccent
}

private struct QuickMealWidgetProvider: AppIntentTimelineProvider {
    /// Four meals, and no longer a choice.
    ///
    /// Five and six were offered, and both needed a three-column grid whose
    /// tiles were too small to aim at — the ring, the name and the figure all
    /// had to shrink to fit. Four fills the row at a size that can be tapped,
    /// and four is what a day usually has.
    static let mealSlotLimit = 4

    func placeholder(in context: Context) -> QuickMealWidgetEntry {
        makePlaceholderEntry()
    }

    func snapshot(for configuration: QuickMealWidgetConfigurationIntent, in context: Context) async -> QuickMealWidgetEntry {
        makeEntry(style: .glass, accent: .app)
    }

    func timeline(for configuration: QuickMealWidgetConfigurationIntent, in context: Context) async -> Timeline<QuickMealWidgetEntry> {
        let entry = makeEntry(style: .glass, accent: .app)
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    private func makeEntry(
        style: EatometerWidgetVisualStyle,
        accent: EatometerWidgetAccent
    ) -> QuickMealWidgetEntry {
        guard let snapshot = EatometerWidgetStore.loadTodaySnapshot() else {
            return makePlaceholderEntry(style: style, accent: accent)
        }

        let categories = snapshot.mealCategories.isEmpty ? Self.defaultCategories() : snapshot.mealCategories
        return QuickMealWidgetEntry(
            date: .now,
            calories: snapshot.calories,
            caloriesGoal: snapshot.caloriesGoal,
            mealCategories: Array(categories.prefix(Self.mealSlotLimit)),
            meals: snapshot.meals,
            style: style,
            accent: accent
        )
    }

    private func makePlaceholderEntry(
        style: EatometerWidgetVisualStyle = .glass,
        accent: EatometerWidgetAccent = .app
    ) -> QuickMealWidgetEntry {
        QuickMealWidgetEntry(
            date: .now,
            calories: 1260,
            caloriesGoal: 2000,
            mealCategories: Array(Self.defaultCategories().prefix(Self.mealSlotLimit)),
            meals: [
                EatometerTodayMealSummary(
                    id: UUID().uuidString,
                    title: WidgetLocalization.string("widget.quick_meal.breakfast", defaultValue: "Breakfast", comment: "Breakfast fallback"),
                    categoryID: "breakfast",
                    categoryTitle: WidgetLocalization.string("widget.quick_meal.breakfast", defaultValue: "Breakfast", comment: "Breakfast fallback"),
                    calories: 430,
                    scheduledAt: .now
                ),
                EatometerTodayMealSummary(
                    id: UUID().uuidString,
                    title: WidgetLocalization.string("widget.quick_meal.lunch", defaultValue: "Lunch", comment: "Lunch fallback"),
                    categoryID: "lunch",
                    categoryTitle: WidgetLocalization.string("widget.quick_meal.lunch", defaultValue: "Lunch", comment: "Lunch fallback"),
                    calories: 610,
                    scheduledAt: .now
                )
            ],
            style: style,
            accent: accent
        )
    }


    private static func defaultCategories() -> [EatometerMealCategorySummary] {
        [
            EatometerMealCategorySummary(
                id: "breakfast",
                title: WidgetLocalization.string("widget.quick_meal.breakfast", defaultValue: "Breakfast", comment: "Breakfast fallback"),
                symbolName: "sunrise.fill"
            ),
            EatometerMealCategorySummary(
                id: "lunch",
                title: WidgetLocalization.string("widget.quick_meal.lunch", defaultValue: "Lunch", comment: "Lunch fallback"),
                symbolName: "sun.max.fill"
            ),
            EatometerMealCategorySummary(
                id: "dinner",
                title: WidgetLocalization.string("widget.quick_meal.dinner", defaultValue: "Dinner", comment: "Dinner fallback"),
                symbolName: "moon.stars.fill"
            ),
            EatometerMealCategorySummary(
                id: "snack",
                title: WidgetLocalization.string("widget.quick_meal.snack", defaultValue: "Snack", comment: "Snack fallback"),
                symbolName: "leaf.fill"
            )
        ]
    }

}

/// One meal: a ring with a plus in the middle, its name, and what has been
/// logged against it.
///
/// The plus is inside the ring rather than beside it because the ring is the
/// tap target — the whole column opens the diary at that meal, and a separate
/// button would be a second thing to aim at in a tile this size.
private struct QuickMealRingColumn: View {
    let title: String
    let consumed: Int
    let target: Int
    let tint: Color
    let secondaryText: Color
    let primaryText: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(Double(consumed) / Double(target), 0), 1)
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(secondaryText)
            }
            .frame(width: 54, height: 54)

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.3)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                // What has been eaten, not the target. The ring already draws
                // the target — it is the thing being filled — so repeating it
                // as the figure left the widget unable to say the one thing it
                // is for: how much has actually been logged.
                Text(verbatim: "\(consumed)")
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

private struct QuickMealWidgetView: View {
    let entry: QuickMealWidgetEntry
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var accentColor: Color { entry.accent.color }
    private var primaryText: Color { widgetPrimaryText(style: entry.style, isDark: isDark) }
    private var secondaryText: Color { widgetSecondaryText(style: entry.style, isDark: isDark) }

    private var visibleMealCategories: [EatometerMealCategorySummary] {
        Array(entry.mealCategories.prefix(QuickMealWidgetProvider.mealSlotLimit))
    }

    private var emptyStateText: String {
        WidgetLocalization.string(
            "widget.quick_meal.empty",
            defaultValue: "Add meals in the app to show them here.",
            comment: "Quick meal widget empty state"
        )
    }

    var body: some View {
        Group {
            if visibleMealCategories.isEmpty {
                Text(emptyStateText)
                    .font(.footnote)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(visibleMealCategories, id: \.id) { category in
                        Link(destination: mealURL(categoryID: category.id)) {
                            QuickMealRingColumn(
                                title: category.title,
                                consumed: category.calories,
                                target: category.targetCalories,
                                tint: accentColor,
                                secondaryText: secondaryText,
                                primaryText: primaryText
                            )
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .eatometerWidgetChrome(style: entry.style)
    }

    private func mealURL(categoryID: String) -> URL {
        var components = URLComponents()
        components.scheme = "eatometer"
        components.host = "diary"
        components.queryItems = [
            URLQueryItem(name: "meal_slot_id", value: categoryID)
        ]
        return components.url ?? URL(string: "eatometer://diary")!
    }
}

struct EatometerQuickMealWidget: Widget {
    static let kind: String = EatometerWidgetStore.quickMealWidgetKind

    private var displayNameText: String {
        WidgetLocalization.string(
            "widget.gallery.quick_meal.title",
            defaultValue: "Quick meal",
            comment: "Quick meal widget display name"
        )
    }

    private var descriptionText: String {
        WidgetLocalization.string(
            "widget.gallery.quick_meal.description",
            defaultValue: "Open meal slots and add favorites faster.",
            comment: "Quick meal widget gallery description"
        )
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: QuickMealWidgetConfigurationIntent.self, provider: QuickMealWidgetProvider()) { entry in
            QuickMealWidgetView(entry: entry)
        }
        .configurationDisplayName(displayNameText)
        .description(descriptionText)
        .supportedFamilies([.systemMedium])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}

private extension Color {
    init?(widgetHex: String) {
        var value = widgetHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let raw = UInt32(value, radix: 16) else { return nil }
        let red = Double((raw >> 16) & 0xFF) / 255.0
        let green = Double((raw >> 8) & 0xFF) / 255.0
        let blue = Double(raw & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}

struct NutritionWidgetEntry: TimelineEntry {
    let date: Date
    let calories: Int
    let protein: Int
    let fat: Int
    let carbs: Int
    let caloriesGoal: Int
    let proteinGoal: Int
    let fatGoal: Int
    let carbsGoal: Int
    let style: EatometerWidgetVisualStyle
    let accent: EatometerWidgetAccent
}

struct NutritionWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NutritionWidgetEntry {
        NutritionWidgetEntry(
            date: .now,
            calories: 1260,
            protein: 98,
            fat: 42,
            carbs: 134,
            caloriesGoal: 2000,
            proteinGoal: 150,
            fatGoal: 67,
            carbsGoal: 200,
            style: .glass,
            accent: .app
        )
    }

    func snapshot(for configuration: NutritionWidgetConfigurationIntent, in context: Context) async -> NutritionWidgetEntry {
        makeEntry(style: .glass, accent: .app)
    }

    func timeline(for configuration: NutritionWidgetConfigurationIntent, in context: Context) async -> Timeline<NutritionWidgetEntry> {
        let entry = makeEntry(style: .glass, accent: .app)
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    private func makeEntry(style: EatometerWidgetVisualStyle, accent: EatometerWidgetAccent) -> NutritionWidgetEntry {
        if let snapshot = EatometerWidgetStore.loadTodaySnapshot() {
            return NutritionWidgetEntry(
                date: .now,
                calories: snapshot.calories,
                protein: snapshot.protein,
                fat: snapshot.fat,
                carbs: snapshot.carbs,
                caloriesGoal: snapshot.caloriesGoal,
                proteinGoal: snapshot.proteinGoal,
                fatGoal: snapshot.fatGoal,
                carbsGoal: snapshot.carbsGoal,
                style: style,
                accent: accent
            )
        }

        return NutritionWidgetEntry(
            date: .now,
            calories: 0,
            protein: 0,
            fat: 0,
            carbs: 0,
            caloriesGoal: 2000,
            proteinGoal: 150,
            fatGoal: 67,
            carbsGoal: 200,
            style: style,
            accent: accent
        )
    }
}

/// One metric drawn as a ring: the arc, the name under it, the figure under
/// that in the ring's own colour.
///
/// Shared by the small and medium layouts, which differ only in how many of
/// these stand side by side.
private struct NutritionRingColumn: View {
    let title: String
    let value: Int
    let target: Int
    let tint: Color
    let diameter: CGFloat
    let lineWidth: CGFloat
    let titleSize: CGFloat
    let valueSize: CGFloat
    let secondaryText: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(Double(value) / Double(target), 0), 1)
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    // Twelve o'clock is where a ring is read from, and
                    // `trim` starts at three.
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: diameter, height: diameter)

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.3)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(verbatim: "\(value)")
                    .font(.system(size: valueSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

struct NutritionWidgetView: View {
    let entry: NutritionWidgetEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family

    private var isDark: Bool { colorScheme == .dark }
    private var secondaryText: Color { widgetSecondaryText(style: entry.style, isDark: isDark) }

    private var caloriesTitleText: String {
        WidgetLocalization.string("diary.calories", defaultValue: "Calories", comment: "Calories")
    }

    private var proteinTitleText: String {
        WidgetLocalization.string("diary.protein", defaultValue: "Protein", comment: "Protein")
    }

    private var fatTitleText: String {
        WidgetLocalization.string("diary.fat", defaultValue: "Fat", comment: "Fat")
    }

    private var carbsTitleText: String {
        WidgetLocalization.string("diary.carbs", defaultValue: "Carbs", comment: "Carbs")
    }

    /// How much of the calorie goal has been eaten, as a whole percent.
    ///
    /// The lock screen has room for one number and no colour to carry a second
    /// meaning, so the four metrics collapse to the one that answers "how is
    /// today going".
    private var caloriesPercent: Int {
        guard entry.caloriesGoal > 0 else { return 0 }
        return Int((Double(entry.calories) / Double(entry.caloriesGoal) * 100).rounded())
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            lockScreenRing
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }

    /// Small: calories alone.
    ///
    /// Four rings at this size would be four thirty-point circles with
    /// four-digit numbers under them. One ring the size of the tile says the
    /// same thing about the figure that matters most and can be read across a
    /// room.
    private var smallLayout: some View {
        NutritionRingColumn(
            title: caloriesTitleText,
            value: entry.calories,
            target: entry.caloriesGoal,
            tint: EatometerWidgetPalette.calories,
            diameter: 62,
            lineWidth: 9,
            titleSize: 10,
            valueSize: 19,
            secondaryText: secondaryText
        )
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .eatometerWidgetChrome(style: entry.style)
    }

    /// Medium: the full split, in the order it is quoted everywhere else —
    /// calories, protein, carbohydrates, fat.
    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 6) {
            NutritionRingColumn(
                title: caloriesTitleText, value: entry.calories, target: entry.caloriesGoal,
                tint: EatometerWidgetPalette.calories, diameter: 52, lineWidth: 8,
                titleSize: 9, valueSize: 17, secondaryText: secondaryText
            )
            .frame(maxWidth: .infinity)

            NutritionRingColumn(
                title: proteinTitleText, value: entry.protein, target: entry.proteinGoal,
                tint: EatometerWidgetPalette.protein, diameter: 52, lineWidth: 8,
                titleSize: 9, valueSize: 17, secondaryText: secondaryText
            )
            .frame(maxWidth: .infinity)

            NutritionRingColumn(
                title: carbsTitleText, value: entry.carbs, target: entry.carbsGoal,
                tint: EatometerWidgetPalette.carbs, diameter: 52, lineWidth: 8,
                titleSize: 9, valueSize: 17, secondaryText: secondaryText
            )
            .frame(maxWidth: .infinity)

            NutritionRingColumn(
                title: fatTitleText, value: entry.fat, target: entry.fatGoal,
                tint: EatometerWidgetPalette.fat, diameter: 52, lineWidth: 8,
                titleSize: 9, valueSize: 17, secondaryText: secondaryText
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .eatometerWidgetChrome(style: entry.style)
    }

    /// Lock screen: one ring and a percentage, no colour and no chrome.
    ///
    /// The accessory families are rendered as a stencil — every colour is
    /// replaced by the system's tint — so anything that relied on colour to
    /// tell metrics apart would arrive as four identical grey rings. It also
    /// must not carry a background of its own; `containerBackground` is what
    /// the system fills in, and drawing a card here would be a grey box on the
    /// wallpaper.
    private var lockScreenRing: some View {
        ZStack {
            AccessoryWidgetBackground()

            Circle()
                .stroke(Color.primary.opacity(0.25), lineWidth: 5)

            Circle()
                .trim(from: 0, to: min(max(Double(caloriesPercent) / 100, 0), 1))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: -1) {
                Text(verbatim: "\(caloriesPercent)")
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                Text(verbatim: "%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(2)
        .widgetAccentable()
    }
}

struct EatometerNutritionWidget: Widget {
    static let kind: String = EatometerWidgetStore.nutritionWidgetKind

    private var displayNameText: String {
        WidgetLocalization.string(
            "today.stats.summary.title",
            defaultValue: "Summary",
            comment: "Nutrition widget display name"
        )
    }

    private var descriptionText: String {
        WidgetLocalization.string(
            "widget.gallery.nutrition.description",
            defaultValue: "Calories and macros for the current day.",
            comment: "Nutrition widget gallery description"
        )
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: NutritionWidgetConfigurationIntent.self, provider: NutritionWidgetProvider()) { entry in
            NutritionWidgetView(entry: entry)
        }
        .configurationDisplayName(displayNameText)
        .description(descriptionText)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}


#Preview(as: .systemSmall) {
    EatometerWidget()
} timeline: {
    WaterWidgetEntry(date: .now, intakeMilliliters: 750, goalMilliliters: 2000, adjustmentMilliliters: 200, style: .soft, accent: .blue)
}

#Preview("Quick Meal Medium", as: .systemMedium) {
    EatometerQuickMealWidget()
} timeline: {
    QuickMealWidgetEntry(
        date: .now,
        calories: 1380,
        caloriesGoal: 2000,
        mealCategories: [
            EatometerMealCategorySummary(id: "breakfast", title: "Завтрак", symbolName: "sunrise.fill", targetCalories: 450, calories: 320),
            EatometerMealCategorySummary(id: "lunch", title: "Обед", symbolName: "sun.max.fill", targetCalories: 450, calories: 450),
            EatometerMealCategorySummary(id: "dinner", title: "Ужин", symbolName: "moon.stars.fill", targetCalories: 450, calories: 0)
        ],
        meals: [],
        style: .soft,
        accent: .app
    )
}

#Preview("Nutrition", as: .systemSmall) {
    EatometerNutritionWidget()
} timeline: {
    NutritionWidgetEntry(
        date: .now,
        calories: 1380,
        protein: 105,
        fat: 48,
        carbs: 132,
        caloriesGoal: 2000,
        proteinGoal: 150,
        fatGoal: 67,
        carbsGoal: 200,
        style: .soft,
        accent: .app
    )
}

#Preview("Nutrition Medium", as: .systemMedium) {
    EatometerNutritionWidget()
} timeline: {
    NutritionWidgetEntry(
        date: .now,
        calories: 1200, protein: 50, fat: 30, carbs: 120,
        caloriesGoal: 2000, proteinGoal: 150, fatGoal: 67, carbsGoal: 200,
        style: .soft, accent: .app
    )
}

#Preview("Nutrition Lock Screen", as: .accessoryCircular) {
    EatometerNutritionWidget()
} timeline: {
    NutritionWidgetEntry(
        date: .now,
        calories: 1320, protein: 50, fat: 30, carbs: 120,
        caloriesGoal: 2000, proteinGoal: 150, fatGoal: 67, carbsGoal: 200,
        style: .soft, accent: .app
    )
}
