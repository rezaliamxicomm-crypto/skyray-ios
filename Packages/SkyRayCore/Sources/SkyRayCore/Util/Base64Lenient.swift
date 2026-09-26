import Foundation

public enum Base64Lenient {
    /// Standard or URL-safe alphabet, whitespace anywhere, padding optional. nil when nothing decodes.
    public static func decode(_ text: String) -> Data? {
        var s = text.filter { !$0.isWhitespace }
        if s.isEmpty { return nil }
        s = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s = s.replacingOccurrences(of: "=", with: "")
        let pad = (4 - s.count % 4) % 4
        if pad == 3 { return nil }
        s += String(repeating: "=", count: pad)
        return Data(base64Encoded: s)
    }

    public static func decodeString(_ text: String) -> String? {
        guard let data = decode(text) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
