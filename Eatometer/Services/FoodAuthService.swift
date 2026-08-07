import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import Security

@MainActor
final class FoodAuthService: ObservableObject {
    static let shared = FoodAuthService()

    static let appID = "eatometer-app"
    private static let requestedScopes: [String] = []
    private static let accessTokenKey = "Eatometer.auth.access_token"
    private static let refreshTokenKey = "Eatometer.auth.refresh_token"
    private static let displayNameKey = "Eatometer.auth.display_name"
    private static let refreshSkew: TimeInterval = 300

    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUsername = ""
    @Published private(set) var recentAccounts: [String] = []
    @Published private(set) var isSigningIn = false
    @Published var authenticationError: String?
    @Published var showProfile = false

    private let serverHost: String
    private let serverPort: Int
    private let useTLS: Bool
    private let userServerHost: String
    private let userServerPort: Int
    private let userUseTLS: Bool
    private var refreshTask: Task<Bool, Never>?
    private var bootstrapTask: Task<Bool, Never>?

    private init() {
        let authConfig = ConfigLoader.loadAuthAPIConfig()
        let userConfig = ConfigLoader.loadUserAPIConfig()
        serverHost = authConfig.host
        serverPort = authConfig.port
        useTLS = authConfig.useTLS
        userServerHost = userConfig.host
        userServerPort = userConfig.port
        userUseTLS = userConfig.useTLS
        currentUsername = UserDefaults.standard.string(forKey: Self.displayNameKey) ?? ""
        migrateLegacyTokens()
        isAuthenticated = accessToken != nil || refreshToken != nil
    }

