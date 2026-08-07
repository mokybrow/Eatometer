import Foundation

struct ServiceConfig {
    let host: String
    let port: Int
    let useTLS: Bool
}

enum ConfigLoader {
    private static let defaultOAuthCallbackScheme = "eatometer"

    private static func intFromEnvOrAny(_ envKey: String, _ bundleVal: Any?) -> Int? {
        if let env = ProcessInfo.processInfo.environment[envKey], let value = Int(env) { return value }
        if let intValue = bundleVal as? Int { return intValue }
        if let stringValue = bundleVal as? String, let value = Int(stringValue) { return value }
        if let numberValue = bundleVal as? NSNumber { return numberValue.intValue }
        return nil
    }

    private static func stringFromEnvOrAny(_ envKey: String, _ bundleVal: Any?) -> String? {
        if let env = ProcessInfo.processInfo.environment[envKey], !env.isEmpty { return env }
        if let stringValue = bundleVal as? String, !stringValue.isEmpty { return stringValue }
        return nil
    }

    private static func isValidURLScheme(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-."))
        return CharacterSet.letters.contains(first)
            && value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func normalizeOAuthCallbackScheme(_ raw: String?) -> String {
        guard let raw else { return defaultOAuthCallbackScheme }

        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { return defaultOAuthCallbackScheme }

        if candidate.contains("://"), let parsedScheme = URLComponents(string: candidate)?.scheme {
            candidate = parsedScheme
        } else if let colonIndex = candidate.firstIndex(of: ":") {
            candidate = String(candidate[..<colonIndex])
        }

        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard isValidURLScheme(candidate) else {
            print("Invalid AUTH_CALLBACK_SCHEME value: \(raw). Falling back to \(defaultOAuthCallbackScheme)")
            return defaultOAuthCallbackScheme
        }

        return candidate
    }

    private static func parseServiceURL(_ raw: String, defaultPort: Int? = nil) -> ServiceConfig? {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { return nil }

        func components(from string: String) -> URLComponents? {
            URLComponents(string: string)
        }

        var comps: URLComponents? = components(from: candidate)
        if comps?.host == nil {
            comps = components(from: "https://\(candidate)")
            if comps?.host == nil {
                comps = components(from: "http://\(candidate)")
            }
        }

        if let comps, let host = comps.host {
            let scheme = comps.scheme?.lowercased()
            let useTLS = (scheme == "https") || (scheme == nil && defaultPort == 443)
            let port = comps.port ?? (useTLS ? 443 : (defaultPort ?? 80))
            return ServiceConfig(host: host, port: port, useTLS: useTLS)
        }

        if candidate.contains(":") {
            let parts = candidate.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let port = Int(parts[1]) {
                return ServiceConfig(host: parts[0], port: port, useTLS: false)
            }
        }

        return nil
    }

    static func loadAuthAPIConfig() -> ServiceConfig {
        let urlBundle = Bundle.main.object(forInfoDictionaryKey: "AUTH_API_URL")
        if let urlString = stringFromEnvOrAny("AUTH_API_URL", urlBundle), let parsed = parseServiceURL(urlString) {
            return parsed
        }
        preconditionFailure("AUTH_API_URL must be set in Info.plist or environment")
    }

    static func loadFoodAPIConfig() -> ServiceConfig {
        let urlBundle = Bundle.main.object(forInfoDictionaryKey: "FOOD_API_URL")
        if let urlString = stringFromEnvOrAny("FOOD_API_URL", urlBundle), let parsed = parseServiceURL(urlString) {
            return parsed
        }
        preconditionFailure("FOOD_API_URL must be set in Info.plist or environment")
    }

    static func loadSearchAPIConfig() -> ServiceConfig {
        let urlBundle = Bundle.main.object(forInfoDictionaryKey: "SEARCH_API_URL")
        if let urlString = stringFromEnvOrAny("SEARCH_API_URL", urlBundle), let parsed = parseServiceURL(urlString) {
            return parsed
        }
        preconditionFailure("SEARCH_API_URL must be set in Info.plist or environment")
    }

    static func loadUserAPIConfig() -> ServiceConfig {
        let urlBundle = Bundle.main.object(forInfoDictionaryKey: "USER_API_URL")
        if let urlString = stringFromEnvOrAny("USER_API_URL", urlBundle), let parsed = parseServiceURL(urlString) {
            return parsed
        }
        preconditionFailure("USER_API_URL must be set in Info.plist or environment")
    }

    static func loadAdminAPIConfig() -> ServiceConfig {
        let urlBundle = Bundle.main.object(forInfoDictionaryKey: "ADMIN_API_URL")
        if let urlString = stringFromEnvOrAny("ADMIN_API_URL", urlBundle), let parsed = parseServiceURL(urlString) {
            return parsed
        }
        preconditionFailure("ADMIN_API_URL must be set in Info.plist or environment")
    }

    static func loadOAuthConfig() -> (serverBaseURL: String, callbackScheme: String) {
        let urlBundle = Bundle.main.object(forInfoDictionaryKey: "AUTH_SERVER_BASE_URL")
        let schemeBundle = Bundle.main.object(forInfoDictionaryKey: "AUTH_CALLBACK_SCHEME")
        let rawScheme = stringFromEnvOrAny("AUTH_CALLBACK_SCHEME", schemeBundle) ?? (schemeBundle as? String)
        let scheme = normalizeOAuthCallbackScheme(rawScheme)

        if let urlString = stringFromEnvOrAny("AUTH_SERVER_BASE_URL", urlBundle) {
            return (serverBaseURL: urlString, callbackScheme: scheme)
        }

        return (serverBaseURL: "http://localhost:8080", callbackScheme: scheme)
    }

    static func grpcAuthoritySummary() -> String {
        let auth = loadAuthAPIConfig()
        let user = loadUserAPIConfig()
        let food = loadFoodAPIConfig()
        let search = loadSearchAPIConfig()
        return "auth=\(auth.host):\(auth.port), user=\(user.host):\(user.port), food=\(food.host):\(food.port), search=\(search.host):\(search.port)"
    }

    static func boolFlag(_ envKey: String, defaultValue: Bool = false) -> Bool {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: envKey)
        if let env = ProcessInfo.processInfo.environment[envKey] {
            return ["1", "true", "yes"].contains(env.lowercased())
        }
        if let value = bundleValue as? Bool {
            return value
        }
        if let string = bundleValue as? String {
            return ["1", "true", "yes"].contains(string.lowercased())
        }
        return defaultValue
    }

    static func intValue(_ envKey: String, defaultValue: Int) -> Int {
        intFromEnvOrAny(envKey, Bundle.main.object(forInfoDictionaryKey: envKey)) ?? defaultValue
    }
}
