import SwiftUI

/// iPad ("regular" width) Diary layout from the mock-ups:
/// a horizontal "Summary" row of level cards, followed by a horizontal
/// "Meals" row of meal cards.
struct DiaryRegularSummaryRow: View {
    let waterMilliliters: Int
    let waterGoalMilliliters: Int
    let summary: NutritionSummary
    let goal: DailyNutritionGoal
    let showsWater: Bool
    let onOpenWater: () -> Void

    private var targetProtein: Int {
        Int((Double(goal.calories) * Double(goal.proteinPercent) / 100 / 4).rounded())
    }

    private var targetFat: Int {
        Int((Double(goal.calories) * Double(goal.fatPercent) / 100 / 9).rounded())
    }

    private var targetCarbs: Int {
        Int((Double(goal.calories) * Double(goal.carbsPercent) / 100 / 4).rounded())
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if showsWater {
                    Button(action: onOpenWater) {
                        DiaryLevelCard(
                            title: Text("water.title"),
                            value: Text(verbatim: "\(waterMilliliters)/\(waterGoalMilliliters) ml"),
                            tint: EOTheme.Palette.water,
                            progress: ratio(waterMilliliters, waterGoalMilliliters)
                        )
                    }
                    .buttonStyle(.plain)
                }

                DiaryLevelCard(
                    title: Text("diary.calories"),
                    value: Text(verbatim: "\(summary.calories)/\(goal.calories)"),
                    tint: EOTheme.Palette.calories,
                    progress: ratio(summary.calories, goal.calories)
                )

                DiaryLevelCard(
                    title: Text("diary.protein"),
                    value: Text(verbatim: "\(summary.protein)/\(targetProtein)"),
                    tint: EOTheme.Palette.protein,
                    progress: ratio(summary.protein, targetProtein)
                )

                DiaryLevelCard(
                    title: Text("diary.carbs"),
                    value: Text(verbatim: "\(summary.carbs)/\(targetCarbs)"),
                    tint: EOTheme.Palette.carbs,
                    progress: ratio(summary.carbs, targetCarbs)
                )

                DiaryLevelCard(
                    title: Text("diary.fat"),
                    value: Text(verbatim: "\(summary.fat)/\(targetFat)"),
                    tint: EOTheme.Palette.fat,
                    progress: ratio(summary.fat, targetFat)
                )
            }
            .padding(.horizontal, EOTheme.Metrics.screenInset)
            .padding(.vertical, 2)
        }
        .frame(height: 254)
    }

    private func ratio(_ value: Int, _ target: Int) -> CGFloat {
        guard target > 0 else { return 0 }
        return min(max(CGFloat(value) / CGFloat(target), 0), 1)
    }
}

/// White card that fills from the bottom with a tinted "liquid level",
/// used by the iPad Summary row.
struct DiaryLevelCard: View {
    let title: Text
    let value: Text
    let tint: Color
    let progress: CGFloat

    @State private var labelFrames: [String: CGRect] = [:]

    private let coordinateSpace = "diary-level-card"

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                EOTheme.Palette.card

                Rectangle()
                    .fill(tint)
                    .frame(height: proxy.size.height * progress)
                    .animation(.smooth(duration: 0.5), value: progress)

                VStack(alignment: .leading) {
                    title
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(
                            EOTheme.Palette.levelLabel(
                                tint,
                                isSubmerged: isSubmerged("title", cardHeight: proxy.size.height)
                            )
                        )
                        .lineLimit(1)
                        .eoLevelLabelFrame("title", in: coordinateSpace)

                    Spacer(minLength: 0)

                    value
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(
                            EOTheme.Palette.levelLabel(
                                tint,
                                isSubmerged: isSubmerged("value", cardHeight: proxy.size.height)
                            )
                        )
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .eoLevelLabelFrame("value", in: coordinateSpace)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)
            }
            .coordinateSpace(name: coordinateSpace)
            .onPreferenceChange(EOLevelLabelFramePreferenceKey.self) { frames in
                labelFrames = frames
            }
            .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
        .frame(width: 244)
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

/// Horizontal "Meals" row: one card per meal category listing its items.
struct DiaryRegularMealsRow: View {
    let categories: [MealCategory]
    let items: (MealCategory) -> [String]
    let calories: (MealCategory) -> Int
    let onOpen: (MealCategory) -> Void
    let contextMenu: (MealCategory) -> AnyView

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(categories) { category in
                    DiaryRegularMealCard(
                        category: category,
                        items: items(category),
                        calories: calories(category)
                    )
                    .onTapGesture { onOpen(category) }
                    .eoCardContextMenu { contextMenu(category) }
                    // Pins the card so a reorder can't leave its context menu
                    // wired to the meal that used to sit in this slot.
                    .id(category.id)
                }
            }
            .padding(.horizontal, EOTheme.Metrics.screenInset)
            .padding(.vertical, 2)
        }
    }
}

private struct DiaryRegularMealCard: View {
    let category: MealCategory
    let items: [String]
    let calories: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: category.symbolName)
                    .font(.body.weight(.semibold))
                Text(category.displayTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, EOTheme.Metrics.cardInset)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ForEach(Array(items.prefix(6).enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    EORowSeparator()
                }

                Text(verbatim: item)
                    .font(EOTheme.Typography.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, EOTheme.Metrics.cardInset)
                    .padding(.vertical, 12)
            }

            Text(verbatim: "\(calories) \(NSLocalizedString("diary.kcal", comment: "Calories suffix"))")
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, EOTheme.Metrics.cardInset)
                .padding(.top, 18)
                .padding(.bottom, 16)
        }
        .frame(width: 284, alignment: .leading)
        .background(
            EOTheme.Palette.card,
            in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}
