import Foundation
import Security

/// This phone's code for the box, kept in the Keychain (3.0.0). identifierForVendor changes when the app is removed and put back,
/// so the box saw a reinstall as a new phone and counted it against the device limit. The code made on the first run is stored
/// here — on this device only (no iCloud sync), readable after the first unlock — and read back ever after: a reinstall is the
/// same phone. The value is the same hash DeviceCode made (the box already knows it); nothing else about the phone is kept.
enum DeviceCodeStore {
    private static let service = "com.allion.skyray.device"
    private static let account = "code"

    /// The kept code; else `fallback` stored and returned (nil when there is nothing to store). When the Keychain does not answer (before the
    /// first unlock, a transient error) nothing is written and this run uses the fallback — the upgrade's code is the same value anyway.
    static func code(fallback: String?) -> String? {
        switch read() {
        case .found(let kept): return kept
        case .missing:
            guard let fresh = fallback, !fresh.isEmpty else { return nil }
            write(fresh)
            return fresh
        case .unavailable: return fallback
        }
    }

    private enum Read { case found(String), missing, unavailable }

    private static func read() -> Read {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let data = out as? Data, let kept = String(data: data, encoding: .utf8), !kept.isEmpty else { return .unavailable }
        return .found(kept)
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
