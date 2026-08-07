import SwiftUI

struct NutritionFactsEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let unit: String?
    let value: String
    let secondaryValue: String?
    var isIndented: Bool = false
    var isEmphasized: Bool = false

    init(id: String, title: String, unit: String? = nil, value: String, isIndented: Bool = false, isEmphasized: Bool = false) {
        self.id = id
        self.title = title
        self.unit = unit
        self.value = value
        self.secondaryValue = nil
        self.isIndented = isIndented
        self.isEmphasized = isEmphasized
    }

    init(
        id: String,
        title: String,
        unit: String? = nil,
        value: String,
        secondaryValue: String?,
        isIndented: Bool = false,
        isEmphasized: Bool = false
    ) {
        self.id = id
        self.title = title
        self.unit = unit
        self.value = value
        self.secondaryValue = secondaryValue
        self.isIndented = isIndented
        self.isEmphasized = isEmphasized
    }
}

struct NutritionFactsTableCard: View {
    let headerTitle: String
    let secondaryHeaderTitle: String?
    let caloriesLabel: String
    let caloriesValue: String
    let secondaryCaloriesValue: String?
    let entries: [NutritionFactsEntry]
    let footnote: String?

    init(
        headerTitle: String,
        caloriesLabel: String,
        caloriesValue: String,
        entries: [NutritionFactsEntry],
        footnote: String? = nil
    ) {
        self.headerTitle = headerTitle
        self.secondaryHeaderTitle = nil
        self.caloriesLabel = caloriesLabel
        self.caloriesValue = caloriesValue
        self.secondaryCaloriesValue = nil
        self.entries = entries
        self.footnote = footnote
    }

    init(
        leftHeaderTitle: String,
        rightHeaderTitle: String,
        caloriesLabel: String,
        leftCaloriesValue: String,
        rightCaloriesValue: String,
        entries: [NutritionFactsEntry],
        footnote: String? = nil
    ) {
        self.headerTitle = leftHeaderTitle
        self.secondaryHeaderTitle = rightHeaderTitle
        self.caloriesLabel = caloriesLabel
        self.caloriesValue = leftCaloriesValue
        self.secondaryCaloriesValue = rightCaloriesValue
        self.entries = entries
        self.footnote = footnote
    }

    init(
        headerTitle: String,
        summary: NutritionSummary,
        caloriesLabel: String = NSLocalizedString("addmeal.total.calories", comment: "Calories title"),
        footnote: String? = nil
    ) {
        self.init(
            headerTitle: headerTitle,
            caloriesLabel: caloriesLabel,
            caloriesValue: String(summary.calories),
            entries: Self.summaryEntries(summary),
            footnote: footnote
        )
    }

    init(
        leftHeaderTitle: String,
        rightHeaderTitle: String,
        leftSummary: NutritionSummary,
        rightSummary: NutritionSummary,
        caloriesLabel: String = NSLocalizedString("addmeal.total.calories", comment: "Calories title"),
        footnote: String? = nil
    ) {
        self.init(
            leftHeaderTitle: leftHeaderTitle,
            rightHeaderTitle: rightHeaderTitle,
            caloriesLabel: caloriesLabel,
            leftCaloriesValue: String(leftSummary.calories),
            rightCaloriesValue: String(rightSummary.calories),
            entries: Self.summaryEntries(leftSummary, secondarySummary: rightSummary),
            footnote: footnote
        )
    }

    init(product: ProductSummary, footnote: String? = nil) {
        self.init(
            headerTitle: "100 \(product.per100UnitShortTitle)",
            caloriesLabel: NSLocalizedString("addmeal.total.calories", comment: "Calories title"),
            caloriesValue: String(product.caloriesPer100g),
            entries: Self.productEntries(product),
            footnote: footnote
        )
    }

    private var showsSecondaryColumn: Bool {
        secondaryHeaderTitle != nil || secondaryCaloriesValue != nil || entries.contains(where: { $0.secondaryValue != nil })
    }

    private var valueColumnWidth: CGFloat { 90 }
    private var secondaryColumnGapWidth: CGFloat { 17 }
    private var secondarySeparatorTrailingInset: CGFloat { valueColumnWidth + secondaryColumnGapWidth / 2 }

    private static func summaryEntries(_ summary: NutritionSummary, secondarySummary: NutritionSummary? = nil) -> [NutritionFactsEntry] {
        let gramsUnit = NSLocalizedString("unit.grams.short", comment: "Short grams unit")
        return [
            NutritionFactsEntry(
                id: "protein",
                title: NSLocalizedString("diary.protein", comment: "Protein label"),
                unit: gramsUnit,
                value: String(summary.protein),
                secondaryValue: secondarySummary.map { String($0.protein) }
            ),
            NutritionFactsEntry(
                id: "fat",
                title: NSLocalizedString("diary.fat", comment: "Fat label"),
                unit: gramsUnit,
                value: String(summary.fat),
                secondaryValue: secondarySummary.map { String($0.fat) }
            ),
            NutritionFactsEntry(
                id: "carbs",
                title: NSLocalizedString("diary.carbs", comment: "Carbs label"),
                unit: gramsUnit,
                value: String(summary.carbs),
                secondaryValue: secondarySummary.map { String($0.carbs) }
            )
        ]
    }

