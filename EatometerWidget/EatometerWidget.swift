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

private func widgetPrimaryText(style: EatometerWidgetVisualStyle, isDark: Bool) -> Color {
    switch style {
    case .device:
        return .primary
    case .transparent:
        return isDark ? .white : Color(red: 0.09, green: 0.09, blue: 0.10)
    case .glass:
        return isDark ? .white.opacity(0.94) : Color(red: 0.08, green: 0.08, blue: 0.09)
    case .soft:
        return .primary
    }
}

private func widgetSecondaryText(style: EatometerWidgetVisualStyle, isDark: Bool) -> Color {
    switch style {
    case .device:
        return .secondary
    case .transparent:
        return isDark ? .white.opacity(0.76) : Color.black.opacity(0.58)
    case .glass:
        return isDark ? .white.opacity(0.68) : Color.black.opacity(0.54)
    case .soft:
        return .secondary
    }
}

private struct EatometerWidgetChromeModifier: ViewModifier {
    let style: EatometerWidgetVisualStyle
    let accent: Color
    let isDark: Bool

    func body(content: Content) -> some View {
        content
            .background(backgroundView)
            .containerBackground(for: .widget) {
                backgroundView
            }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .device:
            glassBackground
        case .soft:
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.04, green: 0.05, blue: 0.07)]
                    : [accent.opacity(0.11), Color(red: 0.99, green: 0.99, blue: 0.97)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .glass:
            glassBackground
        case .transparent:
            Color.clear
        }
    }

    private var glassBackground: some View {
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.13, green: 0.14, blue: 0.17), Color(red: 0.05, green: 0.06, blue: 0.08)]
                    : [Color.white.opacity(0.96), Color(red: 0.96, green: 0.97, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: isDark
                    ? [Color.white.opacity(0.13), accent.opacity(0.10)]
                    : [Color.white.opacity(0.80), accent.opacity(0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            accent.opacity(isDark ? 0.07 : 0.05)
        }
    }
}

private extension View {
    func eatometerWidgetChrome(style: EatometerWidgetVisualStyle, accent: Color, isDark: Bool) -> some View {
        modifier(EatometerWidgetChromeModifier(style: style, accent: accent, isDark: isDark))
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

private func waterSurfaceY(in rect: CGRect, level: CGFloat) -> CGFloat {
    let clampedLevel = max(0, min(1, level))
    return rect.maxY - rect.height * clampedLevel
}

private struct WaterSurfaceShape: Shape {
    let level: CGFloat

    func path(in rect: CGRect) -> Path {
        guard level > 0.001 else { return Path() }

        var path = Path()
        let surfaceY = waterSurfaceY(in: rect, level: level)
        path.move(to: CGPoint(x: rect.minX, y: surfaceY))
        path.addLine(to: CGPoint(x: rect.maxX, y: surfaceY))
        return path
    }
}

private struct WaterFillShape: Shape {
    let level: CGFloat

    func path(in rect: CGRect) -> Path {
        guard level > 0.001 else { return Path() }

        var path = Path()
        let surfaceY = waterSurfaceY(in: rect, level: level)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: surfaceY))
        path.addLine(to: CGPoint(x: rect.maxX, y: surfaceY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct WaterWidgetView: View {
    let entry: WaterWidgetEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family

    private var isDark: Bool { colorScheme == .dark }
    private var accentColor: Color { entry.accent.color }
    private var primaryText: Color { widgetPrimaryText(style: entry.style, isDark: isDark) }
    private var secondaryText: Color { widgetSecondaryText(style: entry.style, isDark: isDark) }

    private let waterDeepLink = URL(string: "eatometer://water")

    private var titleText: String {
        WidgetLocalization.string(
            "water.title",
            defaultValue: "Water",
            comment: "Water widget title"
        )
    }

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

    private var rawProgressRatio: Double {
        guard entry.goalMilliliters > 0 else { return 0 }
        return max(0, Double(entry.intakeMilliliters) / Double(entry.goalMilliliters))
    }

    private var progressRatio: Double {
        min(1, rawProgressRatio)
    }

    private var fixedWaterStepText: String {
        String.localizedStringWithFormat(
            WidgetLocalization.string(
                "widget.water.fixed_step",
                defaultValue: "+%d ml",
                comment: "Fixed water widget step"
            ),
            50
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                WaterFillShape(level: progressRatio)
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [
                                    accentColor.opacity(entry.style == .transparent ? 0.34 : 0.62),
                                    accentColor.opacity(entry.style == .transparent ? 0.48 : 0.82)
                                ]
                                : [
                                    accentColor.opacity(entry.style == .transparent ? 0.24 : 0.42),
                                    accentColor.opacity(entry.style == .transparent ? 0.36 : 0.70)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .animation(.easeInOut(duration: 0.5), value: progressRatio)

                if rawProgressRatio > 1 {
                    WaterFillShape(level: 1)
                        .fill(accentColor.opacity(isDark ? 0.18 : 0.12))
                }

                WaterSurfaceShape(level: progressRatio)
                    .stroke(
                        Color.white.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 0.2)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 10) {
                    Text(titleText)
                        .font(.headline)
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(progressText)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(primaryText)

                    Spacer(minLength: 0)

                    waterControls
                }
                .padding(12)
            }
            .clipShape(ContainerRelativeShape())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .eatometerWidgetChrome(style: entry.style, accent: accentColor, isDark: isDark)
        .widgetURL(waterDeepLink)
    }

    private var waterControls: some View {
        HStack(spacing: 7) {
            waterControlButton(systemImage: "plus", label: nil, delta: entry.adjustmentMilliliters)
            waterControlButton(systemImage: nil, label: fixedWaterStepText, delta: 50)
            waterControlButton(systemImage: "minus", label: nil, delta: -entry.adjustmentMilliliters)
                .disabled(entry.intakeMilliliters <= 0)
                .opacity(entry.intakeMilliliters <= 0 ? 0.42 : 1)
        }
    }

    private func waterControlButton(systemImage: String?, label: String?, delta: Int) -> some View {
        Button(intent: AdjustWaterIntakeIntent(delta: delta)) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Text(label ?? "")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(primaryText)
            .frame(maxWidth: .infinity, minHeight: family == .systemSmall ? 30 : 38)
            .background(
                Capsule()
                    .fill(entry.style == .transparent ? accentColor.opacity(isDark ? 0.18 : 0.14) : Color.white.opacity(isDark ? 0.14 : 0.90))
            )
            .overlay(
                Capsule()
                    .stroke(accentColor.opacity(isDark ? 0.24 : 0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            WaterWidgetContainerView(entry: entry)
        }
        .configurationDisplayName(displayNameText)
        .description(descriptionText)
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}

private struct WaterWidgetContainerView: View {
    let entry: WaterWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemMedium {
            WaterGlassWidgetView(entry: entry)
        } else {
            WaterWidgetView(entry: entry)
        }
    }
}

private struct WaterGlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        let glassRect = rect.insetBy(dx: rect.width * 0.18, dy: 2)
        return Path(
            roundedRect: glassRect,
            cornerRadius: min(glassRect.width * 0.22, 12),
            style: .continuous
        )
    }
}

private struct WaterGlassView: View {
    let progressRatio: Double
    let isDark: Bool

    private var level: CGFloat {
        CGFloat(min(max(progressRatio, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let glassHeight = max(0, size.height - 4)
            let fillHeight = max(0, glassHeight * level)

            ZStack(alignment: .bottom) {
                WaterGlassShape()
                    .fill(isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.5))

                Rectangle()
                    .fill(isDark ? Color(red: 0.16, green: 0.55, blue: 0.92) : Color(red: 0.33, green: 0.75, blue: 1.0))
                    .frame(height: fillHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .mask(WaterGlassShape())
                    .animation(.easeInOut(duration: 0.45), value: level)

                WaterGlassShape()
                    .stroke(isDark ? Color.white.opacity(0.4) : Color.blue.opacity(0.3), lineWidth: 2)
            }
        }
    }
}

struct WaterGlassWidgetView: View {
    let entry: WaterWidgetEntry
    @Environment(\.colorScheme) private var colorScheme

    private let waterDeepLink = URL(string: "eatometer://water")

    private var isDark: Bool { colorScheme == .dark }
    private var accentColor: Color { entry.accent.color }
    private var primaryText: Color { widgetPrimaryText(style: entry.style, isDark: isDark) }
    private var secondaryText: Color { widgetSecondaryText(style: entry.style, isDark: isDark) }

    private var titleText: String {
        WidgetLocalization.string(
            "water.title",
            defaultValue: "Water",
            comment: "Water glass widget title"
        )
    }

    private var progressText: String {
        String.localizedStringWithFormat(
            WidgetLocalization.string(
                "water.subtitle",
                defaultValue: "%d / %d ml",
                comment: "Water glass widget progress"
            ),
            entry.intakeMilliliters,
            entry.goalMilliliters
        )
    }

    private var progressRatio: Double {
        guard entry.goalMilliliters > 0 else { return 0 }
        return min(max(Double(entry.intakeMilliliters) / Double(entry.goalMilliliters), 0), 1)
    }

    private var fixedWaterStepText: String {
        String.localizedStringWithFormat(
            WidgetLocalization.string(
                "widget.water.fixed_step",
                defaultValue: "+%d ml",
                comment: "Fixed water widget step"
            ),
            50
        )
    }

    var body: some View {
        HStack(spacing: 14) {
            WaterGlassView(progressRatio: progressRatio, isDark: isDark)
                .frame(width: 78, height: 116)

            VStack(alignment: .leading, spacing: 8) {
                Text(titleText)
                    .font(.headline)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.trailing, 30)

                Text(progressText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    waterControlButton(systemImage: "plus", label: nil, delta: entry.adjustmentMilliliters)
                    waterControlButton(systemImage: nil, label: fixedWaterStepText, delta: 50)
                    waterControlButton(systemImage: "minus", label: nil, delta: -entry.adjustmentMilliliters)
                        .disabled(entry.intakeMilliliters <= 0)
                        .opacity(entry.intakeMilliliters <= 0 ? 0.42 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .eatometerWidgetChrome(style: entry.style, accent: accentColor, isDark: isDark)
        .widgetURL(waterDeepLink)
    }

    private func waterControlButton(systemImage: String?, label: String?, delta: Int) -> some View {
        Button(intent: AdjustWaterIntakeIntent(delta: delta)) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .bold))
                } else {
                    Text(label ?? "")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
            }
            .foregroundStyle(primaryText)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                Capsule()
                    .fill(entry.style == .transparent ? accentColor.opacity(isDark ? 0.18 : 0.14) : Color.white.opacity(isDark ? 0.13 : 0.92))
            )
            .overlay(
                Capsule()
                    .stroke(accentColor.opacity(isDark ? 0.24 : 0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickMealWidgetItem: Identifiable, Hashable {
    enum Kind: String {
        case product
        case recipe
        case mealTemplate = "meal_template"
    }

    let itemID: String
    let title: String
    let subtitle: String
    let calories: Int
    let kind: Kind

    var id: String { "\(kind.rawValue)-\(itemID)" }
}

private struct QuickMealWidgetEntry: TimelineEntry {
    let date: Date
    let calories: Int
    let caloriesGoal: Int
    let mealCategories: [EatometerMealCategorySummary]
    let meals: [EatometerTodayMealSummary]
    let quickItems: [QuickMealWidgetItem]
    let style: EatometerWidgetVisualStyle
    let accent: EatometerWidgetAccent
}

private struct QuickMealWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickMealWidgetEntry {
        makePlaceholderEntry()
    }

    func snapshot(for configuration: QuickMealWidgetConfigurationIntent, in context: Context) async -> QuickMealWidgetEntry {
        makeEntry(
            for: configuration.quickAddSource ?? .mixed,
            mealSlotLimit: configuration.mealSlotLimit ?? .four,
            style: .glass,
            accent: .app
        )
    }

    func timeline(for configuration: QuickMealWidgetConfigurationIntent, in context: Context) async -> Timeline<QuickMealWidgetEntry> {
        let entry = makeEntry(
            for: configuration.quickAddSource ?? .mixed,
            mealSlotLimit: configuration.mealSlotLimit ?? .four,
            style: .glass,
            accent: .app
        )
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    private func makeEntry(
        for source: QuickMealQuickAddSource,
        mealSlotLimit: QuickMealMealSlotLimit,
        style: EatometerWidgetVisualStyle,
        accent: EatometerWidgetAccent
    ) -> QuickMealWidgetEntry {
        guard let snapshot = EatometerWidgetStore.loadTodaySnapshot() else {
            return makePlaceholderEntry(source: source, mealSlotLimit: mealSlotLimit, style: style, accent: accent)
        }

        let categories = snapshot.mealCategories.isEmpty ? Self.defaultCategories() : snapshot.mealCategories
        let quickItems = Self.quickItems(from: snapshot, source: source)
        return QuickMealWidgetEntry(
            date: .now,
            calories: snapshot.calories,
            caloriesGoal: snapshot.caloriesGoal,
            mealCategories: Array(categories.prefix(mealSlotLimit.count)),
            meals: snapshot.meals,
            quickItems: Array(quickItems.prefix(8)),
            style: style,
            accent: accent
        )
    }

    private func makePlaceholderEntry(
        source: QuickMealQuickAddSource = .mixed,
        mealSlotLimit: QuickMealMealSlotLimit = .four,
        style: EatometerWidgetVisualStyle = .glass,
        accent: EatometerWidgetAccent = .app
    ) -> QuickMealWidgetEntry {
        let placeholderItems = Self.placeholderQuickItems(for: source)

        return QuickMealWidgetEntry(
            date: .now,
            calories: 1260,
            caloriesGoal: 2000,
            mealCategories: Array(Self.defaultCategories().prefix(mealSlotLimit.count)),
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
            quickItems: placeholderItems,
            style: style,
            accent: accent
        )
    }

    private static func placeholderQuickItems(for source: QuickMealQuickAddSource) -> [QuickMealWidgetItem] {
        switch source {
        case .mixed:
            return [
                QuickMealWidgetItem(
                    itemID: UUID().uuidString,
                    title: WidgetLocalization.string("widget.quick_meal.placeholder.product", defaultValue: "Favorite product", comment: "Quick meal placeholder product"),
                    subtitle: "180 kcal",
                    calories: 180,
                    kind: .product
                ),
                QuickMealWidgetItem(
                    itemID: UUID().uuidString,
                    title: WidgetLocalization.string("widget.quick_meal.placeholder.template", defaultValue: "Meal template", comment: "Quick meal placeholder template"),
                    subtitle: "520 kcal",
                    calories: 520,
                    kind: .mealTemplate
                )
            ]
        case .products:
            return [
                QuickMealWidgetItem(
                    itemID: UUID().uuidString,
                    title: WidgetLocalization.string("widget.quick_meal.placeholder.product", defaultValue: "Favorite product", comment: "Quick meal placeholder product"),
                    subtitle: "180 kcal",
                    calories: 180,
                    kind: .product
                )
            ]
        case .recipes:
            return [
                QuickMealWidgetItem(
                    itemID: UUID().uuidString,
                    title: WidgetLocalization.string("widget.quick_meal.placeholder.recipe", defaultValue: "Recipe", comment: "Quick meal placeholder recipe"),
                    subtitle: "320 kcal",
                    calories: 320,
                    kind: .recipe
                )
            ]
        case .mealTemplates:
            return [
                QuickMealWidgetItem(
                    itemID: UUID().uuidString,
                    title: WidgetLocalization.string("widget.quick_meal.placeholder.template", defaultValue: "Meal template", comment: "Quick meal placeholder template"),
                    subtitle: "520 kcal",
                    calories: 520,
                    kind: .mealTemplate
                )
            ]
        }
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

    private static func quickItems(from snapshot: EatometerTodaySnapshot, source: QuickMealQuickAddSource) -> [QuickMealWidgetItem] {
        let favorites = snapshot.favoriteProducts.map {
            QuickMealWidgetItem(itemID: $0.id, title: $0.title, subtitle: $0.subtitle, calories: $0.calories, kind: .product)
        }
        let templates = snapshot.mealTemplates.map {
            QuickMealWidgetItem(itemID: $0.id, title: $0.title, subtitle: $0.subtitle, calories: $0.calories, kind: .mealTemplate)
        }
        let recipes = snapshot.recipes.map {
            QuickMealWidgetItem(itemID: $0.id, title: $0.title, subtitle: $0.subtitle, calories: $0.calories, kind: .recipe)
        }

        switch source {
        case .mixed:
            return favorites + templates + recipes
        case .products:
            return favorites
        case .recipes:
            return recipes
        case .mealTemplates:
            return templates
        }
    }
}

private struct QuickMealWidgetView: View {
    let entry: QuickMealWidgetEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family

    private var isDark: Bool { colorScheme == .dark }
    private var accentColor: Color { entry.accent.color }
    private var primaryText: Color { widgetPrimaryText(style: entry.style, isDark: isDark) }
    private var secondaryText: Color { widgetSecondaryText(style: entry.style, isDark: isDark) }

    private var titleText: String {
        WidgetLocalization.string(
            "widget.gallery.quick_meal.title",
            defaultValue: "Quick meal",
            comment: "Quick meal widget title"
        )
    }

    private var mealsTitleText: String {
        WidgetLocalization.string(
            "widget.quick_meal.meals",
            defaultValue: "Meals",
            comment: "Quick meal widget meals section"
        )
    }

    private var quickAddTitleText: String {
        WidgetLocalization.string(
            "widget.quick_meal.quick_add",
            defaultValue: "Quick add",
            comment: "Quick meal widget quick add section"
        )
    }

    private var emptyText: String {
        WidgetLocalization.string(
            "widget.quick_meal.empty",
            defaultValue: "Add favorites in the app to show them here.",
            comment: "Quick meal widget empty state"
        )
    }

    private var visibleMealCategories: [EatometerMealCategorySummary] {
        Array(entry.mealCategories.prefix(6))
    }

    private var usesCompactMealGrid: Bool {
        visibleMealCategories.count > 4
    }

    private var mealCategoryColumns: [GridItem] {
        let spacing: CGFloat = usesCompactMealGrid ? 6 : 8
        let columnCount = usesCompactMealGrid ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }

    private var visibleQuickItemLimit: Int {
        usesCompactMealGrid ? 2 : 3
    }

    private var mealChoiceButtonSize: CGFloat {
        usesCompactMealGrid ? 21 : 24
    }

    private var mealChoiceButtonSpacing: CGFloat {
        usesCompactMealGrid ? 3 : 5
    }

    private var quickTileFill: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.065)
    }

    private var quickRowFill: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.055)
    }

    private var quickTileStroke: Color {
        isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.11)
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumBody
            } else {
                largeBody
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .eatometerWidgetChrome(style: entry.style, accent: accentColor, isDark: isDark)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titleText)
                .font(.headline.weight(.bold))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .padding(.trailing, 30)

            LazyVGrid(columns: mealCategoryColumns, spacing: usesCompactMealGrid ? 6 : 8) {
                ForEach(visibleMealCategories, id: \.id) { category in
                    Link(destination: mealURL(categoryID: category.id)) {
                        mediumMealTile(category: category)
                    }
                }
            }
        }
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(titleText)
                .font(.headline.weight(.bold))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 30)

            Text(mealsTitleText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(secondaryText)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            LazyVGrid(columns: mealCategoryColumns, spacing: usesCompactMealGrid ? 6 : 8) {
                ForEach(visibleMealCategories, id: \.id) { category in
                    Link(destination: mealURL(categoryID: category.id)) {
                        mealTile(category: category)
                    }
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            HStack {
                Text(quickAddTitleText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(secondaryText)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
                    .allowsTightening(true)
                Spacer(minLength: 0)
            }

            if entry.quickItems.isEmpty {
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            } else {
                VStack(spacing: 7) {
                    ForEach(Array(entry.quickItems.prefix(visibleQuickItemLimit))) { item in
                        quickAddRow(item)
                    }
                }
            }
        }
    }

    private func mediumMealTile(category: EatometerMealCategorySummary) -> some View {
        HStack(spacing: usesCompactMealGrid ? 6 : 8) {
            Image(systemName: category.symbolName)
                .font(.system(size: usesCompactMealGrid ? 12 : 14, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: usesCompactMealGrid ? 18 : 22, height: usesCompactMealGrid ? 18 : 22)

            Text(category.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: usesCompactMealGrid ? 38 : 42, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(quickTileFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(quickTileStroke, lineWidth: 1)
        )
    }

    private func mealTile(category: EatometerMealCategorySummary) -> some View {
        HStack(spacing: usesCompactMealGrid ? 6 : 8) {
            Image(systemName: category.symbolName)
                .font(.system(size: usesCompactMealGrid ? 12 : 14, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: usesCompactMealGrid ? 18 : 22, height: usesCompactMealGrid ? 18 : 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(categoryCaloriesText(categoryID: category.id))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, usesCompactMealGrid ? 7 : 9)
        .frame(maxWidth: .infinity, minHeight: usesCompactMealGrid ? 42 : 48, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(quickTileFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(quickTileStroke, lineWidth: 1)
        )
    }

    private func quickAddRow(_ item: QuickMealWidgetItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: quickItemIcon(for: item.kind))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(quickItemTint(for: item.kind))
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(quickItemSubtitle(item))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: mealChoiceButtonSpacing) {
                ForEach(visibleMealCategories, id: \.id) { category in
                    Link(destination: quickAddURL(for: item, categoryID: category.id)) {
                        mealChoiceButton(category: category)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 43, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(quickRowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(quickTileStroke, lineWidth: 1)
        )
    }

    private func mealChoiceButton(category: EatometerMealCategorySummary) -> some View {
        Image(systemName: category.symbolName)
            .font(.system(size: usesCompactMealGrid ? 9 : 10, weight: .bold))
            .foregroundStyle(isDark ? Color.white.opacity(0.90) : accentColor)
            .frame(width: mealChoiceButtonSize, height: mealChoiceButtonSize)
            .background(
                Circle()
                    .fill(isDark ? Color.white.opacity(0.12) : accentColor.opacity(0.17))
            )
            .overlay(
                Circle()
                    .stroke(isDark ? Color.white.opacity(0.12) : accentColor.opacity(0.25), lineWidth: 1)
            )
    }

    private func categoryCaloriesText(categoryID: String) -> String {
        let calories = entry.meals
            .filter { $0.categoryID == categoryID }
            .reduce(0) { $0 + $1.calories }
        return String.localizedStringWithFormat(
            WidgetLocalization.string("today.kcal_value", defaultValue: "%d kcal", comment: "Quick meal category calories"),
            calories
        )
    }

    private func quickItemSubtitle(_ item: QuickMealWidgetItem) -> String {
        if item.calories > 0 {
            return String.localizedStringWithFormat(
                WidgetLocalization.string("today.kcal_value", defaultValue: "%d kcal", comment: "Quick meal item calories"),
                item.calories
            )
        }
        return item.subtitle
    }

    private func quickItemIcon(for kind: QuickMealWidgetItem.Kind) -> String {
        switch kind {
        case .product:
            return "carrot.fill"
        case .recipe:
            return "book.closed.fill"
        case .mealTemplate:
            return "square.stack.3d.up.fill"
        }
    }

    private func quickItemTint(for kind: QuickMealWidgetItem.Kind) -> Color {
        switch kind {
        case .product:
            return .green
        case .recipe:
            return .orange
        case .mealTemplate:
            return .blue
        }
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

    private func quickAddURL(for item: QuickMealWidgetItem, categoryID: String) -> URL {
        var components = URLComponents()
        components.scheme = "eatometer"
        components.host = "diary"
        components.queryItems = [
            URLQueryItem(name: "meal_slot_id", value: categoryID),
            URLQueryItem(name: "quick_add_type", value: item.kind.rawValue),
            URLQueryItem(name: "quick_add_id", value: item.itemID)
        ]
        return components.url ?? mealURL(categoryID: categoryID)
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
        .supportedFamilies([.systemMedium, .systemLarge])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}

private struct HabitWidgetEntry: TimelineEntry {
    let date: Date
    let habit: EatometerHabitWidgetHabit?
    let style: EatometerWidgetVisualStyle
    let accent: EatometerWidgetAccent
}

private struct HabitWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitWidgetEntry {
        HabitWidgetEntry(
            date: .now,
            habit: EatometerHabitWidgetHabit(
                id: UUID().uuidString,
                name: WidgetLocalization.string("widget.habit.placeholder.name", defaultValue: "No sugar", comment: "Habit widget placeholder"),
                icon: "leaf.fill",
                colorHex: "#34C759",
                kind: "quit",
                trackingMode: "manual",
                targetDays: 30,
                attemptID: UUID().uuidString,
                attemptStartedAt: Calendar.current.date(byAdding: .day, value: -7, to: .now),
                attemptEndedAt: nil,
                checkInCount: 6,
                checkedDayKeys: []
            ),
            style: .glass,
            accent: .app
        )
    }

    func snapshot(for configuration: HabitWidgetConfigurationIntent, in context: Context) async -> HabitWidgetEntry {
        makeEntry(
            for: configuration.habit?.id,
            style: .glass,
            accent: .app
        )
    }

    func timeline(for configuration: HabitWidgetConfigurationIntent, in context: Context) async -> Timeline<HabitWidgetEntry> {
        let entry = makeEntry(
            for: configuration.habit?.id,
            style: .glass,
            accent: .app
        )
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    private func makeEntry(
        for selectedHabitID: String?,
        style: EatometerWidgetVisualStyle,
        accent: EatometerWidgetAccent
    ) -> HabitWidgetEntry {
        let habits = EatometerWidgetStore.loadHabitSnapshot()?.habits ?? []
        let normalizedSelectedID = selectedHabitID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = normalizedSelectedID.flatMap { selectedID in
            selectedID.isEmpty ? nil : habits.first(where: { $0.id == selectedID })
        }
        return HabitWidgetEntry(date: .now, habit: selected, style: style, accent: accent)
    }
}

private struct HabitWidgetView: View {
    let entry: HabitWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var primaryText: Color { widgetPrimaryText(style: entry.style, isDark: isDark) }
    private var secondaryText: Color { widgetSecondaryText(style: entry.style, isDark: isDark) }

    private var accent: Color {
        if entry.accent == .app {
            return Color(widgetHex: entry.habit?.colorHex ?? "#34C759") ?? .green
        }
        return entry.accent.color
    }

    private var habitURL: URL? {
        guard let habit = entry.habit else { return URL(string: "eatometer://habits") }
        var components = URLComponents()
        components.scheme = "eatometer"
        components.host = "habits"
        components.queryItems = [URLQueryItem(name: "habit_id", value: habit.id)]
        return components.url
    }

    var body: some View {
        Group {
            if let habit = entry.habit {
                content(for: habit)
            } else {
                emptyState
            }
        }
        .padding(family == .systemSmall ? 13 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .eatometerWidgetChrome(style: entry.style, accent: accent, isDark: isDark)
        .widgetURL(habitURL)
    }

    @ViewBuilder
    private func content(for habit: EatometerHabitWidgetHabit) -> some View {
        let mark = markStagePayload(for: habit)
        let stageSummary = stageText(for: habit, compact: family == .systemSmall)

        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: habit.icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(accent))

                    Spacer(minLength: 0)
                }
                .padding(.trailing, 34)

                    Text(habit.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(elapsedTitleText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(secondaryText)
                            .textCase(.uppercase)
                            .lineLimit(1)

                        Text(elapsedText(for: habit))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)

                        if let stageSummary {
                            Text(stageSummary)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let mark {
                        markStageButton(for: habit, mark: mark)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: habit.icon)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(accent))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(habit.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.62)
                            .allowsTightening(true)

                        Text(modeText(for: habit))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)

                    if let mark {
                        markStageButton(for: habit, mark: mark)
                            .padding(.top, 4)
                    }
                }
                .frame(minHeight: 42, alignment: .top)
                .padding(.trailing, 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(elapsedTitleText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(secondaryText)
                        .textCase(.uppercase)
                        .lineLimit(1)

                    Text(elapsedText(for: habit))
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }

                progressBar(for: habit)

                if let stageSummary {
                    Text(stageSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func markStageButton(for habit: EatometerHabitWidgetHabit, mark: (attemptID: String, dayKey: String)) -> some View {
        Button(intent: MarkHabitStageIntent(habitID: habit.id, attemptID: mark.attemptID, dayKey: mark.dayKey)) {
            Image(systemName: "checkmark")
                .font(.system(size: family == .systemSmall ? 12 : 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: family == .systemSmall ? 28 : 30, height: family == .systemSmall ? 28 : 30)
                .background(Circle().fill(accent))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(markStageText))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.green))

            Text(emptyTitleText)
                .font(.headline.weight(.bold))
                .foregroundStyle(primaryText)
                .lineLimit(2)

            Text(emptySubtitleText)
                .font(.caption)
                .foregroundStyle(secondaryText)
                .lineLimit(3)
        }
    }

    private func progressBar(for habit: EatometerHabitWidgetHabit) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(isDark ? 0.16 : 0.10))
                Capsule()
                    .fill(accent)
                    .frame(width: proxy.size.width * progressRatio(for: habit))
            }
        }
        .frame(height: 7)
    }

    private func progressRatio(for habit: EatometerHabitWidgetHabit) -> CGFloat {
        guard let targetDays = habit.targetDays, targetDays > 0 else { return min(1, CGFloat(elapsedDays(for: habit)) / 30) }
        return min(1, CGFloat(elapsedDays(for: habit)) / CGFloat(targetDays))
    }

    private func elapsedDays(for habit: EatometerHabitWidgetHabit) -> Int {
        guard let startedAt = habit.attemptStartedAt else { return 0 }
        return max(0, Int(entry.date.timeIntervalSince(startedAt) / 86_400))
    }

    private func elapsedText(for habit: EatometerHabitWidgetHabit) -> String {
        guard let startedAt = habit.attemptStartedAt else { return noAttemptText }
        let elapsed = max(0, entry.date.timeIntervalSince(startedAt))
        let days = Int(elapsed / 86_400)
        if days > 0 {
            return String.localizedStringWithFormat(durationDaysFormat, days)
        }
        let hours = Int(elapsed / 3_600)
        if hours > 0 {
            return String.localizedStringWithFormat(durationHoursFormat, hours)
        }
        let minutes = max(1, Int(elapsed / 60))
        return String.localizedStringWithFormat(durationMinutesFormat, minutes)
    }

    private func stageText(for habit: EatometerHabitWidgetHabit, compact: Bool) -> String? {
        if let targetDays = habit.targetDays, targetDays > 0 {
            if compact {
                return String(format: "%d/%d", elapsedDays(for: habit), targetDays)
            }
            return String.localizedStringWithFormat(progressFormat, elapsedDays(for: habit), targetDays)
        }
        guard habit.trackingMode == "manual", habit.checkInCount > 0 else { return nil }
        if compact {
            return String(format: "%d", habit.checkInCount)
        }
        return String.localizedStringWithFormat(checkInsFormat, habit.checkInCount)
    }

    private func modeText(for habit: EatometerHabitWidgetHabit) -> String {
        habit.trackingMode == "manual" ? manualModeText : automaticModeText
    }

    private func markStagePayload(for habit: EatometerHabitWidgetHabit) -> (attemptID: String, dayKey: String)? {
        guard habit.trackingMode == "manual",
              let attemptID = habit.attemptID,
              let dayKey = EatometerWidgetStore.currentManualHabitStageDayKey(for: habit, at: entry.date),
              !habit.checkedDayKeys.contains(dayKey) else {
            return nil
        }
        return (attemptID, dayKey)
    }

    private var elapsedTitleText: String {
        WidgetLocalization.string("widget.habit.elapsed", defaultValue: "Elapsed", comment: "Habit widget elapsed label")
    }

    private var markStageText: String {
        WidgetLocalization.string("widget.habit.mark_stage", defaultValue: "Mark stage", comment: "Habit widget mark stage button")
    }

    private var emptyTitleText: String {
        WidgetLocalization.string("widget.habit.empty.title", defaultValue: "Choose a habit", comment: "Habit widget empty title")
    }

    private var emptySubtitleText: String {
        WidgetLocalization.string("widget.habit.empty.subtitle", defaultValue: "Edit the widget and select an active habit.", comment: "Habit widget empty subtitle")
    }

    private var manualModeText: String {
        WidgetLocalization.string("widget.habit.mode.manual", defaultValue: "Manual", comment: "Habit widget manual mode")
    }

    private var automaticModeText: String {
        WidgetLocalization.string("widget.habit.mode.automatic", defaultValue: "Automatic", comment: "Habit widget automatic mode")
    }

    private var noAttemptText: String {
        WidgetLocalization.string("widget.habit.no_attempt", defaultValue: "No active run", comment: "Habit widget no attempt")
    }

    private var durationDaysFormat: String {
        WidgetLocalization.string("widget.habit.duration.days", defaultValue: "%d d", comment: "Habit widget duration days")
    }

    private var durationHoursFormat: String {
        WidgetLocalization.string("widget.habit.duration.hours", defaultValue: "%d h", comment: "Habit widget duration hours")
    }

    private var durationMinutesFormat: String {
        WidgetLocalization.string("widget.habit.duration.minutes", defaultValue: "%d min", comment: "Habit widget duration minutes")
    }

    private var progressFormat: String {
        WidgetLocalization.string("widget.habit.progress", defaultValue: "%d / %d days", comment: "Habit widget progress")
    }

    private var checkInsFormat: String {
        WidgetLocalization.string("widget.habit.checkins", defaultValue: "%d marks", comment: "Habit widget check-ins")
    }
}

struct EatometerHabitWidget: Widget {
    static let kind: String = EatometerWidgetStore.habitWidgetKind

    private var displayNameText: String {
        WidgetLocalization.string(
            "widget.gallery.habit.title",
            defaultValue: "Habit",
            comment: "Habit widget display name"
        )
    }

    private var descriptionText: String {
        WidgetLocalization.string(
            "widget.gallery.habit.description",
            defaultValue: "Track one habit and mark manual stages.",
            comment: "Habit widget gallery description"
        )
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: HabitWidgetConfigurationIntent.self, provider: HabitWidgetProvider()) { entry in
            HabitWidgetView(entry: entry)
        }
        .configurationDisplayName(displayNameText)
        .description(descriptionText)
        .supportedFamilies([.systemSmall, .systemMedium])
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

struct NutritionWidgetView: View {
    let entry: NutritionWidgetEntry
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var accentColor: Color { entry.accent.color }
    private var primaryText: Color { widgetPrimaryText(style: entry.style, isDark: isDark) }
    private var secondaryText: Color { widgetSecondaryText(style: entry.style, isDark: isDark) }

    private var caloriesSummaryText: String {
        String.localizedStringWithFormat(
            WidgetLocalization.string(
                "today.kcal_value",
                defaultValue: "%d kcal",
                comment: "Calories value"
            ),
            entry.calories
        )
    }

    private var eatenTitleText: String {
        WidgetLocalization.string(
            "diary.eaten",
            defaultValue: "Eaten",
            comment: "Nutrition widget eaten title"
        )
    }

    private var proteinTitleText: String {
        WidgetLocalization.string(
            "diary.protein",
            defaultValue: "Protein",
            comment: "Nutrition widget protein title"
        )
    }

    private var fatTitleText: String {
        WidgetLocalization.string(
            "diary.fat",
            defaultValue: "Fat",
            comment: "Nutrition widget fat title"
        )
    }

    private var carbsTitleText: String {
        WidgetLocalization.string(
            "diary.carbs",
            defaultValue: "Carbs",
            comment: "Nutrition widget carbs title"
        )
    }

    private var dividerColor: Color {
        Color.primary.opacity(0.08)
    }

    private func nutrientValueText(_ value: Int) -> String {
        "\(value)"
    }

    private func nutritionHeaderRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(primaryText)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.vertical, 2)
    }

    private func nutritionValueRow(title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryText)
            }

            Spacer(minLength: 0)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            nutritionHeaderRow(title: eatenTitleText, value: caloriesSummaryText)
                .padding(.trailing, 30)

            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)

            nutritionValueRow(title: proteinTitleText, value: nutrientValueText(entry.protein), tint: .green)

            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)

            nutritionValueRow(title: fatTitleText, value: nutrientValueText(entry.fat), tint: .orange)

            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)

            nutritionValueRow(title: carbsTitleText, value: nutrientValueText(entry.carbs), tint: .blue)
        }
        .padding(16)
        .eatometerWidgetChrome(style: entry.style, accent: accentColor, isDark: isDark)
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
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}

private struct StatsWidgetEntry: TimelineEntry {
    let date: Date
    let calories: Int
    let protein: Int
    let fat: Int
    let carbs: Int
    let caloriesGoal: Int
    let proteinGoal: Int
    let fatGoal: Int
    let carbsGoal: Int
    let isWaterTrackingEnabled: Bool
    let waterIntakeMilliliters: Int
    let waterGoalMilliliters: Int
    let loggingStreakDays: Int
    let focus: EatometerStatsWidgetFocus
    let style: EatometerWidgetVisualStyle
    let accent: EatometerWidgetAccent
}

private struct StatsWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatsWidgetEntry {
        placeholderEntry(focus: .overview, style: .glass, accent: .app)
    }

    func snapshot(for configuration: StatsWidgetConfigurationIntent, in context: Context) async -> StatsWidgetEntry {
        makeEntry(
            focus: configuration.focus ?? .overview,
            style: .glass,
            accent: .app
        )
    }

    func timeline(for configuration: StatsWidgetConfigurationIntent, in context: Context) async -> Timeline<StatsWidgetEntry> {
        let entry = makeEntry(
            focus: configuration.focus ?? .overview,
            style: .glass,
            accent: .app
        )
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    private func makeEntry(
        focus: EatometerStatsWidgetFocus,
        style: EatometerWidgetVisualStyle,
        accent: EatometerWidgetAccent
    ) -> StatsWidgetEntry {
        guard let snapshot = EatometerWidgetStore.loadTodaySnapshot() else {
            return placeholderEntry(focus: focus, style: style, accent: accent)
        }

        return StatsWidgetEntry(
            date: .now,
            calories: snapshot.calories,
            protein: snapshot.protein,
            fat: snapshot.fat,
            carbs: snapshot.carbs,
            caloriesGoal: snapshot.caloriesGoal,
            proteinGoal: snapshot.proteinGoal,
            fatGoal: snapshot.fatGoal,
            carbsGoal: snapshot.carbsGoal,
            isWaterTrackingEnabled: snapshot.isWaterTrackingEnabled,
            waterIntakeMilliliters: snapshot.waterIntakeMilliliters,
            waterGoalMilliliters: snapshot.waterGoalMilliliters,
            loggingStreakDays: snapshot.loggingStreakDays,
            focus: focus,
            style: style,
            accent: accent
        )
    }

    private func placeholderEntry(
        focus: EatometerStatsWidgetFocus,
        style: EatometerWidgetVisualStyle,
        accent: EatometerWidgetAccent
    ) -> StatsWidgetEntry {
        StatsWidgetEntry(
            date: .now,
            calories: 1380,
            protein: 105,
            fat: 48,
            carbs: 132,
            caloriesGoal: 2000,
            proteinGoal: 150,
            fatGoal: 67,
            carbsGoal: 200,
            isWaterTrackingEnabled: true,
            waterIntakeMilliliters: 1250,
            waterGoalMilliliters: 2000,
            loggingStreakDays: 5,
            focus: focus,
            style: style,
            accent: accent
        )
    }
}

private struct StatsWidgetView: View {
    let entry: StatsWidgetEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family

    private var isDark: Bool { colorScheme == .dark }
    private var accentColor: Color { entry.accent.color }
    private var primaryText: Color { widgetPrimaryText(style: entry.style, isDark: isDark) }
    private var secondaryText: Color { widgetSecondaryText(style: entry.style, isDark: isDark) }

    private var titleText: String {
        WidgetLocalization.string("widget.stats.title", defaultValue: "Stats", comment: "Stats widget title")
    }

    private var caloriesTitleText: String {
        WidgetLocalization.string("settings.widget.metric.calories", defaultValue: "Calories", comment: "Calories metric")
    }

    private var macrosTitleText: String {
        WidgetLocalization.string("today.stats.macros.title", defaultValue: "Macros", comment: "Macros title")
    }

    private var waterTitleText: String {
        WidgetLocalization.string("water.title", defaultValue: "Water", comment: "Water title")
    }

    private var streakTitleText: String {
        WidgetLocalization.string("today.stats.streak.title", defaultValue: "Streak", comment: "Streak title")
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                smallBody
            } else {
                mediumBody
            }
        }
        .padding(family == .systemSmall ? 12 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .eatometerWidgetChrome(style: entry.style, accent: accentColor, isDark: isDark)
        .widgetURL(URL(string: "eatometer://statistics"))
    }

    @ViewBuilder
    private var smallBody: some View {
        switch entry.focus {
        case .overview:
            focusCard(
                title: caloriesTitleText,
                value: "\(entry.calories)",
                subtitle: kcalGoalText(value: entry.caloriesGoal),
                iconName: "flame.fill",
                tint: accentColor,
                progress: ratio(entry.calories, entry.caloriesGoal)
            )
        case .calories:
            focusCard(
                title: caloriesTitleText,
                value: "\(entry.calories)",
                subtitle: kcalGoalText(value: entry.caloriesGoal),
                iconName: "flame.fill",
                tint: .red,
                progress: ratio(entry.calories, entry.caloriesGoal)
            )
        case .macros:
            macroFocusCard
        case .water:
            focusCard(
                title: waterTitleText,
                value: waterAmountText(entry.waterIntakeMilliliters),
                subtitle: waterAmountText(entry.waterGoalMilliliters),
                iconName: "drop.fill",
                tint: .blue,
                progress: ratio(entry.waterIntakeMilliliters, entry.waterGoalMilliliters)
            )
        case .streak:
            focusCard(
                title: streakTitleText,
                value: "\(entry.loggingStreakDays)",
                subtitle: WidgetLocalization.string("widget.stats.completed_days", defaultValue: "completed days", comment: "Completed days subtitle"),
                iconName: "trophy.fill",
                tint: .orange,
                progress: min(1, Double(entry.loggingStreakDays) / 7.0)
            )
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.focus == .overview {
                VStack(alignment: .leading, spacing: 5) {
                    Text(titleText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    .frame(height: 24)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                        compactMetricCard(title: caloriesTitleText, value: "\(entry.calories)", iconName: "flame.fill", tint: .red, progress: ratio(entry.calories, entry.caloriesGoal))
                        compactMetricCard(title: macrosTitleText, value: "\(entry.protein)/\(entry.fat)/\(entry.carbs)", iconName: "chart.bar.fill", tint: accentColor, progress: macroAverageProgress)
                        compactMetricCard(title: waterTitleText, value: waterAmountText(entry.waterIntakeMilliliters), iconName: "drop.fill", tint: .blue, progress: ratio(entry.waterIntakeMilliliters, entry.waterGoalMilliliters))
                        compactMetricCard(title: streakTitleText, value: "\(entry.loggingStreakDays)", iconName: "trophy.fill", tint: .orange, progress: min(1, Double(entry.loggingStreakDays) / 7.0))
                    }
                }
            } else {
                smallBody
            }
        }
    }

    private var macroFocusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerIcon(title: macrosTitleText, iconName: "chart.bar.fill", tint: accentColor)

            VStack(spacing: 6) {
                macroRow(title: WidgetLocalization.string("diary.protein", defaultValue: "Protein", comment: "Protein"), value: entry.protein, goal: entry.proteinGoal, tint: .green)
                macroRow(title: WidgetLocalization.string("diary.fat", defaultValue: "Fat", comment: "Fat"), value: entry.fat, goal: entry.fatGoal, tint: .orange)
                macroRow(title: WidgetLocalization.string("diary.carbs", defaultValue: "Carbs", comment: "Carbs"), value: entry.carbs, goal: entry.carbsGoal, tint: .blue)
            }

            Spacer(minLength: 0)
        }
    }

    private func focusCard(title: String, value: String, subtitle: String, iconName: String, tint: Color, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            headerIcon(title: title, iconName: iconName, tint: tint)

            Text(value)
                .font(.system(size: family == .systemSmall ? 28 : 32, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .allowsTightening(true)

            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)

            progressBar(progress: progress, tint: tint)

            Spacer(minLength: 0)
        }
    }

    private func compactMetricCard(title: String, value: String, iconName: String, tint: Color, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
            }

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.36)
                .allowsTightening(true)

            progressBar(progress: progress, tint: tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .background(metricBackground)
    }

    private func headerIcon(title: String, iconName: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: family == .systemSmall ? 28 : 30, height: family == .systemSmall ? 28 : 30)
                .background(tint, in: Circle())

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .allowsTightening(true)
        }
        .padding(.trailing, 30)
    }

    private func macroRow(title: String, value: Int, goal: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
                Spacer(minLength: 4)
                Text("\(value)/\(goal)g")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)
                    .allowsTightening(true)
            }
            progressBar(progress: ratio(value, goal), tint: tint)
        }
    }

    private func progressBar(progress: Double, tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(primaryText.opacity(isDark ? 0.16 : 0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 6)
    }

    private var metricBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.055))
    }

    private var macroAverageProgress: Double {
        let values = [
            ratio(entry.protein, entry.proteinGoal),
            ratio(entry.fat, entry.fatGoal),
            ratio(entry.carbs, entry.carbsGoal)
        ]
        return values.reduce(0, +) / Double(values.count)
    }

    private func ratio(_ value: Int, _ goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(max(Double(value) / Double(goal), 0), 1)
    }

    private func kcalGoalText(value: Int) -> String {
        String.localizedStringWithFormat(
            WidgetLocalization.string("today.kcal_value", defaultValue: "%d kcal", comment: "Calories value"),
            value
        )
    }

    private func waterAmountText(_ milliliters: Int) -> String {
        if milliliters >= 1000 {
            return String(format: "%.1f L", Double(milliliters) / 1000.0)
        }
        return "\(milliliters) ml"
    }
}

