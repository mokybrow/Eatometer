import SwiftUI

struct ProductDetailView: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    let productID: UUID
    let initialProduct: ProductSummary
    var showsDismissButton: Bool = false
    /// When false, hides the "+" menu that forks a global product into a
    /// personal/community copy. Used when the detail is opened from the
    /// add-to-meal picker, where creating a product copy is out of context.
    var allowsProductForking: Bool = true

    @State private var editingState: ProductEditorState?
    @State private var showsAdditionalNutrition = false
    @State private var sharePayload: FoodSharePayload?
    @State private var reviewSubmission: ProductSubmissionSummary?

    private struct NutrientDetail: Identifiable {
        let id: String
        let title: String
        let value: String
    }

    private var canManageProduct: Bool {
        catalogService.products.contains(where: { $0.id == productID })
    }

    private var product: ProductSummary {
        catalogService.productSummary(id: productID) ?? initialProduct
    }

    private var caloriesText: String {
        "\(product.caloriesPer100g) \(NSLocalizedString("diary.kcal", comment: "Calories suffix"))"
    }

    private var visibleReviewSubmission: ProductSubmissionSummary? {
        reviewSubmission ?? catalogService.cachedMyProductSubmission(for: productID)
    }

    private var aboutSectionTitle: String {
        NSLocalizedString(
            "product.detail.about",
            value: NSLocalizedString("today.stats.summary.title", comment: "Fallback product detail overview title"),
            comment: "Product detail overview section title"
        )
    }

    private var nutritionFactsTitle: String {
        NSLocalizedString(
            "nutrition.facts.title",
            tableName: nil,
            bundle: .main,
            value: "Nutrition Facts",
            comment: "Nutrition facts table title"
        )
    }

    private var servingSectionTitle: String {
        NSLocalizedString(
            "product.detail.serving_options",
            tableName: nil,
            bundle: .main,
            value: "Serving options",
            comment: "Product detail serving options section title"
        )
    }

    private var extraNutritionTitle: String {
        NSLocalizedString(
            "product.detail.extra_nutrients",
            tableName: nil,
            bundle: .main,
            value: "More nutrients",
            comment: "Collapsed product detail section title for extra nutrients"
        )
    }

    private var defaultServingBadgeTitle: String {
        NSLocalizedString(
            "product.detail.default_serving",
            tableName: nil,
            bundle: .main,
            value: "Default",
            comment: "Badge title for the default serving option"
        )
    }

    private var additionalNutritionRows: [NutrientDetail] {
        var rows: [NutrientDetail] = []

        if product.fiberPer100g > 0 {
            rows.append(
                NutrientDetail(
                    id: "fiber",
                        title: NSLocalizedString("product.editor.nutrition.fiber", tableName: nil, bundle: .main, value: "Fiber", comment: "Fiber label"),
                    value: nutrientText(product.fiberPer100g, unit: NSLocalizedString("unit.grams.short", comment: "Grams unit short title"))
                )
            )
        }

        if product.sugarPer100g > 0 {
            rows.append(
                NutrientDetail(
                    id: "sugar",
                        title: NSLocalizedString("product.editor.nutrition.sugar", tableName: nil, bundle: .main, value: "Sugar", comment: "Sugar label"),
                    value: nutrientText(product.sugarPer100g, unit: NSLocalizedString("unit.grams.short", comment: "Grams unit short title"))
                )
            )
        }

        if product.sodiumMgPer100g > 0 {
            rows.append(
                NutrientDetail(
                    id: "sodium",
                        title: NSLocalizedString("product.editor.nutrition.sodium", tableName: nil, bundle: .main, value: "Sodium", comment: "Sodium label"),
                    value: nutrientText(product.sodiumMgPer100g, unit: "mg")
                )
            )
        }

        rows.append(contentsOf: product.additionalNutrients.compactMap { nutrient in
            guard nutrient.amount > 0 else { return nil }
            let title = localizedNutritionTitle(code: nutrient.code, label: nutrient.label)
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NutrientDetail(
                id: nutrient.id,
                title: title,
                value: nutrientText(nutrient.amount, unit: nutrient.unit)
            )
        })

        return rows
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: EOTheme.Metrics.sectionSpacing) {
                identityCard
                servingOptionsCard
                nutritionFactsCard
            }
            .eoCardInsets()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .eoPageBackground()
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: productID) {
            await loadSharePayloadIfNeeded()
            _ = await catalogService.fetchProduct(id: productID)
            await loadReviewStatus()
        }
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if showsDismissButton {
                    if canManageProduct {
                        toolbarShareButton
                    }
                } else if allowsProductForking && !canManageProduct {
                    Menu {
                        Button {
                            editingState = personalCopyEditorState()
                        } label: {
                            Label("product.add.personal", systemImage: "person.fill")
                        }

                        Button {
                            editingState = communityCopyEditorState()
                        } label: {
                            Label("product.add.community", systemImage: "person.3.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(.primary)
                }

                if !showsDismissButton && canManageProduct {
                    toolbarShareButton

                    Menu {
                        Button("common.edit") {
                            editingState = ProductEditorState(draft: ProductDraft(summary: product), submissionContext: visibleReviewSubmission)
                        }
                        Button("common.delete", role: .destructive) {
                            deleteProduct()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.primary)
                }
            }
        }
        .sheet(item: $editingState, onDismiss: {
            Task {
                _ = await catalogService.fetchProduct(id: productID)
                await loadReviewStatus()
            }
        }) { state in
            ProductEditorSheet(state: state)
                .environmentObject(catalogService)
        }
    }

    private func deleteProduct() {
        Task {
            let success = await catalogService.deleteProduct(id: product.id)
            if success {
                await MainActor.run { dismiss() }
            }
        }
    }

    // MARK: - Cards (mock-up "Product Viewer" layout)

    private var identityCard: some View {
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

    private var servingOptionsCard: some View {
        EOCard {
            EOCardTitleRow(title: Text(verbatim: servingSectionTitle))

            ForEach(product.selectableServingOptions) { option in
                EORowSeparator()
                EOListRow(
                    title: Text(verbatim: option.displayTitle),
                    subtitle: option.metricDescription.map { Text(verbatim: $0) }
                )
            }
        }
    }

    private var nutritionFactsCard: some View {
        EOCard {
            EOCardTitleRow(title: Text(verbatim: nutritionFactsTitle))
            EORowSeparator()

            productNutritionRow(
                title: NSLocalizedString("addmeal.total.calories", comment: "Calories"),
                value: caloriesText
            )
            EORowSeparator()
            productNutritionRow(
                title: NSLocalizedString("addmeal.total.protein", comment: "Protein"),
                value: nutrientText(Double(product.proteinPer100g), unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            )
            EORowSeparator()
            productNutritionRow(
                title: NSLocalizedString("addmeal.total.carbs", comment: "Carbohydrates"),
                value: nutrientText(Double(product.carbsPer100g), unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            )
            EORowSeparator()
            productNutritionRow(
                title: NSLocalizedString("addmeal.total.fat", comment: "Fat"),
                value: nutrientText(Double(product.fatPer100g), unit: NSLocalizedString("unit.grams.short", comment: "Grams"))
            )
        }
    }

    private func toolbarIcon(_ systemName: String, color: Color = .primary) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .contentShape(Circle())
    }

    @ViewBuilder
    private var toolbarShareButton: some View {
        ShareMenuButton(
            title: product.name,
            card: .make(product: product),
            prepare: shareURL
        )
        .accessibilityLabel(Text("common.share"))
    }

    private func personalCopyEditorState() -> ProductEditorState {
        var draft = ProductDraft(summary: product)
        draft.productID = nil
        draft.visibility = .privateVisibility
        return ProductEditorState(
            draft: draft,
            visibilityOptions: [.privateVisibility, .friendsVisibility]
        )
    }

    private func communityCopyEditorState() -> ProductEditorState {
        var draft = ProductDraft(summary: product)
        draft.productID = nil
        draft.visibility = .publicVisibility
        return ProductEditorState(
            draft: draft,
            visibilityOptions: [.publicVisibility]
        )
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(Text(aboutSectionTitle))

            VStack(alignment: .leading, spacing: 0) {
                overviewDetailRow(
                    title: NSLocalizedString("product.editor.name", comment: "Product name"),
                    value: product.name,
                    valueFont: .body.weight(.semibold),
                    valueColor: .primary
                )

                if !product.brand.isEmpty {
                    overviewDivider
                    overviewDetailRow(
                        title: NSLocalizedString("product.editor.brand", comment: "Brand"),
                        value: product.brand,
                        valueFont: .body.weight(.semibold),
                        valueColor: .primary
                    )
                }

                if !product.details.isEmpty {
                    overviewDivider
                    overviewDetailRow(
                        title: NSLocalizedString("product.editor.description", comment: "Description"),
                        value: product.details,
                        valueFont: .body.weight(.semibold),
                        valueColor: .primary
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(Text(nutritionFactsTitle))

            NutritionFactsTableCard(product: product)
        }
    }

    private var servingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(Text(servingSectionTitle))

            VStack(spacing: 0) {
                ForEach(Array(product.resolvedServingOptions.enumerated()), id: \.element.id) { index, option in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(option.displayTitle)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }

                        Spacer(minLength: 0)

                        Text(option.metricDescription ?? "-")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)

                    if index < product.resolvedServingOptions.count - 1 {
                        nutritionDivider
                    }
                }
            }
            .padding(18)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
        }
    }

    private func sectionTitle(_ title: Text) -> some View {
        title
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 14)
    }

    private func overviewDetailRow(title: String, value: String, valueFont: Font, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text(value)
                .font(valueFont)
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nutritionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private func productNutritionRow(title: String, value: String) -> some View {
        EOListRow(
            title: Text(verbatim: title),
            accessory: .value(Text(verbatim: value))
        )
    }

    private func nutrientText(_ value: Double, unit: String) -> String {
        "\(formattedFoodAmountValue(value, maximumFractionDigits: value < 10 ? 1 : 0)) \(localizedNutritionUnit(unit))"
    }

    /// The link for this thing, made on demand and reused after the first time.
    ///
    /// Returns the URL rather than presenting anything: the screen is often a
    /// sheet, and a sheet cannot raise the share sheet — so the toolbar hands
    /// this to a `ShareLink` instead.
    @MainActor
    private func shareURL() async -> URL? {
        await loadSharePayloadIfNeeded()
        return sharePayload?.resolvedShareURL
    }

    @MainActor
    private func loadSharePayloadIfNeeded() async {
        guard sharePayload == nil else { return }
        guard canManageProduct else { return }
        guard let payload = await catalogService.shareUserProduct(id: productID) else { return }
        sharePayload = payload
    }

    private func loadReviewStatus() async {
        guard canManageProduct else {
            reviewSubmission = nil
            return
        }
        reviewSubmission = await catalogService.myProductSubmission(for: productID)
    }

    @ViewBuilder
    private func reviewStatusCard(_ submission: ProductSubmissionSummary) -> some View {
        let (titleKey, color, icon): (LocalizedStringKey, Color, String) = {
            switch submission.status {
            case .pending: return ("admin.submission.status.pending", .primary, "clock.badge")
            case .approved: return ("admin.submission.status.approved", .accentColor, "checkmark.seal.fill")
            case .rejected: return ("admin.submission.status.rejected", .red, "xmark.seal.fill")
            case .unknown: return ("admin.submission.status.unknown", .gray, "questionmark.circle")
            }
        }()
        let hasSubtitle = submission.status == .rejected && !submission.rejectionReason.isEmpty
        let iconBackground = submission.status == .pending ? Color.primary.opacity(0.08) : color.opacity(0.15)
        HStack(alignment: hasSubtitle ? .top : .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(iconBackground, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(titleKey)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
                if hasSubtitle {
                    Text(submission.rejectionReason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: EOTheme.Metrics.cardRadius, style: .continuous))
    }
}