    private static func productEntries(_ product: ProductSummary) -> [NutritionFactsEntry] {
        var entries = summaryEntries(
            NutritionSummary(
                calories: product.caloriesPer100g,
                protein: product.proteinPer100g,
                fat: product.fatPer100g,
                carbs: product.carbsPer100g
            )
        )

        if product.saturatedFatPer100g > 0 {
            entries.insert(
                NutritionFactsEntry(
                    id: "saturated_fat",
                    title: NSLocalizedString("product.editor.nutrition.saturated_fat", comment: "Saturated fat title"),
                    unit: localizedNutritionUnit("g"),
                    value: nutritionFactsValueText(product.saturatedFatPer100g),
                    isIndented: true
                ),
                at: min(2, entries.count)
            )
        }

        if product.unsaturatedFatPer100g > 0 {
            let insertionIndex = min(product.saturatedFatPer100g > 0 ? 3 : 2, entries.count)
            entries.insert(
                NutritionFactsEntry(
                    id: "unsaturated_fat",
                    title: NSLocalizedString("product.editor.nutrition.unsaturated_fat", comment: "Unsaturated fat title"),
                    unit: localizedNutritionUnit("g"),
                    value: nutritionFactsValueText(product.unsaturatedFatPer100g),
                    isIndented: true
                ),
                at: insertionIndex
            )
        }

        if product.fiberPer100g > 0 {
            entries.append(
                NutritionFactsEntry(
                    id: "fiber",
                    title: NSLocalizedString("product.editor.nutrition.fiber", tableName: nil, bundle: .main, value: "Fiber", comment: "Fiber label"),
                    unit: localizedNutritionUnit("g"),
                    value: nutritionFactsValueText(product.fiberPer100g)
                )
            )
        }

        if product.sugarPer100g > 0 {
            entries.append(
                NutritionFactsEntry(
                    id: "sugar",
                    title: NSLocalizedString("product.editor.nutrition.sugar", tableName: nil, bundle: .main, value: "Sugar", comment: "Sugar label"),
                    unit: localizedNutritionUnit("g"),
                    value: nutritionFactsValueText(product.sugarPer100g)
                )
            )
        }

        if product.sodiumMgPer100g > 0 {
            entries.append(
                NutritionFactsEntry(
                    id: "sodium",
                    title: NSLocalizedString("product.editor.nutrition.sodium", tableName: nil, bundle: .main, value: "Sodium", comment: "Sodium label"),
                    unit: localizedNutritionUnit("mg"),
                    value: nutritionFactsValueText(product.sodiumMgPer100g)
                )
            )
        }

        entries.append(contentsOf: product.additionalNutrients.compactMap { nutrient in
            guard nutrient.amount > 0 else { return nil }
            let title = localizedNutritionTitle(code: nutrient.code, label: nutrient.label)
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

            return NutritionFactsEntry(
                id: nutrient.id,
                title: title,
                unit: localizedNutritionUnit(nutrient.unit),
                value: nutritionFactsValueText(nutrient.amount)
            )
        })

        return entries
    }

    private static func nutritionFactsValueText(_ value: Double) -> String {
        formattedFoodAmountValue(value, maximumFractionDigits: value < 10 ? 1 : 0)
    }

    private func titleText(for entry: NutritionFactsEntry) -> String {
        guard let unit = entry.unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty else {
            return entry.title
        }
        return "\(entry.title) (\(unit))"
    }

    private func numberText(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedValue.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 2 else { return trimmedValue }
        return components.dropLast().joined(separator: " ")
    }

    private func nutritionValue(_ value: String) -> some View {
        NutritionValueText(
            value: numberText(value),
            font: .body.weight(.semibold),
            color: .primary,
            numberMinWidth: 52,
            unitWidth: 0
        )
    }

    private func rowTitleFont(isEmphasized: Bool = false) -> Font {
        .system(size: 16, weight: isEmphasized ? .bold : .regular)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .trailing) {
                VStack(alignment: .leading, spacing: 0) {
                    if showsSecondaryColumn {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)

                            Text(headerTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: valueColumnWidth, alignment: .trailing)

                            Color.clear.frame(width: secondaryColumnGapWidth)

                            Text(secondaryHeaderTitle ?? "-")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: valueColumnWidth, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                    } else {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Text(headerTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                                .frame(minWidth: 72, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                    }

                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(caloriesLabel)
                            .font(rowTitleFont())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 0)

                        if showsSecondaryColumn {
                            HStack(spacing: 0) {
                                nutritionValue(caloriesValue)
                                    .frame(width: valueColumnWidth, alignment: .trailing)

                                Color.clear.frame(width: secondaryColumnGapWidth)

                                nutritionValue(secondaryCaloriesValue ?? "-")
                                    .frame(width: valueColumnWidth, alignment: .trailing)
                            }
                        } else {
                            nutritionValue(caloriesValue)
                        }
                    }
                    .padding(.vertical, 10)

                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)

                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(titleText(for: entry))
                                .font(rowTitleFont(isEmphasized: entry.isEmphasized))
                                .foregroundStyle(.primary)
                                .padding(.leading, entry.isIndented ? 14 : 0)

                            Spacer(minLength: 0)

                            if showsSecondaryColumn {
                                HStack(spacing: 0) {
                                    nutritionValue(entry.value)
                                        .frame(width: valueColumnWidth, alignment: .trailing)

                                    Color.clear.frame(width: secondaryColumnGapWidth)

                                    nutritionValue(entry.secondaryValue ?? "-")
                                        .frame(width: valueColumnWidth, alignment: .trailing)
                                }
                            } else {
                                nutritionValue(entry.value)
                            }
                        }
                        .padding(.vertical, 10)

                        if index < entries.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 1)
                        }
                    }
                }

                if showsSecondaryColumn {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1)
                        .padding(.trailing, secondarySeparatorTrailingInset)
                }
            }

            if let footnote, !footnote.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}