struct EatometerStatsWidget: Widget {
    static let kind: String = EatometerWidgetStore.statsWidgetKind

    private var displayNameText: String {
        WidgetLocalization.string(
            "widget.stats.title",
            defaultValue: "Stats",
            comment: "Stats widget display name"
        )
    }

    private var descriptionText: String {
        WidgetLocalization.string(
            "widget.gallery.stats.description",
            defaultValue: "Daily calories, macros, water and completed-day streak.",
            comment: "Stats widget gallery description"
        )
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: StatsWidgetConfigurationIntent.self, provider: StatsWidgetProvider()) { entry in
            StatsWidgetView(entry: entry)
        }
        .configurationDisplayName(displayNameText)
        .description(descriptionText)
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    EatometerWidget()
} timeline: {
    WaterWidgetEntry(date: .now, intakeMilliliters: 750, goalMilliliters: 2000, adjustmentMilliliters: 200, style: .soft, accent: .blue)
}

#Preview("Water Glass", as: .systemMedium) {
    EatometerWidget()
} timeline: {
    WaterWidgetEntry(date: .now, intakeMilliliters: 1250, goalMilliliters: 2000, adjustmentMilliliters: 200, style: .glass, accent: .blue)
}

#Preview("Quick Meal Medium", as: .systemMedium) {
    EatometerQuickMealWidget()
} timeline: {
    QuickMealWidgetEntry(
        date: .now,
        calories: 1380,
        caloriesGoal: 2000,
        mealCategories: [
            EatometerMealCategorySummary(id: "breakfast", title: "Breakfast", symbolName: "sunrise.fill"),
            EatometerMealCategorySummary(id: "lunch", title: "Lunch", symbolName: "sun.max.fill"),
            EatometerMealCategorySummary(id: "dinner", title: "Dinner", symbolName: "moon.stars.fill"),
            EatometerMealCategorySummary(id: "snack", title: "Snack", symbolName: "leaf.fill"),
            EatometerMealCategorySummary(id: "late", title: "Late meal", symbolName: "moon.fill")
        ],
        meals: [],
        quickItems: [],
        style: .soft,
        accent: .app
    )
}

