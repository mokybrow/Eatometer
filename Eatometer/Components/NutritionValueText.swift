import SwiftUI

func localizedNutritionUnit(_ rawUnit: String) -> String {
    let normalizedUnit = rawUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalizedUnit {
    case "g", "gram", "grams":
        return NSLocalizedString(
            "unit.grams.short",
            tableName: nil,
            bundle: .main,
            value: "g",
            comment: "Short grams unit"
        )
    case "mg", "milligram", "milligrams":
        return NSLocalizedString(
            "unit.milligrams.short",
            tableName: nil,
            bundle: .main,
            value: "mg",
            comment: "Short milligrams unit"
        )
    default:
        return rawUnit
    }
}

func localizedNutritionTitle(code: String, label: String) -> String {
    let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
    let lookupKey = trimmedCode.isEmpty ? trimmedLabel : trimmedCode
    let normalizedCode = lookupKey
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "-", with: "_")

    let fallback = trimmedLabel.isEmpty ? trimmedCode : trimmedLabel
    guard !normalizedCode.isEmpty else { return fallback }

    switch normalizedCode {
    case "saturated_fat", "saturated_fats", "saturatedfat", "saturates":
        return NSLocalizedString(
            "product.editor.nutrition.saturated_fat",
            tableName: nil,
            bundle: .main,
            value: fallback,
            comment: "Saturated fat title"
        )
    case "unsaturated_fat", "unsaturated_fats", "unsaturatedfat", "monounsaturated_fat", "polyunsaturated_fat":
        return NSLocalizedString(
            "product.editor.nutrition.unsaturated_fat",
            tableName: nil,
            bundle: .main,
            value: fallback,
            comment: "Unsaturated fat title"
        )
    default:
        break
    }

    return NSLocalizedString(
        "product.nutrient.\(normalizedCode)",
        tableName: nil,
        bundle: .main,
        value: fallback,
        comment: "Additional nutrient title"
    )
}

struct NutritionValueText: View {
    let value: String
    var font: Font = .body.weight(.semibold)
    var color: Color = .primary
    var numberMinWidth: CGFloat = 44
    var unitWidth: CGFloat = 24
    /// If set, overrides the detected unit (e.g. for calories)
    var explicitUnit: String? = nil

    private var parts: (number: String, unit: String?) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, trimmedValue != "-" else {
            return (trimmedValue, nil)
        }

        if let explicitUnit {
            return (trimmedValue, explicitUnit)
        }

        let components = trimmedValue.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 2, let unit = components.last else {
            return (trimmedValue, nil)
        }

        let number = components.dropLast().joined(separator: " ")
        return (number, localizedNutritionUnit(unit))
    }

    var body: some View {
        let resolvedParts = parts

        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(resolvedParts.number)
                .font(font)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: numberMinWidth, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)

            if let unit = resolvedParts.unit, !unit.isEmpty {
                Text(unit)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .frame(width: unitWidth, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .multilineTextAlignment(.trailing)
    }
}
