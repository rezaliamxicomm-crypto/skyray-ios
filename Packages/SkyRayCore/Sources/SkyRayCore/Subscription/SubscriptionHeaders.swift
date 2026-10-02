import Foundation

/// The API's response headers, parsed the way the Android app parses them (EthaSubscription.kt).
public enum SubscriptionHeaders {
    public struct UserInfo: Equatable {
        public var upload: Int64 = -1
        public var download: Int64 = -1
        public var total: Int64 = -1
        public var expire: Int64 = -1
        public init() {}
    }

    /// "upload=0; download=1234; total=0; expire=0" → the four numbers (absent = -1); nil when nothing parses.
    public static func parseUserInfo(_ header: String?) -> UserInfo? {
        guard let header = header, !header.isEmpty else { return nil }
        var info = UserInfo(); var seen = false
        for part in header.split(whereSeparator: { $0 == ";" || $0 == "," }) {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, let value = Double(kv[1]) else { continue }
            let n = Int64(value)
            switch kv[0].lowercased() {
            case "upload": info.upload = n; seen = true
            case "download": info.download = n; seen = true
            case "total": info.total = n; seen = true
            case "expire": info.expire = n; seen = true
            default: continue
            }
        }
        return seen ? info : nil
    }

    /// "base64:…" is decoded; anything else is taken as it is, trimmed. Blank or undecodable → nil.
    public static func decodeHeaderText(_ value: String?) -> String? {
        guard let value = value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.lowercased().hasPrefix("base64:") {
            let payload = String(trimmed.dropFirst("base64:".count))
            guard let text = Base64Lenient.decodeString(payload) else { return nil }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return trimmed
    }

    /// Profile-Update-Interval is in hours; the app works in minutes with a floor.
    public static func updateIntervalMinutes(_ header: String?) -> Int64? {
        guard let header = header, let hours = Double(header.trimmingCharacters(in: .whitespaces)), hours > 0 else { return nil }
        return max(Int64(hours * 60), Etha.minUpdateMinutes)
    }

    /// nil = unknown, Int64.max = never, else whole days rounded up, never negative.
    public static func daysLeft(expire: Int64, now: Int64 = Int64(Date().timeIntervalSince1970)) -> Int64? {
        if expire < 0 { return nil }
        if expire == 0 { return Int64.max }
        let seconds = expire - now
        if seconds <= 0 { return 0 }
        return (seconds + 86399) / 86400
    }

    /// The allowance on the data tile: "120 GB", "70.2 GB" — one decimal, dropped when it would be ".0" (the used
    /// figure beside it keeps its decimal); under 1 GB whole MB, then KB. Android's EthaSubscription.quotaText.
    public static func quotaText(bytes: Int64) -> String {
        if bytes >= 1 << 30 {
            let tenths = (Double(bytes) / 1_073_741_824 * 10).rounded()
            let whole = tenths.truncatingRemainder(dividingBy: 10) == 0
            return String(format: whole ? "%.0f GB" : "%.1f GB", tenths / 10)
        }
        if bytes >= 1 << 20 { return String(format: "%.0f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }

    public static func isStale(_ fetchedAt: Date?, now: Date = Date(), maxAge: TimeInterval = Etha.staleAfter) -> Bool {
        guard let fetchedAt = fetchedAt, fetchedAt.timeIntervalSince1970 > 0 else { return true }
        return now.timeIntervalSince(fetchedAt) >= maxAge
    }

    /// Lower-cased header names. Returns true when any known header was present. An empty announce clears
    /// it; a garbage userinfo keeps the old numbers.
    @discardableResult
    public static func apply(_ headers: [String: String], to info: inout SubscriptionInfo, now: Date = Date()) -> Bool {
        var seen = false
        if let raw = headers["subscription-userinfo"] {
            seen = true
            if let ui = parseUserInfo(raw) {
                info.upload = ui.upload; info.download = ui.download; info.total = ui.total; info.expire = ui.expire
            }
        }
        if let raw = headers["profile-title"] { info.profileTitle = decodeHeaderText(raw); seen = true }
        if let raw = headers["announce"] { info.announce = decodeHeaderText(raw); seen = true }
        if let raw = headers["support-url"] {
            let t = raw.trimmingCharacters(in: .whitespaces); info.supportURL = t.isEmpty ? nil : t; seen = true
        }
        if let raw = headers["profile-web-page-url"] {
            let t = raw.trimmingCharacters(in: .whitespaces); info.webPageURL = t.isEmpty ? nil : t; seen = true
        }
        if let raw = headers["profile-update-interval"] {
            if let m = updateIntervalMinutes(raw) { info.updateIntervalMinutes = m }
            seen = true
        }
        if seen { info.infoUpdated = now }
        return seen
    }
}
