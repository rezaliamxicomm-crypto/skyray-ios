import Foundation

/// The box's advice for this subscription's lines on the phone's network — the header X-Etha-Hint of the fetch (SkyRay
/// 2.1; the API's app/ranking.py), signed with the answer:
///
///     v=1;o=<label>,<label>,…;d=<label>,…;out=0|1;n=<phones>
///
/// `order`: the lines to try first, as the phones of this network found them (tiers of equals spread by the token);
/// `dead`: the lines nobody there reaches; `outage`: every phone of the network is failing on every line — "it is not
/// you"; `phones`: how many reported. Advice, never an order: the phone's own memory of the network wins where it has
/// one, the dead lines are probed last rather than skipped, and every line is verified by the phone's own probes.
public struct Hint: Equatable, Codable {
    public var order: [String] = []
    public var dead: Set<String> = []
    public var outage = false
    public var phones = 0

    public init() {}
    public init(order: [String], dead: Set<String>, outage: Bool, phones: Int) {
        self.order = order; self.dead = dead; self.outage = outage; self.phones = phones
    }

    public static let maxLength = 4096
    private static let label = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]{1,48}$")

    /// The header → the hint; nil when it is not one (another version, too long, no fields worth keeping).
    public static func parse(_ raw: String?) -> Hint? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty, raw.count <= maxLength else { return nil }
        var fields: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            fields[kv[0].trimmingCharacters(in: .whitespaces).lowercased()] = kv[1].trimmingCharacters(in: .whitespaces)
        }
        guard fields["v"] == "1" else { return nil }
        var h = Hint()
        h.order = labels(fields["o"])
        h.dead = Set(labels(fields["d"]))
        h.outage = fields["out"] == "1"
        h.phones = Int(fields["n"] ?? "") ?? 0
        return h.order.isEmpty && h.dead.isEmpty && !h.outage ? nil : h
    }

    private static func labels(_ list: String?) -> [String] {
        var out: [String] = []
        for item in (list ?? "").split(separator: ",") {
            let l = String(item).trimmingCharacters(in: .whitespaces)
            guard label.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) != nil, !out.contains(l) else { continue }
            out.append(l)
        }
        return out
    }

    /// `labels` (this subscription's, in its order) arranged by the hint: the advised order first, the rest in their
    /// own order, the dead last. A label the hint does not know keeps its place among the rest.
    public func arrange(_ labels: [String]) -> [String] {
        let advised = order.filter { labels.contains($0) && !dead.contains($0) }
        let rest = labels.filter { !advised.contains($0) && !dead.contains($0) }
        let last = labels.filter { dead.contains($0) }
        return advised + rest + last
    }
}
