import SwiftUI

struct SharedUserProductImportSheet: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    let shareReference: String
    let onImportComplete: (() -> Void)?

    @State private var preview: ProductSummary?
    @State private var existingProduct: ProductSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var alreadyExistsMessage: String {
        NSLocalizedString(
            "product.import.already_exists",
            tableName: nil,
            bundle: .main,
            value: "You already have this product.",
            comment: "Shared product already imported"
        )
    }

    private var invalidLinkMessage: String {
        NSLocalizedString(
            "product.import.invalid_link",
            tableName: nil,
            bundle: .main,
            value: "Invalid product link",
            comment: "Invalid product share link message"
        )
    }

    private var importActionTitle: String {
        NSLocalizedString(
            "product.import.action",
            tableName: nil,
            bundle: .main,
            value: "Import",
            comment: "Import shared product button title"
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
            .navigationTitle("product.import.title")
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
            Text("product.import.loading")
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

    private func content(_ product: ProductSummary) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                identityCard(product)
                servingOptionsCard(product)
                nutritionFactsCard(product)
                statusSection
                importButtonSection
            }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func identityCard(_ product: ProductSummary) -> some View {
        EOCard {
            EOListRow(title: Text(verbatim: product.name))

            if !product.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EORowSeparator()
                EOListRow(title: Text(verbatim: product.brand))
            }

            EORowSeparator()
            EOListRow(
                title: Text("addmeal.unit"),
                accessory: .value(Text(verbatim: product.baseNutritionUnit.title))
            )

            if let barcode = product.barcode,
               !barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EORowSeparator()
                EOListRow(
                    title: Text("product.editor.barcode"),
                    accessory: .value(Text(verbatim: barcode))
                )
            }
        }
    }

    private func servingOptionsCard(_ product: ProductSummary) -> some View {
        EOCard {
            EOCardTitleRow(
                title: Text(
                    verbatim: NSLocalizedString(
                        "product.detail.serving_options",
                        tableName: nil,
                        bundle: .main,
                        value: "Serving options",
                        comment: "Product detail serving options section title"
                    )
                )
            )

            ForEach(product.selectableServingOptions) { option in
                EORowSeparator()
                EOListRow(
                    title: Text(verbatim: option.displayTitle),
                    subtitle: option.metricDescription.map { Text(verbatim: $0) }
                )
            }
        }
    }

    private func nutritionFactsCard(_ product: ProductSummary) -> some View {
        let nutritionFactsTitle = NSLocalizedString(
            "nutrition.facts.title",
            tableName: nil,
            bundle: .main,
            value: "Nutrition Facts",
            comment: "Nutrition facts table title"
        )
        let gramsUnit = NSLocalizedString("unit.grams.short", comment: "Grams")
        let caloriesUnit = NSLocalizedString("diary.kcal", comment: "Calories suffix")

        return EOCard {
            EOCardTitleRow(title: Text(verbatim: nutritionFactsTitle))
            EORowSeparator()
            EOListRow(
                title: Text("addmeal.total.calories"),
                accessory: .value(Text(verbatim: "\(product.caloriesPer100g) \(caloriesUnit)"))
            )
            EORowSeparator()
            EOListRow(
                title: Text("addmeal.total.protein"),
                accessory: .value(Text(verbatim: "\(product.proteinPer100g) \(gramsUnit)"))
            )
            EORowSeparator()
            EOListRow(
                title: Text("addmeal.total.carbs"),
                accessory: .value(Text(verbatim: "\(product.carbsPer100g) \(gramsUnit)"))
            )
            EORowSeparator()
            EOListRow(
                title: Text("addmeal.total.fat"),
                accessory: .value(Text(verbatim: "\(product.fatPer100g) \(gramsUnit)"))
            )
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if existingProduct != nil {
            Label(alreadyExistsMessage, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var importButtonSection: some View {
        if existingProduct == nil {
            EOPrimaryButton(
                title: Text(verbatim: importActionTitle),
                systemImage: "plus.circle.fill",
                isLoading: isLoading,
                fillsWidth: true,
                action: importProduct
            )
        }
    }

    private func loadPreview() {
        guard !shareReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = invalidLinkMessage
            return
        }

        isLoading = true
        existingProduct = nil
        Task {
            let product = await catalogService.previewSharedUserProduct(code: shareReference)
            await MainActor.run {
                isLoading = false
                preview = product
                existingProduct = product.flatMap(matchingExistingProduct)
                if product == nil {
                    errorMessage = catalogService.lastErrorMessage ?? invalidLinkMessage
                }
            }
        }
    }

    private func importProduct() {
        guard existingProduct == nil else { return }

        isLoading = true
        Task {
            let product = await catalogService.importSharedUserProduct(code: shareReference)
            await MainActor.run {
                isLoading = false
                if product != nil {
                    onImportComplete?()
                    dismiss()
                } else if catalogService.lastErrorMessage == alreadyExistsMessage {
                    existingProduct = preview
                } else {
                    errorMessage = catalogService.lastErrorMessage ?? invalidLinkMessage
                }
            }
        }
    }

    private func matchingExistingProduct(_ product: ProductSummary) -> ProductSummary? {
        let fingerprint = productFingerprint(product)
        return catalogService.products.first(where: { productFingerprint($0) == fingerprint })
    }

    private func productFingerprint(_ product: ProductSummary) -> String {
        [
            normalizedText(product.name),
            normalizedText(product.brand),
            String(product.caloriesPer100g),
            String(product.proteinPer100g),
            String(product.fatPer100g),
            String(product.carbsPer100g)
        ].joined(separator: "||")
    }

    private func normalizedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

}
