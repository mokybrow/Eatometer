import SwiftUI

struct SharedMealTemplateImportSheet: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let shareReference: String
    let onImportComplete: (() -> Void)?

    @State private var preview: MealTemplateSummary?
    @State private var existingMealTemplate: MealTemplateSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var importButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : .black
    }

    private var importButtonForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var importButtonBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }

    private var mealTemplateAlreadyExistsMessage: String {
        NSLocalizedString(
            "mealtemplate.import.already_exists",
            tableName: nil,
            bundle: .main,
            value: "You already have this ration.",
            comment: "Shared ration already imported"
        )
    }

    private var invalidLinkMessage: String {
        NSLocalizedString(
            "mealtemplate.import.invalid_link",
            tableName: nil,
            bundle: .main,
            value: "Invalid ration link",
            comment: "Invalid ration share link message"
        )
    }

    private var importFailedMessage: String {
        NSLocalizedString(
            "mealtemplate.import.failed",
            tableName: nil,
            bundle: .main,
            value: "Ration import failed",
            comment: "Ration import failed message"
        )
    }

    private var importActionTitle: String {
        NSLocalizedString(
            "mealtemplate.import.action",
            tableName: nil,
            bundle: .main,
            value: "Add to Library",
            comment: "Import shared ration button title"
        )
    }

    init(shareReference: String, onImportComplete: (() -> Void)? = nil) {
        self.shareReference = shareReference
        self.onImportComplete = onImportComplete
    }

    var body: some View {
        NavigationStack {
            Group {
                if let preview {
                    content(preview)
                } else if let errorMessage {
                    errorPlaceholder(errorMessage)
                } else {
                    loadingPlaceholder
                }
            }
            .background(Color.appPageBackground.ignoresSafeArea())
            .navigationTitle("mealtemplate.import.title")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: shareReference) {
                loadPreview()
            }

            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    PressableIconButton(action: { dismiss() }) {
                        Label("common.close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("mealtemplate.import.loading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func content(_ mealTemplate: MealTemplateSummary) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerSection(mealTemplate)
                itemsSection(mealTemplate)
                nutritionSection(mealTemplate)
                statusSection
                importButtonSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func headerSection(_ mealTemplate: MealTemplateSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mealTemplate.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !mealTemplate.details.isEmpty {
                Text(mealTemplate.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private func itemsSection(_ mealTemplate: MealTemplateSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("addmeal.section.items")

            VStack(spacing: 0) {
                ForEach(Array(mealTemplate.items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(amountText(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(format: NSLocalizedString("today.kcal_value", comment: "Calories value"), item.calories))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 12)

                    if index < mealTemplate.items.count - 1 {
                        divider
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private func nutritionSection(_ mealTemplate: MealTemplateSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("recipe.detail.nutrition")

            NutritionFactsTableCard(
                headerTitle: NSLocalizedString("addmeal.section.total", comment: "Total nutrition card title"),
                summary: NutritionSummary(
                    calories: mealTemplate.calories,
                    protein: mealTemplate.protein,
                    fat: mealTemplate.fat,
                    carbs: mealTemplate.carbs
                )
            )
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if existingMealTemplate != nil {
            Label(mealTemplateAlreadyExistsMessage, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var importButtonSection: some View {
        if existingMealTemplate == nil {
            PressableIconButton(disabled: isLoading, action: importMealTemplate) {
                if isLoading {
                    ProgressView()
                        .tint(importButtonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Label(importActionTitle, systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                        .foregroundStyle(importButtonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .background(importButtonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous)
                    .stroke(importButtonBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
            .opacity(isLoading ? 0.6 : 1)
        }
    }

    private func loadPreview() {
        guard !shareReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = invalidLinkMessage
            return
        }

        isLoading = true
        existingMealTemplate = nil
        Task {
            let mealTemplate = await catalogService.previewSharedMealTemplate(code: shareReference)
            await MainActor.run {
                isLoading = false
                preview = mealTemplate
                existingMealTemplate = mealTemplate.flatMap(matchingExistingMealTemplate)
                if mealTemplate == nil {
                    errorMessage = catalogService.lastErrorMessage ?? invalidLinkMessage
                }
            }
        }
    }

    private func importMealTemplate() {
        guard existingMealTemplate == nil else { return }

        isLoading = true
        Task {
            let mealTemplate = await catalogService.importSharedMealTemplate(code: shareReference)
            await MainActor.run {
                isLoading = false
                if mealTemplate != nil {
                    onImportComplete?()
                    dismiss()
                } else if catalogService.lastErrorMessage == mealTemplateAlreadyExistsMessage {
                    existingMealTemplate = preview
                } else {
                    onImportComplete?()
                    dismiss()
                }
            }
        }
    }

    private func matchingExistingMealTemplate(_ mealTemplate: MealTemplateSummary) -> MealTemplateSummary? {
        let fingerprint = mealTemplateFingerprint(mealTemplate)
        return catalogService.mealTemplates.first(where: { mealTemplateFingerprint($0) == fingerprint })
    }

    private func mealTemplateFingerprint(_ mealTemplate: MealTemplateSummary) -> String {
        let itemSignature = mealTemplate.items.map { item in
            [
                normalizedText(item.name),
                String(format: "%.3f", item.amount),
                item.unit.rawValue,
                normalizedText(item.servingLabel)
            ].joined(separator: "|")
        }.joined(separator: ";")

        return [
            normalizedText(mealTemplate.title),
            normalizedText(mealTemplate.details),
            String(mealTemplate.calories),
            String(mealTemplate.protein),
            String(mealTemplate.fat),
            String(mealTemplate.carbs),
            itemSignature
        ].joined(separator: "||")
    }

    private func normalizedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func amountText(for item: MealItemEntry) -> String {
        displayFoodQuantityText(
            amount: item.amount,
            unit: item.unit,
            servingLabel: item.servingLabel,
            product: catalogService.productSummary(for: item)
        )
    }

    private func nutritionComparisonRow(title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            NutritionValueText(value: value)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private func gramsText(_ value: Int) -> String {
        "\(value)"
    }
}
