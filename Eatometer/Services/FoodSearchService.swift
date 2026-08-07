import Foundation
import Combine
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf

@MainActor
final class FoodSearchService: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?

    private let authService: FoodAuthService
    private let serverHost: String
    private let serverPort: Int
    private let useTLS: Bool

    init(authService: FoodAuthService) {
        self.authService = authService

        let config = ConfigLoader.loadSearchAPIConfig()
        self.serverHost = config.host
        self.serverPort = config.port
        self.useTLS = config.useTLS
    }

    func searchProducts(query: String, limit: Int32 = 20, offset: Int32 = 0) async -> [Search_ProductSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            lastErrorMessage = nil
            return []
        }

        lastErrorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await withAuthenticatedMetadata { metadata in
                try await withSearchClient { client in
                    var request = Search_SearchProductsRequest()
                    request.query = normalized
                    request.limit = max(limit, 1)
                    request.offset = max(offset, 0)
                    return try await client.searchProducts(request, metadata: metadata)
                }
            }
            lastErrorMessage = nil
            return response.results
        } catch {
            storeLastError(error)
            return []
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
            || message.contains("не удалось авторизовать")
            || message.contains("cancelled")
            || message.contains("canceled")
            || message.contains("client stopped")
            || message.contains("can't make more rpcs")
            || message.contains("cant make more rpcs") {
            return true
        }

        return false
    }

    private func storeLastError(_ error: Error) {
        guard !shouldIgnoreError(error) else {
            lastErrorMessage = nil
            return
        }

        lastErrorMessage = NSLocalizedString("search.error", tableName: nil, bundle: .main, value: "Search error", comment: "Generic product search error")
    }

    private func withSearchClient<T>(
        _ body: (Search_SearchProductsService.Client<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T where T: Sendable {
        try await GRPCCore.withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: serverHost, port: serverPort),
                transportSecurity: useTLS ? .tls : .plaintext
            )
        ) { client in
            let searchClient = Search_SearchProductsService.Client(wrapping: client)
            return try await body(searchClient)
        }
    }

    private func withAuthenticatedMetadata<T>(
        _ operation: (Metadata) async throws -> T
    ) async throws -> T where T: Sendable {
        return try await authService.withAuthorizedMetadata(operation)
    }
}
