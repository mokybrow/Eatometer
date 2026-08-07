import Foundation
import Combine
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import SwiftProtobuf

// MARK: - Public DTOs surfaced to UI

struct ProductSubmissionSummary: Identifiable, Equatable {
    enum Status: String {
        case pending
        case approved
        case rejected
        case unknown
    }

    let id: String
    let userProductID: String
    let submittedByUserID: String
    var status: Status
    var name: String
    var brand: String
    var details: String
    var barcode: String
    var barcodeFormat: String
    var caloriesPer100g: Int
    var proteinPer100g: Double
    var fatPer100g: Double
    var saturatedFatPer100g: Double
    var unsaturatedFatPer100g: Double
    var carbsPer100g: Double
    var fiberPer100g: Double
    var sugarPer100g: Double
    var sodiumMgPer100g: Double
    var ocrCalories: Double
    var ocrProtein: Double
    var ocrFat: Double
    var ocrSaturatedFat: Double
    var ocrCarbs: Double
    var ocrRawText: String
    var nutritionPhotoKey: String
    var barcodePhotoKey: String
    var packagePhotoKey: String
    var nutritionPhotoURL: String
    var barcodePhotoURL: String
    var packagePhotoURL: String
    var rejectionReason: String
    var approvedProductID: String
    var reviewerUserID: String
    var reviewedAt: Date?
    var createdAt: Date?

    init(_ proto: Food_ProductSubmission) {
        self.id = proto.id
        self.userProductID = proto.userProductID
        self.submittedByUserID = proto.submittedByUserID
        self.status = Self.statusFromProto(proto.status)
        self.name = proto.name
        self.brand = proto.brand
        self.details = proto.description_p
        self.barcode = proto.barcode
        self.barcodeFormat = proto.barcodeFormat
        let facts = proto.per100G
        self.caloriesPer100g = Int(facts.calories.rounded())
        self.proteinPer100g = facts.protein
        self.fatPer100g = facts.fat
        self.saturatedFatPer100g = facts.saturatedFat
        self.unsaturatedFatPer100g = facts.unsaturatedFat
        self.carbsPer100g = facts.carbs
        self.fiberPer100g = facts.fiber
        self.sugarPer100g = facts.sugar
        self.sodiumMgPer100g = facts.sodiumMg
        let ocr = proto.ocrValues
        self.ocrCalories = ocr.calories
        self.ocrProtein = ocr.protein
        self.ocrFat = ocr.fat
        self.ocrSaturatedFat = ocr.saturatedFat
        self.ocrCarbs = ocr.carbs
        self.ocrRawText = ocr.rawText
        self.nutritionPhotoKey = proto.nutritionPhotoKey
        self.barcodePhotoKey = proto.barcodePhotoKey
        self.packagePhotoKey = proto.packagePhotoKey
        self.nutritionPhotoURL = proto.nutritionPhotoURL
        self.barcodePhotoURL = proto.barcodePhotoURL
        self.packagePhotoURL = proto.packagePhotoURL
        self.rejectionReason = proto.rejectionReason
        self.approvedProductID = proto.approvedProductID
        self.reviewerUserID = proto.reviewerUserID
        self.reviewedAt = proto.hasReviewedAt ? proto.reviewedAt.date : nil
        self.createdAt = proto.hasCreatedAt ? proto.createdAt.date : nil
    }

    private static func statusFromProto(_ status: Food_ProductSubmissionStatus) -> Status {
        switch status {
        case .pending: return .pending
        case .approved: return .approved
        case .rejected: return .rejected
        default: return .unknown
        }
    }
}

struct SubmissionUploadSlot {
    enum Kind {
        case nutrition
        case barcode
        case package
    }
    let kind: Kind
    let uploadURL: URL
    let objectKey: String
    let requiredHeaders: [String: String]
    let expiresAt: Date

    init?(_ proto: Food_SubmissionPhotoUploadSlot) {
        guard let url = URL(string: proto.uploadURL) else { return nil }
        self.uploadURL = url
        self.objectKey = proto.objectKey
        self.requiredHeaders = proto.requiredHeaders
        self.expiresAt = proto.hasExpiresAt ? proto.expiresAt.date : Date().addingTimeInterval(900)
        switch proto.kind {
        case .nutrition: self.kind = .nutrition
        case .barcode: self.kind = .barcode
        case .package: self.kind = .package
        default: return nil
        }
    }
}

