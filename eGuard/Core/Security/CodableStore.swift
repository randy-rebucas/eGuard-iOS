import Foundation

/// A small key-value store for Codable values. Implemented by the Keychain, protected files, and memory.
@MainActor
protocol CodableStore: AnyObject {
    func load<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T?
    func save<T: Encodable>(_ value: T, forKey key: String) throws
    func remove(forKey key: String) throws
    func removeAll() throws
}

/// Volatile storage for previews and UI tests.
final class InMemoryStore: CodableStore {
    private var storage: [String: Data] = [:]

    init() {}

    func load<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = storage[key] else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, forKey key: String) throws {
        storage[key] = try JSONEncoder().encode(value)
    }

    func remove(forKey key: String) throws {
        storage[key] = nil
    }

    func removeAll() throws {
        storage.removeAll()
    }
}
