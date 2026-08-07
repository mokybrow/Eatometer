import Combine
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import SwiftProtobuf

@MainActor
final class AdminService: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastSuccessMessage: String?

    private let authService: FoodAuthService?
    private let serverHost: String
    private let serverPort: Int
    private let useTLS: Bool

    init() {
        self.authService = nil
        self.serverHost = ""
        self.serverPort = 0
        self.useTLS = false
    }

    init(authService: FoodAuthService) {
        let config = ConfigLoader.loadAdminAPIConfig()
        self.authService = authService
        self.serverHost = config.host
        self.serverPort = config.port
        self.useTLS = config.useTLS
    }

    @discardableResult
    func sendNewsletter(subject: String, body: String, appID: String) async -> Int? {
        let normalizedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSubject.isEmpty, !normalizedBody.isEmpty, !normalizedAppID.isEmpty else {
            let error = NSError(
                domain: "AdminService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Newsletter subject, body and mailbox are required."]
            )
            storeLastError(error)
            return nil
        }

        isLoading = true
        lastErrorMessage = nil
        lastSuccessMessage = nil
        defer { isLoading = false }

        do {
            let response = try await performAuthorized { metadata in
                try await self.withAdminClient { client in
                    var request = Admin_SendNewsletterRequest()
                    request.subject = normalizedSubject
                    request.body = normalizedBody
                    request.appID = normalizedAppID
                    return try await client.sendNewsletter(request, metadata: metadata)
                }
            }
            let sent = Int(response.sent)
            lastSuccessMessage = "Newsletter sent to \(sent) users."
            return sent
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func sendNewsPush(title: String, body: String, newsText: String, appID: String) async -> Int? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNewsText = newsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTitle.isEmpty, !normalizedBody.isEmpty, !normalizedAppID.isEmpty else {
            let error = NSError(
                domain: "AdminService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Push title, body and audience are required."]
            )
            storeLastError(error)
            return nil
        }

        isLoading = true
        lastErrorMessage = nil
        lastSuccessMessage = nil
        defer { isLoading = false }

        do {
            let response = try await performAuthorized { metadata in
                try await self.withAdminClient { client in
                    var request = Admin_SendNewsPushRequest()
                    request.title = normalizedTitle
                    request.body = normalizedBody
                    request.newsText = normalizedNewsText
                    request.appID = normalizedAppID
                    return try await client.sendNewsPush(request, metadata: metadata)
                }
            }
            let sent = Int(response.sent)
            lastSuccessMessage = "News push sent to \(sent) users."
            return sent
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func listSupportRequests(appID: String, status: String, topic: String = "", limit: Int32 = 50, offset: Int32 = 0) async -> [Admin_SupportRequest]? {
        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await performAuthorized { metadata in
                try await self.withAdminClient { client in
                    var request = Admin_ListSupportRequestsRequest()
                    request.appID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
                    request.status = status.trimmingCharacters(in: .whitespacesAndNewlines)
                    request.topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
                    request.limit = limit
                    request.offset = offset
                    return try await client.listSupportRequests(request, metadata: metadata)
                }
            }
            return response.requests
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func replySupportRequest(id: String, subject: String, message: String, status: String) async -> Admin_SupportRequest? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, !normalizedSubject.isEmpty, !normalizedMessage.isEmpty else {
            let error = NSError(
                domain: "AdminService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Reply subject and message are required."]
            )
            storeLastError(error)
            return nil
        }

        isLoading = true
        lastErrorMessage = nil
        lastSuccessMessage = nil
        defer { isLoading = false }

        do {
            let response = try await performAuthorized { metadata in
                try await self.withAdminClient { client in
                    var request = Admin_ReplySupportRequestRequest()
                    request.id = normalizedID
                    request.subject = normalizedSubject
                    request.message = normalizedMessage
                    request.status = normalizedStatus
                    return try await client.replySupportRequest(request, metadata: metadata)
                }
            }
            lastSuccessMessage = "Support reply sent."
            return response.request
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func listUsers(
        query: String = "",
        role: String = "",
        bannedOnly: Bool = false,
        limit: Int32 = 50,
        offset: Int32 = 0
    ) async -> Admin_ListUsersResponse? {
        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await performAuthorized { metadata in
                try await self.withAdminClient { client in
                    var request = Admin_ListUsersRequest()
                    request.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    request.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
                    request.bannedOnly = bannedOnly
                    request.limit = limit
                    request.offset = offset
                    return try await client.listUsers(request, metadata: metadata)
                }
            }
            return response
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func banUser(id: String) async -> Admin_AdminUser? {
        await setUserBanState(id: id, banned: true)
    }

    @discardableResult
    func unbanUser(id: String) async -> Admin_AdminUser? {
        await setUserBanState(id: id, banned: false)
    }

    private func setUserBanState(id: String, banned: Bool) async -> Admin_AdminUser? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            let error = NSError(
                domain: "AdminService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "User ID is required."]
            )
            storeLastError(error)
            return nil
        }

        isLoading = true
        lastErrorMessage = nil
        lastSuccessMessage = nil
        defer { isLoading = false }

        do {
            let user = try await performAuthorized { metadata in
                try await self.withAdminClient { client in
                    if banned {
                        var request = Admin_BanUserRequest()
                        request.userID = normalizedID
                        let response = try await client.banUser(request, metadata: metadata)
                        return response.user
                    } else {
                        var request = Admin_UnbanUserRequest()
                        request.userID = normalizedID
                        let response = try await client.unbanUser(request, metadata: metadata)
                        return response.user
                    }
                }
            }
            lastSuccessMessage = banned ? "User banned." : "User unbanned."
            return user
        } catch {
            storeLastError(error)
            return nil
        }
    }

    private func withAdminClient<T>(
        _ body: (Admin_AdminService.Client<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T where T: Sendable {
        try await GRPCCore.withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: serverHost, port: serverPort),
                transportSecurity: useTLS ? .tls : .plaintext
            )
        ) { client in
            let adminClient = Admin_AdminService.Client(wrapping: client)
            return try await body(adminClient)
        }
    }

    private func isAuthError(_ error: Error) -> Bool {
        let desc = String(describing: error).lowercased()
        return desc.contains("unauthenticated")
            || desc.contains("invalid token")
            || desc.contains("expired")
            || desc.contains("invalid or expired")
    }

    private func performAuthorized<T>(
        _ operation: @escaping (Metadata) async throws -> T
    ) async throws -> T where T: Sendable {
        guard let authService else {
            throw NSError(
                domain: "AdminService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Admin service authorization failed."]
            )
        }

        var metadata = authService.makeAuthMetadata()
        if metadata == nil {
            let refreshed = await authService.refreshAccessToken()
            if refreshed {
                metadata = authService.makeAuthMetadata()
            }
        }

        guard let meta = metadata else {
            throw NSError(
                domain: "AdminService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No access token"]
            )
        }

        do {
            return try await operation(meta)
        } catch {
            if Task.isCancelled { throw error }

            if isAuthError(error) {
                let refreshed = await authService.refreshAccessToken()
                if refreshed, let retryMeta = authService.makeAuthMetadata() {
                    return try await operation(retryMeta)
                }
                throw NSError(
                    domain: "AdminService",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Token refresh failed"]
                )
            }
            throw error
        }
    }

    private func shouldIgnoreError(_ error: Error) -> Bool {
        if error is CancellationError || Task.isCancelled {
            return true
        }

        if let rpcError = error as? RPCError,
           rpcError.code == .cancelled || rpcError.code == .unauthenticated {
            return true
        }

        let nsError = error as NSError
        let message = String(describing: error).lowercased()
        if (nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue)
            || nsError.code == 401
            || message.contains("unauthenticated")
            || message.contains("cancelled")
            || message.contains("canceled")
            || message.contains("client stopped") {
            return true
        }

        return false
    }

    private func storeLastError(_ error: Error) {
        guard !shouldIgnoreError(error) else {
            lastErrorMessage = nil
            return
        }

        lastSuccessMessage = nil
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastErrorMessage = description
            return
        }

        let nsError = error as NSError
        if let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastErrorMessage = description
            return
        }

        lastErrorMessage = String(describing: error)
    }

    // MARK: - Product Moderation

    @discardableResult
    func listPendingProductSubmissions(limit: Int32 = 50, cursor: String = "") async -> [Food_ProductSubmission]? {
        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await performAuthorized { metadata in
                try await self.withFoodClient { client in
                    var request = Food_ListPendingProductSubmissionsRequest()
                    request.limit = limit
                    request.cursor = cursor
                    return try await client.listPendingProductSubmissions(request, metadata: metadata)
                }
            }
            return response.submissions
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func getProductSubmission(id: String) async -> Food_ProductSubmission? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            let error = NSError(
                domain: "AdminService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Submission ID is required."]
            )
            storeLastError(error)
            return nil
        }

        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await performAuthorized { metadata in
                try await self.withFoodClient { client in
                    var request = Food_GetProductSubmissionRequest()
                    request.submissionID = normalizedID
                    return try await client.getProductSubmission(request, metadata: metadata)
                }
            }
            return response.submission
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func approveProductSubmission(id: String) async -> (submission: Food_ProductSubmission?, product: Food_Product?)? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            let error = NSError(
                domain: "AdminService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Submission ID is required."]
            )
            storeLastError(error)
            return nil
        }

        isLoading = true
        lastErrorMessage = nil
        lastSuccessMessage = nil
        defer { isLoading = false }

        do {
            let response = try await performAuthorized { metadata in
                try await self.withFoodClient { client in
                    var request = Food_ApproveProductSubmissionRequest()
                    request.submissionID = normalizedID
                    return try await client.approveProductSubmission(request, metadata: metadata)
                }
            }
            lastSuccessMessage = "Product submission approved successfully."
            return (submission: response.submission, product: response.product)
        } catch {
            storeLastError(error)
            return nil
        }
    }

    @discardableResult
    func rejectProductSubmission(id: String, reason: String) async -> Food_ProductSubmission? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, !normalizedReason.isEmpty else {
            let error = NSError(
                domain: "AdminService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Submission ID and rejection reason are required."]
            )
            storeLastError(error)
            return nil
        }

        isLoading = true
        lastErrorMessage = nil
        lastSuccessMessage = nil
        defer { isLoading = false }

        do {
            let response = try await performAuthorized { metadata in
                try await self.withFoodClient { client in
                    var request = Food_RejectProductSubmissionRequest()
                    request.submissionID = normalizedID
                    request.reason = normalizedReason
                    return try await client.rejectProductSubmission(request, metadata: metadata)
                }
            }
            lastSuccessMessage = "Product submission rejected."
            return response.submission
        } catch {
            storeLastError(error)
            return nil
        }
    }

    private func withFoodClient<T>(
        _ body: (Food_FoodService.Client<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T where T: Sendable {
        try await GRPCCore.withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: serverHost, port: serverPort),
                transportSecurity: useTLS ? .tls : .plaintext
            )
        ) { client in
            let foodClient = Food_FoodService.Client(wrapping: client)
            return try await body(foodClient)
        }
    }
}
