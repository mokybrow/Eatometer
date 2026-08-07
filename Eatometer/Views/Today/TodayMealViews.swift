import SwiftUI

struct MealCategoryCard: View {
    let category: MealCategory
    let meals: [MealEntry]
    let target: NutritionSummary
    let isHighlighted: Bool
    let onOpen: () -> Void

    init(
        category: MealCategory,
        meals: [MealEntry],
        target: NutritionSummary,
        isHighlighted: Bool = false,
        onOpen: @escaping () -> Void
    ) {
        self.category = category
        self.meals = meals
        self.target = target
        self.isHighlighted = isHighlighted
        self.onOpen = onOpen
    }

    private var consumedCalories: Int {
        meals.reduce(0) { $0 + $1.calories }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Text(verbatim: "\(consumedCalories) \(NSLocalizedString("diary.kcal", comment: "Calories suffix"))")
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            isHighlighted ? Color.platformSystemGray5 : EOTheme.Palette.card,
            in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        .onTapGesture(perform: onOpen)
        .animation(.easeInOut(duration: 0.16), value: isHighlighted)
    }
}
