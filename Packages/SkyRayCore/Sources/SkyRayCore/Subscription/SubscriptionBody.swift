import Foundation

public enum SubscriptionBody {
    /// The API body: base64 of newline-joined vless:// links. A plain-text body with links is accepted too.
    public static func decode(_ data: Data) -> [String] {
        guard let raw = String(data: data, encoding: .utf8) else { return [] }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("vless://") { return links(in: text) }
        guard let decoded = Base64Lenient.decodeString(text) else { return [] }
        return links(in: decoded)
    }

    static func links(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.lowercased().hasPrefix("vless://") }
    }
}
