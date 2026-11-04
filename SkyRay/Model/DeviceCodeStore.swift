import Foundation
import Security

/// This phone's code for the box, kept in the Keychain (3.0.0). identifierForVendor changes when the app is removed and put back,
/// so the box saw a reinstall as a new phone and counted it against the device limit. The code made on the first run is stored
/// here — on this device only (no iCloud sync), readable after the first unlock — and read back ever after: a reinstall is the
/// same phone. The value is the same hash DeviceCode made (the box already knows it); nothing else about the phone is kept.
enum DeviceCodeStore {
    private static let service = "com.allion.skyray.device"
    private static let account = "code"

    /// The kept code, else `fallback` stored and returned; nil when there is nothing to store.
    static func code(fallback: String?) -> String? {
        if let kept = read(), !kept.isEmpty { return kept }
        guard let fresh = fallback, !fresh.isEmpty else { return nil }
        write(fresh)
        return fresh
    }

    private static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