#Preview("Quick Meal", as: .systemLarge) {
    EatometerQuickMealWidget()
} timeline: {
    QuickMealWidgetEntry(
        date: .now,
        calories: 1380,
        caloriesGoal: 2000,
        mealCategories: [
            EatometerMealCategorySummary(id: "breakfast", title: "Breakfast", symbolName: "sunrise.fill"),
            EatometerMealCategorySummary(id: "lunch", title: "Lunch", symbolName: "sun.max.fill"),
            EatometerMealCategorySummary(id: "dinner", title: "Dinner", symbolName: "moon.stars.fill"),
            EatometerMealCategorySummary(id: "snack", title: "Snack", symbolName: "leaf.fill"),
            EatometerMealCategorySummary(id: "late", title: "Late meal", symbolName: "moon.fill")
        ],
        meals: [
            EatometerTodayMealSummary(
                id: UUID().uuidString,
                title: "Breakfast",
                categoryID: "breakfast",
                categoryTitle: "Breakfast",
                calories: 430,
                scheduledAt: .now
            ),
            EatometerTodayMealSummary(
                id: UUID().uuidString,
                title: "Lunch",
                categoryID: "lunch",
                categoryTitle: "Lunch",
                calories: 620,
                scheduledAt: .now
            )
        ],
        quickItems: [
            QuickMealWidgetItem(itemID: UUID().uuidString, title: "Greek yogurt", subtitle: "", calories: 180, kind: .product),
            QuickMealWidgetItem(itemID: UUID().uuidString, title: "Chicken bowl", subtitle: "", calories: 520, kind: .mealTemplate),
            QuickMealWidgetItem(itemID: UUID().uuidString, title: "Soup", subtitle: "", calories: 340, kind: .recipe)
        ],
        style: .glass,
        accent: .mint
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

#Preview("Stats", as: .systemMedium) {
    EatometerStatsWidget()
} timeline: {
    StatsWidgetEntry(
        date: .now,
        calories: 1380,
        protein: 105,
        fat: 48,
        carbs: 132,
        caloriesGoal: 2000,
        proteinGoal: 150,
        fatGoal: 67,
        carbsGoal: 200,
        isWaterTrackingEnabled: true,
        waterIntakeMilliliters: 1250,
        waterGoalMilliliters: 2000,
        loggingStreakDays: 5,
        focus: .overview,
        style: .glass,
        accent: .app
    )
}
