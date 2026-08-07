import Foundation
import Security

struct KeychainStore {
    private static let service = "Eatometer.auth"

    static func string(forKey key: String) -> String? {
        readString(forKey: key, service: service)
    }

    private static func readString(forKey key: String, service: String) -> String? {
        var query = baseQuery(forKey: key, service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status != errSecSuccess && status != errSecItemNotFound {
            log(event: "read_failed", key: key, service: service, status: status)
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        log(event: trimmed.isEmpty ? "read_empty" : "read_success", key: key, service: service, status: status, tokenLength: trimmed.count)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    static func setString(_ value: String, forKey key: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else {
            log(event: "write_invalid_value", key: key)
            removeValue(forKey: key)
            return false
        }

        let query = baseQuery(forKey: key, service: service)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            log(event: "update_success", key: key, status: updateStatus, tokenLength: trimmed.count)
            return true
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        if updateStatus == errSecItemNotFound {
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            log(event: addStatus == errSecSuccess ? "add_success" : "add_failed", key: key, status: addStatus, tokenLength: trimmed.count)
            return addStatus == errSecSuccess
        }

        log(event: "update_failed_retrying_add", key: key, status: updateStatus, tokenLength: trimmed.count)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        log(event: deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound ? "delete_before_add_success" : "delete_before_add_failed", key: key, status: deleteStatus)
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        log(event: addStatus == errSecSuccess ? "add_after_delete_success" : "add_after_delete_failed", key: key, status: addStatus, tokenLength: trimmed.count)
        return addStatus == errSecSuccess
    }

    @discardableResult
    static func removeValue(forKey key: String) -> Bool {
        let status = SecItemDelete(baseQuery(forKey: key, service: service) as CFDictionary)
        log(event: status == errSecSuccess || status == errSecItemNotFound ? "remove_success" : "remove_failed", key: key, status: status)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(forKey key: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private static func log(event: String, key: String, service: String = service, status: OSStatus? = nil, tokenLength: Int? = nil) {
        var parts = ["service=\(service)", "key=\(key)"]
        if let status {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            parts.append("status=\(status)")
            parts.append("message=\(message)")
        }
        if let tokenLength {
            parts.append("len=\(tokenLength)")
        }
        print("KeychainStore \(event) \(parts.joined(separator: " "))")
    }
}
