import CryptoKit
import Foundation

/// This phone as a code for the box (2.1.2): the header X-Etha-Device on every fetch of our link. The first 16 hex digits of
/// SHA-256 over the install id (identifierForVendor) and the bundle id — the same for this install every time, another in
/// another app, never the id itself and nothing else about the phone. The box counts the phones a link is on, and tells two
/// phones' measurements apart in its ranking. The same shape as the Android app's EthaDevice.
public enum DeviceCode {
    /// Pure: the code for an install id and a bundle; nil when there is no id.
    public static func make(id: String?, bundle: String) -> String? {
        guard let v = id?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data("\(v):\(bundle)".utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