struct ProductSubmissionPage {
    var items: [ProductSubmissionSummary]
    var nextCursor: String
}

// MARK: - FoodCatalogService extension

extension FoodCatalogService {

    func createSubmissionUploadURLs(
        photos: [(kind: SubmissionUploadSlot.Kind, contentType: String)]
    ) async -> [SubmissionUploadSlot] {
        guard authService != nil else { return [] }
        do {
            let response: Food_CreateSubmissionUploadURLsResponse = try await withAuthenticatedMetadata { metadata in
                var request = Food_CreateSubmissionUploadURLsRequest()
                request.photos = photos.map { entry in
                    var item = Food_SubmissionPhotoUploadRequest()
                    item.kind = Self.uploadKindToProto(entry.kind)
                    item.contentType = entry.contentType
                    return item
                }
                return try await self.withFoodClient { client in
                    try await client.createSubmissionUploadURLs(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return response.slots.compactMap(SubmissionUploadSlot.init)
        } catch {
            storeLastError(error)
            return []
        }
    }

    @discardableResult
    func uploadSubmissionPhoto(
        slot: SubmissionUploadSlot,
        data: Data,
        contentType: String
    ) async -> Bool {
        var request = URLRequest(url: slot.uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (k, v) in slot.requiredHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (_, response) = try await URLSession.shared.upload(for: request, from: data)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return true
            }
            return false
        } catch {
            storeLastError(error)
            return false
        }
    }

    func submitProductForReview(
        userProductID: UUID,
        nutritionPhotoKey: String,
        barcodePhotoKey: String?,
        packagePhotoKey: String?,
        barcode: String,
        barcodeFormat: String,
        ocrCalories: Double?,
        ocrProtein: Double?,
        ocrFat: Double?,
        ocrCarbs: Double?,
        ocrRawText: String?
    ) async -> ProductSubmissionSummary? {
        guard authService != nil else { return nil }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_SubmitProductForReviewRequest()
                request.userProductID = userProductID.uuidString
                request.nutritionPhotoKey = nutritionPhotoKey
                if let barcodePhotoKey { request.barcodePhotoKey = barcodePhotoKey }
                if let packagePhotoKey { request.packagePhotoKey = packagePhotoKey }
                request.barcode = barcode
                request.barcodeFormat = barcodeFormat
                var ocr = Food_SubmissionOcrValues()
                if let ocrCalories { ocr.calories = ocrCalories }
                if let ocrProtein { ocr.protein = ocrProtein }
                if let ocrFat { ocr.fat = ocrFat }
                if let ocrCarbs { ocr.carbs = ocrCarbs }
                if let ocrRawText { ocr.rawText = ocrRawText }
                request.ocrValues = ocr
                return try await self.withFoodClient { client in
                    try await client.submitProductForReview(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            let summary = ProductSubmissionSummary(response.submission)
            upsertMyProductSubmissionCache(with: summary)
            return summary
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func listMyProductSubmissions(
        statusFilter: ProductSubmissionSummary.Status? = nil,
        limit: Int32 = 50,
        forceRefresh: Bool = false
    ) async -> [ProductSubmissionSummary] {
        guard authService != nil else { return [] }
        if !forceRefresh,
           statusFilter == nil,
           limit == 50,
           let cachedAt = cachedMyProductSubmissionsAt,
           Date().timeIntervalSince(cachedAt) < Self.myProductSubmissionsCacheTTL {
            return cachedMyProductSubmissions
        }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ListMyProductSubmissionsRequest()
                if let statusFilter {
                    request.statusFilter = Self.statusToProto(statusFilter)
                }
                request.limit = limit
                return try await self.withFoodClient { client in
                    try await client.listMyProductSubmissions(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            let summaries = response.submissions.map(ProductSubmissionSummary.init)
            if statusFilter == nil && limit >= 50 {
                replaceMyProductSubmissionCache(with: summaries)
            }
            return summaries
        } catch {
            storeLastError(error)
            if statusFilter == nil && !cachedMyProductSubmissions.isEmpty {
                return cachedMyProductSubmissions
            }
            return []
        }
    }

    func myProductSubmission(for userProductID: UUID, forceRefresh: Bool = false) async -> ProductSubmissionSummary? {
        let normalizedUserProductID = userProductID.uuidString.lowercased()

        if !forceRefresh,
           let cachedAt = cachedMyProductSubmissionsAt,
           Date().timeIntervalSince(cachedAt) < Self.myProductSubmissionsCacheTTL {
            return latestSubmission(for: normalizedUserProductID, in: cachedMyProductSubmissions)
        }

        let submissions = await listMyProductSubmissions(forceRefresh: forceRefresh)
        return latestSubmission(for: normalizedUserProductID, in: submissions)
    }

    func cachedMyProductSubmission(for userProductID: UUID) -> ProductSubmissionSummary? {
        guard let cachedAt = cachedMyProductSubmissionsAt,
              Date().timeIntervalSince(cachedAt) < Self.myProductSubmissionsCacheTTL else {
            return nil
        }

        return latestSubmission(for: userProductID.uuidString.lowercased(), in: cachedMyProductSubmissions)
    }

    func listPendingProductSubmissions(
        limit: Int32 = 25,
        cursor: String? = nil
    ) async -> ProductSubmissionPage? {
        guard authService != nil else { return nil }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ListPendingProductSubmissionsRequest()
                request.limit = limit
                if let cursor { request.cursor = cursor }
                return try await self.withFoodClient { client in
                    try await client.listPendingProductSubmissions(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return ProductSubmissionPage(
                items: response.submissions.map(ProductSubmissionSummary.init),
                nextCursor: response.nextCursor
            )
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func getProductSubmission(id: String) async -> ProductSubmissionSummary? {
        guard authService != nil else { return nil }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_GetProductSubmissionRequest()
                request.submissionID = id
                return try await self.withFoodClient { client in
                    try await client.getProductSubmission(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            let summary = ProductSubmissionSummary(response.submission)
            upsertMyProductSubmissionCache(with: summary)
            return summary
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func approveProductSubmission(id: String) async -> ProductSubmissionSummary? {
        guard authService != nil else { return nil }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_ApproveProductSubmissionRequest()
                request.submissionID = id
                return try await self.withFoodClient { client in
                    try await client.approveProductSubmission(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            let summary = ProductSubmissionSummary(response.submission)
            upsertMyProductSubmissionCache(with: summary)
            return summary
        } catch {
            storeLastError(error)
            return nil
        }
    }

    func rejectProductSubmission(id: String, reason: String) async -> ProductSubmissionSummary? {
        guard authService != nil else { return nil }
        do {
            let response = try await withAuthenticatedMetadata { metadata in
                var request = Food_RejectProductSubmissionRequest()
                request.submissionID = id
                request.reason = reason
                return try await self.withFoodClient { client in
                    try await client.rejectProductSubmission(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            let summary = ProductSubmissionSummary(response.submission)
            upsertMyProductSubmissionCache(with: summary)
            return summary
        } catch {
            storeLastError(error)
            return nil
        }
    }

    private func latestSubmission(
        for normalizedUserProductID: String,
        in submissions: [ProductSubmissionSummary]
    ) -> ProductSubmissionSummary? {
        submissions
            .filter { $0.userProductID.lowercased() == normalizedUserProductID }
            .sorted { (lhs, rhs) in
                (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }
            .first
    }

    private func replaceMyProductSubmissionCache(with submissions: [ProductSubmissionSummary]) {
        cachedMyProductSubmissions = submissions
        cachedMyProductSubmissionsAt = Date()
    }

    private func upsertMyProductSubmissionCache(with submission: ProductSubmissionSummary) {
        cachedMyProductSubmissions.removeAll { $0.id == submission.id }
        cachedMyProductSubmissions.append(submission)
        cachedMyProductSubmissions.sort { (lhs, rhs) in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        cachedMyProductSubmissionsAt = Date()
    }

    private static func uploadKindToProto(_ kind: SubmissionUploadSlot.Kind) -> Food_SubmissionPhotoKind {
        switch kind {
        case .nutrition: return .nutrition
        case .barcode: return .barcode
        case .package: return .package
        }
    }

    private static func statusToProto(_ status: ProductSubmissionSummary.Status) -> Food_ProductSubmissionStatus {
        switch status {
        case .pending: return .pending
        case .approved: return .approved
        case .rejected: return .rejected
        case .unknown: return .unspecified
        }
    }
}
