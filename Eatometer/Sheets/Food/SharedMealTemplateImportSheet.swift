import SwiftUI

struct SharedMealTemplateImportSheet: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    let shareReference: String
    let onImportComplete: (() -> Void)?

    @State private var preview: MealTemplateSummary?
    @State private var existingMealTemplate: MealTemplateSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                    Button(role: .close) { dismiss() }
                        .tint(.primary)
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
                identityCard(mealTemplate)
                itemsCard(mealTemplate)
                nutritionFactsCard(mealTemplate)
                statusSection
                importButtonSection
            }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func identityCard(_ mealTemplate: MealTemplateSummary) -> some View {
        EOCard {
            EOListRow(title: Text(verbatim: mealTemplate.title))
        }
    }

    private func itemsCard(_ mealTemplate: MealTemplateSummary) -> some View {
        EOCard {
            EOCardTitleRow(title: Text("mealtemplate.detail.items"))

            if mealTemplate.items.isEmpty {
                EORowSeparator()
                EOListRow(
                    title: Text("mealtemplate.detail.empty_items"),
                    titleColor: .secondary
                )
            } else {
                ForEach(mealTemplate.items) { item in
                    EORowSeparator()
                    EOListRow(
                        title: Text(verbatim: item.name),
                        subtitle: Text(verbatim: itemMetaText(item))
                    )
                }
            }
        }
    }

    private func nutritionFactsCard(_ mealTemplate: MealTemplateSummary) -> some View {
        let nutritionFactsTitle = NSLocalizedString(
            "nutrition.facts.title",
            tableName: nil,
            bundle: .main,
            value: "Nutrition Facts",
            comment: "Nutrition facts table title"
        )
        let caloriesUnit = NSLocalizedString("diary.kcal", comment: "Kilocalories")
        let gramsUnit = NSLocalizedString("unit.grams.short", comment: "Grams")

        return EOCard {
            EOCardTitleRow(title: Text(verbatim: nutritionFactsTitle))
            EORowSeparator()
            EOListRow(
                title: Text("addmeal.total.calories"),
                accessory: .value(Text(verbatim: "\(mealTemplate.calories) \(caloriesUnit)"))
            )
            EORowSeparator()
            EOListRow(
                title: Text("addmeal.total.protein"),
                accessory: .value(Text(verbatim: "\(mealTemplate.protein) \(gramsUnit)"))
            )
            EORowSeparator()
            EOListRow(
                title: Text("addmeal.total.carbs"),
                accessory: .value(Text(verbatim: "\(mealTemplate.carbs) \(gramsUnit)"))
            )
            EORowSeparator()
            EOListRow(
                title: Text("addmeal.total.fat"),
                accessory: .value(Text(verbatim: "\(mealTemplate.fat) \(gramsUnit)"))
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
                        .tint(Color.appAccentReadableText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                } else {
                    Label(importActionTitle, systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                        .foregroundStyle(Color.appAccentReadableText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
            }
            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func itemMetaText(_ item: MealItemEntry) -> String {
        let amountText = amountText(for: item)
        return "\(amountText) - \(item.calories)kc - \(item.protein)p - \(item.carbs)c - \(item.fat)f"
    }

    private func gramsText(_ value: Int) -> String {
        "\(value)"
    }
}
