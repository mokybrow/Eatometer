import Foundation

enum CachedJSONStore {
    static func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    static func save<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func remove(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}