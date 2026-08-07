import SwiftUI

struct AdminProductModerationView: View {
    @EnvironmentObject private var catalogService: FoodCatalogService

    @State private var submissions: [ProductSubmissionSummary] = []
    @State private var nextCursor = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if submissions.isEmpty && !isLoading {
                Section {
                    ContentUnavailableView(
                        "admin.submissions.empty",
                        systemImage: "checkmark.circle.fill",
                        description: Text("admin.submissions.empty.subtitle")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(submissions) { submission in
                        NavigationLink {
                            AdminProductSubmissionDetailView(submission: submission) {
                                await reloadSubmissions()
                            }
                        } label: {
                            submissionRow(submission)
                        }
                    }
                }
            }

            if !nextCursor.isEmpty {
                Section {
                    Button {
                        Task { await loadSubmissions(reset: false) }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("admin.submissions.load_more")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading)
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("admin.submissions.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reloadSubmissions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await loadSubmissions(reset: true) }
        .refreshable { await reloadSubmissions() }
        .overlay {
            if isLoading && submissions.isEmpty {
                ProgressView()
            }
        }
    }

    private func submissionRow(_ submission: ProductSubmissionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(submission.name.isEmpty ? NSLocalizedString("admin.submission.product", comment: "Product") : submission.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                statusBadge(submission.status)
            }

            if !submission.brand.isEmpty {
                Text(submission.brand)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if !submission.barcode.isEmpty {
                    Text(submission.barcode)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let createdAt = submission.createdAt {
                    Text(createdAt, style: .date)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func reloadSubmissions() async {
        await loadSubmissions(reset: true)
    }

    private func loadSubmissions(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let cursor = reset ? nil : nextCursor
        guard let page = await catalogService.listPendingProductSubmissions(limit: 50, cursor: cursor) else {
            errorMessage = catalogService.lastErrorMessage
            return
        }

        if reset {
            submissions = page.items
        } else {
            submissions.append(contentsOf: page.items)
        }
        nextCursor = page.nextCursor
    }

    private func statusBadge(_ status: ProductSubmissionSummary.Status) -> some View {
        let (key, color) = statusPresentation(status)
        return Text(LocalizedStringKey(key))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func statusPresentation(_ status: ProductSubmissionSummary.Status) -> (String, Color) {
        switch status {
        case .pending:
            return ("admin.submission.status.pending", .orange)
        case .approved:
            return ("admin.submission.status.approved", .green)
        case .rejected:
            return ("admin.submission.status.rejected", .red)
        case .unknown:
            return ("admin.submission.status.unknown", .gray)
        }
    }
}

private struct AdminProductSubmissionDetailView: View {
    @EnvironmentObject private var catalogService: FoodCatalogService
    @Environment(\.dismiss) private var dismiss

    let submission: ProductSubmissionSummary
    let onUpdated: () async -> Void

    @State private var rejectionReason = ""
    @State private var showRejectConfirmation = false
    @State private var isSaving = false
    @State private var savingAction: ModerationAction?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("admin.submission.product") {
                infoRow("admin.submission.product", value: submission.name)
                if !submission.brand.isEmpty {
                    infoRow("product.editor.brand", value: submission.brand)
                }
                if !submission.barcode.isEmpty {
                    infoRow("admin.submission.barcode", value: submission.barcode)
                }
                if !submission.barcodeFormat.isEmpty {
                    infoRow("submit_review.barcode.format", value: submission.barcodeFormat)
                }
                if !submission.details.isEmpty {
                    Text(submission.details)
                        .textSelection(.enabled)
                }
            }

            Section("admin.submission.user_values") {
                nutritionRow("addmeal.total.calories", value: "\(submission.caloriesPer100g) kcal")
                nutritionRow("addmeal.total.protein", value: grams(submission.proteinPer100g))
                nutritionRow("addmeal.total.fat", value: grams(submission.fatPer100g))
                nutritionRow("addmeal.total.carbs", value: grams(submission.carbsPer100g))
                nutritionRow("product.editor.nutrition.fiber", value: grams(submission.fiberPer100g))
                nutritionRow("product.editor.nutrition.sugar", value: grams(submission.sugarPer100g))
                nutritionRow("product.editor.nutrition.sodium", value: "\(number(submission.sodiumMgPer100g)) mg")
            }

            if hasOcrValues {
                Section("admin.submission.ocr_values") {
                    if submission.ocrCalories > 0 {
                        nutritionRow("addmeal.total.calories", value: "\(number(submission.ocrCalories)) kcal")
                    }
                    if submission.ocrProtein > 0 {
                        nutritionRow("addmeal.total.protein", value: grams(submission.ocrProtein))
                    }
                    if submission.ocrFat > 0 {
                        nutritionRow("addmeal.total.fat", value: grams(submission.ocrFat))
                    }
                    if submission.ocrCarbs > 0 {
                        nutritionRow("addmeal.total.carbs", value: grams(submission.ocrCarbs))
                    }
                    if !submission.ocrRawText.isEmpty {
                        Text(submission.ocrRawText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section(NSLocalizedString(
                "admin.submission.photos",
                tableName: nil,
                bundle: .main,
                value: "Photos",
                comment: "Product submission photos section title"
            )) {
                photoView(titleKey: "admin.submission.photo.nutrition", urlString: submission.nutritionPhotoURL)
                photoView(titleKey: "admin.submission.photo.barcode", urlString: submission.barcodePhotoURL)
                photoView(titleKey: "admin.submission.photo.package", urlString: submission.packagePhotoURL)
                if submission.nutritionPhotoURL.isEmpty,
                   submission.barcodePhotoURL.isEmpty,
                   submission.packagePhotoURL.isEmpty {
                    Text("admin.submission.no_photos")
                        .foregroundStyle(.secondary)
                }
            }

            Section("admin.submission.status") {
                infoRow("admin.submission.status", value: statusTitle(submission.status))
                if !submission.rejectionReason.isEmpty {
                    infoRow("admin.submission.reject_reason", value: submission.rejectionReason)
                }
            }

            if submission.status != .pending, let errorMessage, !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("admin.submission.title")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if submission.status == .pending {
                moderationActionsBar
            }
        }
        .alert("admin.submission.reject", isPresented: $showRejectConfirmation) {
            TextField("admin.submission.reject_reason.placeholder", text: $rejectionReason)
            Button("common.cancel", role: .cancel) { }
            Button("admin.submission.reject", role: .destructive) {
                Task { await reject() }
            }
            .disabled(rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("admin.submission.reject_reason")
        }
    }

    private enum ModerationAction {
        case approve
        case reject
    }

    private var moderationActionsBar: some View {
        VStack(spacing: 10) {
            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                PressableIconButton(disabled: isSaving, tintColor: .red, action: {
                    showRejectConfirmation = true
                }) {
                    Group {
                        if savingAction == .reject {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Label("admin.submission.reject", systemImage: "xmark.circle.fill")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }

                PressableIconButton(disabled: isSaving, tintColor: .green, action: {
                    Task { await approve() }
                }) {
                    Group {
                        if savingAction == .approve {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Label("admin.submission.approve", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private var hasOcrValues: Bool {
        submission.ocrCalories > 0
            || submission.ocrProtein > 0
            || submission.ocrFat > 0
            || submission.ocrCarbs > 0
            || !submission.ocrRawText.isEmpty
    }

    private func infoRow(_ titleKey: LocalizedStringKey, value: String) -> some View {
        LabeledContent {
            Text(value.isEmpty ? "-" : value)
                .textSelection(.enabled)
        } label: {
            Text(titleKey)
        }
    }

    private func nutritionRow(_ titleKey: LocalizedStringKey, value: String) -> some View {
        LabeledContent {
            Text(value)
                .monospacedDigit()
        } label: {
            Text(titleKey)
        }
    }

    @ViewBuilder
    private func photoView(titleKey: LocalizedStringKey, urlString: String) -> some View {
        if let url = URL(string: urlString), !urlString.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))

                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    case .failure:
                        ContentUnavailableView(titleKey, systemImage: "photo")
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 160)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
        }
    }

    private func approve() async {
        guard !isSaving else { return }
        isSaving = true
        savingAction = .approve
        errorMessage = nil
        defer {
            isSaving = false
            savingAction = nil
        }

        if await catalogService.approveProductSubmission(id: submission.id) != nil {
            await onUpdated()
            dismiss()
        } else {
            errorMessage = catalogService.lastErrorMessage ?? NSLocalizedString(
                "admin.submission.approve_failed",
                tableName: nil,
                bundle: .main,
                value: "Failed to approve submission.",
                comment: "Approve product submission failure"
            )
        }
    }

    private func reject() async {
        let reason = rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }
        guard !isSaving else { return }

        isSaving = true
        savingAction = .reject
        errorMessage = nil
        defer {
            isSaving = false
            savingAction = nil
        }

        if await catalogService.rejectProductSubmission(id: submission.id, reason: reason) != nil {
            await onUpdated()
            dismiss()
        } else {
            errorMessage = catalogService.lastErrorMessage
        }
    }

    private func statusTitle(_ status: ProductSubmissionSummary.Status) -> String {
        let key: String
        switch status {
        case .pending: key = "admin.submission.status.pending"
        case .approved: key = "admin.submission.status.approved"
        case .rejected: key = "admin.submission.status.rejected"
        case .unknown: key = "admin.submission.status.unknown"
        }
        return NSLocalizedString(key, comment: "Product submission status")
    }

    private func grams(_ value: Double) -> String {
        "\(number(value)) g"
    }

    private func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}
