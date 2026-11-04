import Foundation

/// One country the box offers (the Servers box, 3.0.0): the header X-Etha-Exits, `code|name|country|state|rtt|probe;…`.
/// `probe` is the address the app measures the country through (the box itself for the default, a card's for an exit).
public struct Exit: Codable, Equatable, Identifiable {
    public let code: String
    public let name: String
    public let country: String
    public let state: String          // ok | down | off
    public let rtt: Int               // the box's own round trip to the card, ms (0 for the box itself)
    public let probe: String
    public var id: String { code }
    /// A second hop (a card), not the box itself.
    public var routed: Bool { !probe.isEmpty && probe != Etha.probeBoxIP }
    public var ok: Bool { state == "ok" }
    public init(code: String, name: String, country: String, state: String, rtt: Int, probe: String) {
        self.code = code; self.name = name; self.country = country; self.state = state; self.rtt = rtt; self.probe = probe
    }
}

/// The pure parts of the Servers box, the same shape as the Android app's Exits: the header, the flags, the lowest app
/// version (X-Etha-App-Min), the device limit's refusal.
public enum Exits {
    static let code = try! NSRegularExpression(pattern: "^[a-z]{2}[a-z0-9]{0,6}$")

    /// The header's value → the countries in the box's order; a bad item is skipped.
    public static func parse(_ raw: String?) -> [Exit] {
        guard let raw = raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var out: [Exit] = []
        for item in raw.split(separator: ";", omittingEmptySubsequences: true) {
            let f = item.trimmingCharacters(in: .whitespaces).components(separatedBy: "|")
            guard f.count >= 5, code.firstMatch(in: f[0], range: NSRange(f[0].startIndex..., in: f[0])) != nil else { continue }
            let name = f[1].trimmingCharacters(in: .whitespaces)
            out.append(Exit(code: f[0], name: name.isEmpty ? f[0] : name, country: String(f[2].trimmingCharacters(in: .whitespaces).uppercased().prefix(2)),
                            state: f[3].trimmingCharacters(in: .whitespaces).lowercased(), rtt: Int(f[4].trimmingCharacters(in: .whitespaces)) ?? 0,
                            probe: f.count > 5 ? f[5].trimmingCharacters(in: .whitespaces) : ""))
        }
        return out
    }

    /// A two-letter country as its flag (regional indicators: "US" → 🇺🇸); the globe for anything else.
    public static func flag(_ country: String) -> String {
        let c = country.trimmingCharacters(in: .whitespaces).uppercased()
        guard c.count == 2, c.allSatisfy({ $0 >= "A" && $0 <= "Z" }) else { return "\u{1F310}" }
        return String(c.unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }.map { Character($0) })
    }

    /// `android=3.0.0;ios=3.0.0` → this platform's lowest version, nil when none.
    public static func minVersion(_ raw: String?, platform: String = "ios") -> String? {
        guard let raw = raw else { return nil }
        for part in raw.split(separator: ";") {
            let kv = part.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
            guard kv.count == 2, kv[0] == platform else { continue }
            let v = kv[1].trimmingCharacters(in: .whitespaces)
            if v.range(of: "^\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil { return v }
        }
        return nil
    }

    /// Numeric, dot-separated: `version` below `min` (a missing part counts as 0).
    public static func isBelow(_ version: String, min: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "v", with: "").split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let a = parts(version), b = parts(min)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// The device limit's signed 403 body (`{"detail":"devices","limit":2,"active":3}`) → (limit, active); nil for any other body.
    public static func devicesRefusal(_ body: String) -> (limit: Int, active: Int)? {
        guard body.range(of: "\"detail\"\\s*:\\s*\"devices\"", options: .regularExpression) != nil else { return nil }
        func number(_ key: String) -> Int {
            guard let r = body.range(of: "\"\(key)\"\\s*:\\s*(\\d+)", options: .regularExpression) else { return 0 }
            return Int(body[r].split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        }
        return (number("limit"), number("active"))
    }
}
