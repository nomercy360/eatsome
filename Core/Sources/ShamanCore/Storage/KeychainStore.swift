import Foundation
import Security

/// Device credentials live here rather than in UserDefaults.
///
/// The old provider keys remain readable so an installed build does not lose
/// them during migration, but recognition now uses the app-owned backend. The
/// device id generated on first launch preserves the source partition when an
/// account first adopts this install's local history.
public struct KeychainStore: Sendable {
    public let service: String

    /// The legacy service name preserves an API key saved by earlier builds.
    public init(service: String = "app.shaman.credentials") {
        self.service = service
    }

    public enum Key: String, Sendable {
        case openAIAPIKey = "openai.api_key"
        case geminiAPIKey = "gemini.api_key"
        /// Removed at launch by the first session-bearer build.
        case legacyBackendAPIToken = "backend.api_token"
        case deviceID = "backend.device_id"
        /// Opaque, server-minted, and the only thing that proves who you are.
        ///
        /// Deliberately beside the device id rather than replacing it: the id
        /// still names this install's own partition, and the two answer
        /// different questions — which copy of the app, and which person. It
        /// lives here for the same reason the device id does, so a reinstall
        /// that restores the Keychain stays signed in.
        case sessionToken = "backend.session_token"
    }

    public func set(_ value: String?, for key: Key) throws {
        guard let value, !value.isEmpty else { return try remove(key) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let insert = query.merging(attributes) { current, _ in current }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: status)
        }
    }

    public func get(_ key: Key) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    public func remove(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? {
        "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
    }
}
