import SwiftUI

struct DiaryOverviewCards: View {
    let waterMilliliters: Int
    let waterGoalMilliliters: Int
    let summary: NutritionSummary
    let goal: DailyNutritionGoal
    let onOpenWater: () -> Void
    /// Water tracking can be switched off; the ring card above keeps its size
    /// either way, so the top of the Diary never shifts.
    var showsWater: Bool = true
    /// Quick +/- one step, so a mis-tap can be undone without opening the sheet.
    var onAdjustWater: ((Int) -> Void)? = nil
    var quickStepMilliliters: Int = 200

    var body: some View {
        VStack(spacing: 16) {
            DiaryNutritionRingCard(summary: summary, goal: goal)
                .frame(maxWidth: .infinity)
                .id("diary-goal-card")

            if showsWater {
                Button(action: onOpenWater) {
                    DiaryWaterOverviewCard(
                        currentMilliliters: waterMilliliters,
                        goalMilliliters: waterGoalMilliliters
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("water.title"))
                .accessibilityHint(Text("diary.water.add"))
                .frame(maxWidth: .infinity, minHeight: 156, maxHeight: 156)
                .eoCardContextMenu { waterMenuItems }
                .id("diary-water-card")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Menus

    @ViewBuilder
    private var waterMenuItems: some View {
        if let onAdjustWater {
            Button {
                onAdjustWater(quickStepMilliliters)
            } label: {
                Label {
                    Text(verbatim: quickAdjustTitle("water.quick_add"))
                } icon: {
                    Image(systemName: "plus")
                }
            }

            Button {
                onAdjustWater(-quickStepMilliliters)
            } label: {
                Label {
                    Text(verbatim: quickAdjustTitle("water.quick_remove"))
                } icon: {
                    Image(systemName: "minus")
                }
            }
            .disabled(waterMilliliters <= 0)
        }

        Button(action: onOpenWater) {
            Label("water.add_title", systemImage: "slider.horizontal.3")
        }
    }

    /// "Add 200 ml" / "Remove 200 ml" for the quick water context menu.
    private func quickAdjustTitle(_ key: String) -> String {
        String(
            format: NSLocalizedString(key, comment: "Quick water adjustment"),
            quickStepMilliliters
        )
    }
}

/// Full-width water card that fills from the bottom with a tinted level.
private struct DiaryWaterOverviewCard: View {
    let currentMilliliters: Int
    let goalMilliliters: Int

    @State private var labelFrames: [String: CGRect] = [:]

    private let coordinateSpace = "diary-water-card"

    private var progress: CGFloat {
        guard goalMilliliters > 0 else { return 0 }
        return min(max(CGFloat(currentMilliliters) / CGFloat(goalMilliliters), 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                EOTheme.Palette.card

                Rectangle()
                    .fill(EOTheme.Palette.water)
                    .frame(height: proxy.size.height * progress)
                    .animation(.smooth(duration: 0.5), value: progress)

                VStack(alignment: .leading) {
                    Text("water.title")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(
                            EOTheme.Palette.levelLabel(
                                EOTheme.Palette.water,
                                isSubmerged: isSubmerged("title", cardHeight: proxy.size.height)
                            )
                        )
                        .eoLevelLabelFrame("title", in: coordinateSpace)

                    Spacer()

                    Text(verbatim: "\(currentMilliliters)/\(goalMilliliters) ml")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(
                            EOTheme.Palette.levelLabel(
                                .primary,
                                isSubmerged: isSubmerged("value", cardHeight: proxy.size.height)
                            )
                        )
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .eoLevelLabelFrame("value", in: coordinateSpace)
                }
                .padding(EOTheme.Metrics.cardInset)
            }
            .coordinateSpace(name: coordinateSpace)
            .onPreferenceChange(EOLevelLabelFramePreferenceKey.self) { frames in
                labelFrames = frames
            }
            .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func isSubmerged(_ id: String, cardHeight: CGFloat) -> Bool {
        EOLevelGeometry.isSubmerged(
            labelFrames: labelFrames,
            id: id,
            cardHeight: cardHeight,
            progress: progress
        )
    }
}

/// Full-width nutrition card with one compact progress ring per metric.
struct DiaryNutritionRingCard: View {
    let summary: NutritionSummary
    let goal: DailyNutritionGoal

    private let ringDiameter: CGFloat = 56
    private let ringLineWidth: CGFloat = 7

    private var rings: [MacroRing] {
        [
            MacroRing(
                id: "calories",
                titleKey: "diary.calories",
                value: summary.calories,
                target: goal.calories,
                unit: kcalUnit,
                color: EOTheme.Palette.calories
            ),
            MacroRing(
                id: "protein",
                titleKey: "diary.protein",
                value: summary.protein,
                target: targetProtein,
                unit: gramsUnit,
                color: EOTheme.Palette.protein
            ),
            // Carbohydrates before fats, which is the order the figures are
            // quoted in everywhere outside this app and the order on the label
            // of anything you can buy.
            MacroRing(
                id: "carbs",
                titleKey: "diary.carbs",
                value: summary.carbs,
                target: targetCarbs,
                unit: gramsUnit,
                color: EOTheme.Palette.carbs
            ),
            MacroRing(
                id: "fat",
                titleKey: "diary.fat",
                value: summary.fat,
                target: targetFat,
                unit: gramsUnit,
                color: EOTheme.Palette.fat
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("diary.nutrition_ring")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .top, spacing: 8) {
                ForEach(rings) { ring in
                    ringMetric(ring)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(EOTheme.Metrics.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            EOTheme.Palette.card,
            in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("diary.nutrition_ring"))
        .accessibilityValue(Text(verbatim: accessibilitySummary))
    }

    /// One ring, its name, and its figure — in that order down the column.
    ///
    /// The number is under the ring rather than inside it. Inside, at nine
    /// points, "1200/2000" was two figures fighting for the width of a
    /// fifty-six-point circle and neither could be read at a glance; the ring
    /// was already saying what the fraction said. Below it, in the ring's own
    /// colour, the figure is the thing the eye lands on and the colour is what
    /// ties it to the arc above.
    private func ringMetric(_ ring: MacroRing) -> some View {
        VStack(spacing: 8) {
            MacroRingShape(
                percent: percent(ring.value, ring.target),
                trackColor: EOTheme.Palette.ringTrack,
                color: ring.color,
                lineWidth: ringLineWidth
            )
            .frame(width: ringDiameter, height: ringDiameter)

            VStack(spacing: 2) {
                // Upper-cased and tracked out, so four short words read as
                // labels rather than as four more numbers.
                Text(LocalizedStringKey(ring.titleKey))
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.3)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(verbatim: "\(ring.value)")
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ring.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var gramsUnit: String {
        NSLocalizedString("unit.grams.short", comment: "Grams unit short title")
    }

    private var kcalUnit: String {
        NSLocalizedString("diary.kcal", comment: "Calories suffix")
    }

    private var targetProtein: Int { target(goal.proteinPercent, perGram: 4) }
    private var targetFat: Int { target(goal.fatPercent, perGram: 9) }
    private var targetCarbs: Int { target(goal.carbsPercent, perGram: 4) }

    private var accessibilitySummary: String {
        [
            "\(NSLocalizedString("diary.calories", comment: "Calories")) \(summary.calories)/\(goal.calories) \(kcalUnit)",
            "\(NSLocalizedString("diary.protein", comment: "Protein")) \(summary.protein)/\(targetProtein) \(gramsUnit)",
            "\(NSLocalizedString("diary.carbs", comment: "Carbs")) \(summary.carbs)/\(targetCarbs) \(gramsUnit)",
            "\(NSLocalizedString("diary.fat", comment: "Fat")) \(summary.fat)/\(targetFat) \(gramsUnit)"
        ].joined(separator: ", ")
    }

    private struct MacroRing: Identifiable {
        let id: String
        let titleKey: String
        let value: Int
        let target: Int
        let unit: String
        let color: Color
    }

    /// Uncapped: past 100% the arc keeps winding, and the shadowed leading cap
    /// makes the overlap read as a second lap.
    private func percent(_ value: Int, _ target: Int) -> Double {
        guard target > 0 else { return 0 }
        return max(Double(value) / Double(target) * 100, 0)
    }

    private func target(_ share: Int, perGram: Double) -> Int {
        Int((Double(goal.calories) * Double(share) / 100 / perGram).rounded())
    }
}

/// A plain arc from `startAngle` to the angle `percent` maps to. Animating
/// `percent` interpolates the path, so the ring fills instead of snapping.
private struct RingShape: Shape {
    static func percentToAngle(percent: Double, startAngle: Double) -> Double {
        (percent / 100 * 360) + startAngle
    }

    private var percent: Double
    private let startAngle: Double
    private let drawnClockwise: Bool

    var animatableData: Double {
        get { percent }
        set { percent = newValue }
    }

    init(percent: Double = 100, startAngle: Double = -90, drawnClockwise: Bool = false) {
        self.percent = percent
        self.startAngle = startAngle
        self.drawnClockwise = drawnClockwise
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        let endAngle = Angle(degrees: RingShape.percentToAngle(percent: percent, startAngle: startAngle))
        return Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: Angle(degrees: startAngle),
                endAngle: endAngle,
                clockwise: drawnClockwise
            )
        }
    }
}

/// One Activity-style ring: a faint track plus an arc that sweeps through an
/// angular gradient. Near a full turn the leading cap is drawn again with a
/// drop shadow so it reads as lying on top of the tail.
private struct MacroRingShape: View {
    let percent: Double
    let trackColor: Color
    let color: Color
    var lineWidth: CGFloat = 20

    private static let shadowColor = Color.black.opacity(0.2)
    private static let shadowRadius: CGFloat = 5
    private static let shadowOffsetMultiplier: CGFloat = shadowRadius + 2

    private let startAngle: Double = -90

    /// Sweep of the arc measured from twelve o'clock.
    private var absolutePercentageAngle: Double {
        RingShape.percentToAngle(percent: percent, startAngle: 0)
    }

    /// Where the arc ends in the view's own coordinates.
    private var relativePercentageAngle: Double {
        absolutePercentageAngle + startAngle
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RingShape()
                    .stroke(style: StrokeStyle(lineWidth: lineWidth))
                    .fill(trackColor)

                RingShape(percent: percent, startAngle: startAngle)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .fill(color)

                // A zero-length arc draws nothing, so an untouched ring would be
                // a bare track. Stand in for the round cap the arc would start
                // with — flat, since there is no tail for it to sit on yet.
                if percent < 0.5 {
                    cap
                        .offset(y: -min(geometry.size.width, geometry.size.height) / 2)
                }

                if showsEndCap(frame: geometry.size) {
                    cap
                        .shadow(
                            color: Self.shadowColor,
                            radius: Self.shadowRadius,
                            x: endCapShadowOffset().0,
                            y: endCapShadowOffset().1
                        )
                        .offset(
                            x: endCapLocation(frame: geometry.size).0,
                            y: endCapLocation(frame: geometry.size).1
                        )
                }
            }
        }
        // Keeps the whole stroke inside the frame it was given.
        .padding(lineWidth / 2)
        .animation(.smooth(duration: 0.5), value: percent)
    }

    /// Stands in for the arc's round cap. The shadow is added only where the cap
    /// actually lies on top of the tail.
    private var cap: some View {
        Circle()
            .fill(color)
            .frame(width: lineWidth, height: lineWidth, alignment: .center)
    }

    private func endCapLocation(frame: CGSize) -> (CGFloat, CGFloat) {
        let radians = relativePercentageAngle * .pi / 180
        let offsetRadius = min(frame.width, frame.height) / 2
        return (offsetRadius * CGFloat(cos(radians)), offsetRadius * CGFloat(sin(radians)))
    }

    private func endCapShadowOffset() -> (CGFloat, CGFloat) {
        let radians = (absolutePercentageAngle + (startAngle + 90)) * .pi / 180
        return (
            CGFloat(cos(radians)) * Self.shadowOffsetMultiplier,
            CGFloat(sin(radians)) * Self.shadowOffsetMultiplier
        )
    }

    /// Only needed once the head is about to reach — or has passed — the tail.
    private func showsEndCap(frame: CGSize) -> Bool {
        guard percent < 100 else { return true }
        let circleRadius = min(frame.width, frame.height) / 2
        let remainingAngleInRadians = CGFloat((360 - absolutePercentageAngle) * .pi / 180)
        return circleRadius * remainingAngleInRadians <= lineWidth
    }
}

struct WeeklyMacroCaloriesEntry: Identifiable, Hashable {
    let date: Date
    let summary: NutritionSummary

    var id: Date { date }
}

private struct WeeklyMacroSegment: Identifiable {
    let id: String
    let calories: Int
    let tint: Color
}

struct WeeklyMacroCaloriesCard: View {
    let entries: [WeeklyMacroCaloriesEntry]
    let selectedDay: Date
    let averageSummary: NutritionSummary
    let showsSelection: Bool

    @State private var selectedEntryDate: Date?

    init(
        entries: [WeeklyMacroCaloriesEntry],
        selectedDay: Date,
        averageSummary: NutritionSummary,
        showsSelection: Bool = false
    ) {
        self.entries = entries
        self.selectedDay = selectedDay
        self.averageSummary = averageSummary
        self.showsSelection = showsSelection
    }

    private var maxCalories: Int {
        max(entries.map(\.summary.calories).max() ?? 0, 1)
    }

    private var averageMacroCalories: Int {
        averageSummary.protein * 4 + averageSummary.fat * 9 + averageSummary.carbs * 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("today.macro_chart.title")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .allowsTightening(true)
                Spacer(minLength: 10)
                if !showsSelection {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary.opacity(0.75))
                }
            }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("today.stats.macros.daily_averages")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    MacroAverageRow(
                        shortTitle: NSLocalizedString("settings.widget.metric.carbs.short", comment: "Short carbs label"),
                        grams: averageSummary.carbs,
                        percent: macroPercent(for: averageSummary.carbs * 4),
                        tint: WeeklyMacroBarColors.carbs
                    )
                    MacroAverageRow(
                        shortTitle: NSLocalizedString("settings.widget.metric.fat.short", comment: "Short fat label"),
                        grams: averageSummary.fat,
                        percent: macroPercent(for: averageSummary.fat * 9),
                        tint: WeeklyMacroBarColors.fat
                    )
                    MacroAverageRow(
                        shortTitle: NSLocalizedString("settings.widget.metric.protein.short", comment: "Short protein label"),
                        grams: averageSummary.protein,
                        percent: macroPercent(for: averageSummary.protein * 4),
                        tint: WeeklyMacroBarColors.protein
                    )
                }
                .frame(width: 112, alignment: .leading)

                WeeklyMacroBars(
                    entries: entries,
                    selectedDay: selectedDay,
                    maxCalories: maxCalories,
                    selectedEntryDate: $selectedEntryDate,
                    isInteractive: showsSelection
                )
                .frame(height: 142)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .onChange(of: entries) { _, _ in
            selectedEntryDate = nil
        }
    }

    private func macroPercent(for calories: Int) -> Int {
        guard averageMacroCalories > 0 else { return 0 }
        return Int((Double(max(calories, 0)) / Double(averageMacroCalories) * 100).rounded())
    }
}

private struct WeeklyMacroSelectionCalloutContent: View {
    let entry: WeeklyMacroCaloriesEntry

    private var dateText: String {
        entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var caloriesText: String {
        String(format: NSLocalizedString("today.kcal_value", comment: "Calories value"), entry.summary.calories)
    }

    private var macrosText: String {
        let protein = NSLocalizedString("settings.widget.metric.protein.short", comment: "Short protein label")
        let fat = NSLocalizedString("settings.widget.metric.fat.short", comment: "Short fat label")
        let carbs = NSLocalizedString("settings.widget.metric.carbs.short", comment: "Short carbs label")
        let gramUnit = NSLocalizedString("unit.grams.short", comment: "Grams unit short title")
        return "\(protein) \(entry.summary.protein) \(gramUnit) · \(fat) \(entry.summary.fat) \(gramUnit) · \(carbs) \(entry.summary.carbs) \(gramUnit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(dateText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(caloriesText)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(macrosText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChartSelectionCallout<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.platformSystemBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.15), radius: 16, y: 8)
        .allowsHitTesting(false)
    }
}

private struct MacroAverageRow: View {
    let shortTitle: String
    let grams: Int
    let percent: Int
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(shortTitle)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.appAccentReadableText)
                .frame(width: 17, height: 17)
                .background(tint, in: Circle())

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: NSLocalizedString("recipe.grams_value", comment: "Grams value"), grams))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("\(percent)%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }
}

private struct WeeklyMacroBars: View {
    let entries: [WeeklyMacroCaloriesEntry]
    let selectedDay: Date
    let maxCalories: Int
    @Binding var selectedEntryDate: Date?
    let isInteractive: Bool

    @State private var displayedScale: CGFloat = 0

    private var selectedEntry: WeeklyMacroCaloriesEntry? {
        guard isInteractive, let selectedEntryDate else { return nil }
        return entries.first { Calendar.current.isDate($0.date, inSameDayAs: selectedEntryDate) }
    }

    init(
        entries: [WeeklyMacroCaloriesEntry],
        selectedDay: Date,
        maxCalories: Int,
        selectedEntryDate: Binding<Date?> = .constant(nil),
        isInteractive: Bool = false
    ) {
        self.entries = entries
        self.selectedDay = selectedDay
        self.maxCalories = maxCalories
        self._selectedEntryDate = selectedEntryDate
        self.isInteractive = isInteractive
    }

    var body: some View {
        GeometryReader { geometry in
            let labelHeight: CGFloat = 24
            let axisWidth: CGFloat = 34
            let chartHeight = max(0, geometry.size.height - labelHeight)
            let plotWidth = max(0, geometry.size.width - axisWidth)
            let spacing: CGFloat = 12

            ZStack(alignment: .topLeading) {
                WeeklyMacroValueGrid(maxCalories: maxCalories, chartHeight: chartHeight, axisWidth: axisWidth)

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(entries) { entry in
                        let isCurrentSelection = selectedEntryDate.map {
                            Calendar.current.isDate(entry.date, inSameDayAs: $0)
                        } ?? Calendar.current.isDate(entry.date, inSameDayAs: selectedDay)
                        WeeklyMacroBar(
                            entry: entry,
                            maxCalories: maxCalories,
                            chartHeight: chartHeight,
                            displayedScale: displayedScale,
                            isSelected: isCurrentSelection,
                            isInteractive: isInteractive
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                if let selectedEntryDate,
                                   Calendar.current.isDate(selectedEntryDate, inSameDayAs: entry.date) {
                                    self.selectedEntryDate = nil
                                } else {
                                    self.selectedEntryDate = entry.date
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, axisWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                if let selectedEntry,
                   let selectedIndex = entries.firstIndex(of: selectedEntry) {
                    let anchorX = barAnchorX(index: selectedIndex, count: entries.count, plotWidth: plotWidth, spacing: spacing)
                    let calloutWidth = min(190, max(150, geometry.size.width * 0.58))
                    let calloutX = min(max(anchorX, calloutWidth / 2), max(calloutWidth / 2, plotWidth - calloutWidth / 2))

                    Rectangle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 1, height: chartHeight)
                        .offset(x: anchorX, y: 0)

                    ChartSelectionCallout {
                        WeeklyMacroSelectionCalloutContent(entry: selectedEntry)
                    }
                    .frame(width: calloutWidth)
                    .position(x: calloutX, y: 28)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(2)
                }
            }
        }
        .onAppear {
            guard displayedScale == 0 else { return }
            withAnimation(.easeOut(duration: 0.65)) {
                displayedScale = 1
            }
        }
        .onChange(of: entries) { _, _ in
            displayedScale = 0
            withAnimation(.easeOut(duration: 0.65)) {
                displayedScale = 1
            }
        }
    }

    private func barAnchorX(index: Int, count: Int, plotWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let totalSpacing = spacing * CGFloat(max(count - 1, 0))
        let barWidth = max((plotWidth - totalSpacing) / CGFloat(count), 0)
        return CGFloat(index) * (barWidth + spacing) + barWidth / 2
    }
}

private struct WeeklyMacroValueGrid: View {
    let maxCalories: Int
    let chartHeight: CGFloat
    let axisWidth: CGFloat

    private let fractions: [CGFloat] = [1, 0.5, 0]

    var body: some View {
        GeometryReader { geometry in
            let lineWidth = max(0, geometry.size.width - axisWidth)

            ZStack(alignment: .topLeading) {
                ForEach(fractions, id: \.self) { fraction in
                    let y = chartHeight * (1 - fraction)
                    let labelY = min(max(y, 7), max(chartHeight - 7, 7))
                    let value = Int((CGFloat(maxCalories) * fraction).rounded())

                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: lineWidth, height: 1)
                        .offset(y: y)

                    Text(axisLabel(for: value))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.72))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: axisWidth, alignment: .trailing)
                        .offset(x: lineWidth, y: labelY - 6)
                }
            }
        }
        .frame(height: chartHeight)
    }

    private func axisLabel(for value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

private struct WeeklyMacroBar: View {
    let entry: WeeklyMacroCaloriesEntry
    let maxCalories: Int
    let chartHeight: CGFloat
    let displayedScale: CGFloat
    let isSelected: Bool
    let isInteractive: Bool
    let onSelect: () -> Void

    private var barHeight: CGFloat {
        guard maxCalories > 0, entry.summary.calories > 0 else { return 0 }
        return max(8, chartHeight * CGFloat(entry.summary.calories) / CGFloat(maxCalories) * displayedScale)
    }

    private var segments: [WeeklyMacroSegment] {
        [
            WeeklyMacroSegment(
                id: "protein",
                calories: max(entry.summary.protein, 0) * 4,
                tint: WeeklyMacroBarColors.protein
            ),
            WeeklyMacroSegment(
                id: "fat",
                calories: max(entry.summary.fat, 0) * 9,
                tint: WeeklyMacroBarColors.fat
            ),
            WeeklyMacroSegment(
                id: "carbs",
                calories: max(entry.summary.carbs, 0) * 4,
                tint: WeeklyMacroBarColors.carbs
            )
        ]
    }

    private var totalMacroCalories: Int {
        segments.reduce(0) { $0 + $1.calories }
    }

    var body: some View {
        if isInteractive {
            barContent
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
        } else {
            barContent
        }
    }

    private var barContent: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.045))

                if entry.summary.calories > 0 {
                    if totalMacroCalories > 0 {
                        VStack(spacing: 0) {
                            ForEach(segments) { segment in
                                let segmentHeight = barHeight * CGFloat(segment.calories) / CGFloat(totalMacroCalories)
                                if segmentHeight > 0 {
                                    Rectangle()
                                        .fill(segment.tint)
                                        .frame(height: max(1, segmentHeight))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight, alignment: .top)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.22))
                            .frame(height: barHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: chartHeight, alignment: .bottom)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? Color.primary.opacity(0.20) : Color.clear)
                    .frame(height: 2)
                    .offset(y: 4)
            }

            Text(weekdayTitle(for: entry.date))
                .font(.caption2.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    private func weekdayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        let symbols = DateFormatter().shortStandaloneWeekdaySymbols ?? []
        let index = calendar.component(.weekday, from: date) - 1
        guard symbols.indices.contains(index) else { return "" }
        return String(symbols[index].prefix(1)).uppercased()
    }
}

enum WeeklyMacroBarColors {
    static let protein = Color.appAccent
    static let fat = Color(red: 1.0, green: 0.647, blue: 0.0) // #FFA500
    static let carbs = Color(red: 0.42, green: 0.68, blue: 0.92)
}
