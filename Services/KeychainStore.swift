import Foundation
import Security

/// API keys live here and nowhere else. The `Account` record persisted to
/// disk holds only an identifier that points into this store.
enum KeychainStore {
    private static let service = "ai.openquota.credentials"
    /// Pre-rename service name. The app's bundle ID did not change with the
    /// rename, so keys saved by the old build are still in this keychain —
    /// they are read from the legacy service and copied into the new one.
    private static let legacyService = "ai.openusage.credentials"

    @discardableResult
    static func save(_ secret: String, for id: UUID) -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]

        // Update in place first. Deleting then re-adding would lose the
        // existing credential if the add failed — a rotated key that does not
        // save is better left as the old key than gone entirely.
        let updated = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }

        var attributes = query
        attributes[kSecValueData as String] = data
        // Device-only so keys are never carried to another device by a backup.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func read(for id: UUID) -> String? {
        if let current = readRaw(service: service, id: id) { return current }
        // First run after the rename: the key sits under the old service
        // name. Copy it across so later reads (and the hint) come from here.
        guard let legacy = readRaw(service: legacyService, id: id) else { return nil }
        save(legacy, for: id)
        return legacy
    }

    private static func readRaw(service name: String, id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: name,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for id: UUID) {
        for name in [service, legacyService] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: name,
                kSecAttrAccount as String: id.uuidString,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    /// Last four characters, for confirming *which* key is connected without
    /// ever showing the key itself.
    static func hint(for id: UUID) -> String? {
        guard let key = read(for: id), key.count > 4 else { return nil }
        return "••••" + String(key.suffix(4))
    }
}
