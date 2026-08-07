import SwiftUI

struct SharedUserProductImportSheet: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let shareReference: String
    let onImportComplete: (() -> Void)?

    @State private var preview: ProductSummary?
    @State private var existingProduct: ProductSummary?
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
            value: "Add to Library",
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
                headerSection(product)
                nutritionSection(product)
                statusSection
                importButtonSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func headerSection(_ product: ProductSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !product.brand.isEmpty {
                Text(product.brand)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !product.details.isEmpty {
                Text(product.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }

    private func nutritionSection(_ product: ProductSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("product.detail.per_100g")

            NutritionFactsTableCard(product: product)
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
            PressableIconButton(disabled: isLoading, action: importProduct) {
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
        String(format: NSLocalizedString("recipe.grams_value", comment: "Grams value"), value)
    }

    private func gramsText(_ value: Double) -> String {
        String(format: NSLocalizedString("recipe.grams_value", comment: "Grams value"), Int(value.rounded()))
    }
}