    static func makeAppleNonce(length: Int = 32) -> String? {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func appleNonceHash(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func loginWithAppleNative(credential: ASAuthorizationAppleIDCredential, nonce: String) {
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty,
              !nonce.isEmpty else {
            authenticationError = String(localized: "Не удалось получить токен Apple ID")
            return
        }

        let name = PersonNameComponentsFormatter.localizedString(
            from: credential.fullName ?? PersonNameComponents(),
            style: .default,
            options: []
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        isSigningIn = true
        authenticationError = nil
        Task {
            defer { isSigningIn = false }
            do {
                let tokens = try await withAuthClient { client in
                    var request = Auth_SignInWithAppleRequest()
                    request.identityToken = identityToken
                    request.name = name
                    request.appID = Self.appID
                    request.requestedScopes = Self.requestedScopes
                    request.nonce = nonce
                    return try await client.signInWithApple(request, metadata: self.publicMetadata())
                }
                save(tokens: tokens, displayName: name)
            } catch {
                authenticationError = friendlyMessage(for: error)
            }
        }
    }

    func logout() {
        let token = refreshToken
        clearSession()
        guard let token else { return }
        Task {
            try? await withAuthClient { client in
                var request = Auth_LogoutRequest()
                request.refreshToken = token
                _ = try await client.logout(request, metadata: self.publicMetadata())
            }
        }
    }

    func bootstrapStoredSessionIfNeeded() async -> Bool {
        if let bootstrapTask { return await bootstrapTask.value }
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            if let token = self.accessToken, !self.isExpired(token, skew: Self.refreshSkew) {
                self.isAuthenticated = true
                return true
            }
            guard self.refreshToken != nil else {
                self.clearSession()
                return false
            }
            return await self.refreshAccessToken()
        }
        bootstrapTask = task
        defer { bootstrapTask = nil }
        return await task.value
    }

    func refreshAccessToken() async -> Bool {
        if let refreshTask { return await refreshTask.value }
        let task = Task<Bool, Never> { [weak self] in
            guard let self, let refreshToken = self.refreshToken else { return false }
            do {
                let tokens = try await self.withAuthClient { client in
                    var request = Auth_RefreshRequest()
                    request.refreshToken = refreshToken
                    request.appID = Self.appID
                    request.requestedScopes = Self.requestedScopes
                    return try await client.refresh(request, metadata: self.publicMetadata())
                }
                self.save(tokens: tokens, displayName: self.currentUsername)
                return true
            } catch {
                if self.isUnauthenticated(error) { self.clearSession() }
                return false
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return await task.value
    }

    func getAccessToken() -> String? { accessToken }

    func currentAppID() -> String? {
        guard let accessToken else { return nil }
        return claims(in: accessToken)["app_id"] as? String
    }

    func makeAuthMetadata() -> Metadata? {
        guard let accessToken else { return nil }
        var metadata: Metadata = [:]
        metadata.addString("Bearer \(accessToken)", forKey: "authorization")
        return metadata
    }

    func authorizedMetadata() async -> Metadata? {
        if let accessToken, !isExpired(accessToken, skew: Self.refreshSkew) {
            return makeAuthMetadata()
        }
        return await refreshAccessToken() ? makeAuthMetadata() : nil
    }

    func shouldRetryAuthorizedRequest(after error: Error) -> Bool { isUnauthenticated(error) }

    func withAuthorizedMetadata<T: Sendable>(
        _ operation: (Metadata) async throws -> T
    ) async throws -> T {
        guard let metadata = await authorizedMetadata() else { throw FoodAuthError.unauthenticated }
        do {
            return try await operation(metadata)
        } catch {
            guard isUnauthenticated(error), await refreshAccessToken(), let retry = makeAuthMetadata() else {
                throw error
            }
            return try await operation(retry)
        }
    }

    func withAuthorizedAccessToken<T: Sendable>(
        _ operation: (String) async throws -> T
    ) async throws -> T {
        try await withAuthorizedMetadata { _ in
            guard let token = self.accessToken else { throw FoodAuthError.unauthenticated }
            return try await operation(token)
        }
    }

    func initiateChangeEmail(newEmail: String) async -> Bool {
        await authenticatedBool { client, metadata in
            var request = Auth_InitiateChangeEmailRequest()
            request.newEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            return try await client.initiateChangeEmail(request, metadata: metadata).success
        }
    }

    func confirmChangeEmail(code: String) async -> Bool {
        await authenticatedBool { client, metadata in
            var request = Auth_ConfirmChangeEmailRequest()
            request.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
            return try await client.confirmChangeEmail(request, metadata: metadata).success
        }
    }

    private func authenticatedBool(
        _ operation: (Auth_AuthService.Client<HTTP2ClientTransport.Posix>, Metadata) async throws -> Bool
    ) async -> Bool {
        do {
            return try await withAuthorizedMetadata { metadata in
                try await self.withAuthClient { client in try await operation(client, metadata) }
            }
        } catch {
            return false
        }
    }

    func withUserClient<T: Sendable>(
        _ body: (User_UserService.Client<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T {
        try await GRPCCore.withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: userServerHost, port: userServerPort),
                transportSecurity: userUseTLS ? .tls : .plaintext
            )
        ) { client in
            try await body(User_UserService.Client(wrapping: client))
        }
    }

    private func withAuthClient<T: Sendable>(
        _ body: (Auth_AuthService.Client<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T {
        try await GRPCCore.withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: serverHost, port: serverPort),
                transportSecurity: useTLS ? .tls : .plaintext
            )
        ) { client in
            try await body(Auth_AuthService.Client(wrapping: client))
        }
    }

    private func publicMetadata() -> Metadata {
        var metadata: Metadata = [:]
        metadata.addString(Self.appID, forKey: "x-app-id")
        if let language = Locale.preferredLanguages.first {
            metadata.addString(language, forKey: "accept-language")
        }
        return metadata
    }

    private var accessToken: String? { KeychainStore.string(forKey: Self.accessTokenKey) }
    private var refreshToken: String? { KeychainStore.string(forKey: Self.refreshTokenKey) }

    private func save(tokens: Auth_TokenPair, displayName: String) {
        guard !tokens.accessToken.isEmpty, !tokens.refreshToken.isEmpty else {
            authenticationError = String(localized: "Сервис авторизации вернул пустой токен")
            return
        }
        guard KeychainStore.setString(tokens.accessToken, forKey: Self.accessTokenKey),
              KeychainStore.setString(tokens.refreshToken, forKey: Self.refreshTokenKey) else {
            authenticationError = String(localized: "Не удалось сохранить защищённую сессию")
            return
        }
        if !displayName.isEmpty {
            currentUsername = displayName
            UserDefaults.standard.set(displayName, forKey: Self.displayNameKey)
        }
        isAuthenticated = true
        authenticationError = nil
    }

    private func clearSession() {
        KeychainStore.removeValue(forKey: Self.accessTokenKey)
        KeychainStore.removeValue(forKey: Self.refreshTokenKey)
        isAuthenticated = false
        isSigningIn = false
        showProfile = false
    }

    private func migrateLegacyTokens() {
        for key in [Self.accessTokenKey, Self.refreshTokenKey] {
            if KeychainStore.string(forKey: key) == nil,
               let token = UserDefaults.standard.string(forKey: key), !token.isEmpty {
                KeychainStore.setString(token, forKey: key)
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func claims(in token: String) -> [String: Any] {
        let pieces = token.split(separator: ".")
        guard pieces.count > 1 else { return [:] }
        var base64 = String(pieces[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private func isExpired(_ token: String, skew: TimeInterval = 0) -> Bool {
        guard let expiry = claims(in: token)["exp"] as? TimeInterval else { return true }
        return Date().timeIntervalSince1970 + skew >= expiry
    }

    private func isUnauthenticated(_ error: Error) -> Bool {
        if let rpcError = error as? RPCError, rpcError.code == .unauthenticated { return true }
        let text = String(describing: error).lowercased()
        return text.contains("unauthenticated") || text.contains("token expired")
    }

    private func friendlyMessage(for error: Error) -> String {
        if isUnauthenticated(error) { return String(localized: "Apple ID не прошёл проверку") }
        return String(localized: "Не удалось войти. Проверьте соединение и попробуйте ещё раз.")
    }

    func updateCurrentUsername(_ value: String) {
        currentUsername = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum FoodAuthError: LocalizedError {
    case unauthenticated

    var errorDescription: String? {
        "Требуется вход"
    }
}
