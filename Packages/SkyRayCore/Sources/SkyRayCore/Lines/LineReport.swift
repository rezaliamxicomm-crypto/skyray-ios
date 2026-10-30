import Foundation

/// What Auto measured, for the box: the header X-Etha-Lines on the next subscription fetch (the API stores it as one
/// row of line_reports; the panel shows it — the customer sees no line name). The same shape as the Android app's
/// EthaReport:
///
///     v=1;t=<epoch s>;trig=<connect|first|auto|failover|manual|network|search>;use=<label>;sw=<0|1>;r=<kbps>;l=<label>:<ms>,<label>:-1,…
///
/// `r` (2.1): the best five-second download rate seen on the line in use during the pass, in kbps, when any (the passive
/// throughput figure for the box's ranking; a latency probe cannot see a slow line).
///
/// A label is the line's name without its "EthaVPN-" prefix (REALITY-relay-FRA9-443, XHTTP-api-CleanIP1-443); a line
/// named otherwise is left out. ms -1 = no answer. The header stays under 4 KB (at most 64 lines).
public enum LineReport {
    public static let prefix = "EthaVPN-"
    public static let maxLines = 64
    private static let label = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]{1,48}$")

    /// The line's label for the box, or nil when the line is not one of ours.
    public static func label(_ remark: String?) -> String? {
        guard let r = remark?.trimmingCharacters(in: .whitespaces), r.hasPrefix(prefix) else { return nil }
        let l = String(r.dropFirst(prefix.count))
        let range = NSRange(location: 0, length: (l as NSString).length)
        return label.firstMatch(in: l, range: range) != nil ? l : nil
    }

    /// The header. `results`: (remark, ms) in the subscription's order, -1 failed, 0 not measured (left out); nil when
    /// nothing measured was one of our lines.
    public static func build(now: Date, trigger: String, inUseRemark: String?, switched: Bool, results: [(String, Int64)], rateKbps: Int64 = 0) -> String? {
        var items: [String] = []
        for (remark, ms) in results {
            guard let l = label(remark), ms != 0 else { continue }
            items.append("\(l):\(ms < 0 ? -1 : ms)")
            if items.count == maxLines { break }
        }
        if items.isEmpty { return nil }
        let use = label(inUseRemark) ?? ""
        let rate = rateKbps > 0 ? ";r=\(rateKbps)" : ""
        return "v=1;t=\(Int64(now.timeIntervalSince1970));trig=\(trigger);use=\(use);sw=\(switched ? 1 : 0)\(rate);l=\(items.joined(separator: ","))"
    }

    /// One text for a set of lines: the same set → the same text, whatever their ids (the line's link without its name)
    /// and whatever Cloudflare's ECH configuration of the hour — the `ech=` value and the `echConfigList` inside an XHTTP
    /// line's `extra=` (its download leg) are left out, or every refresh after Cloudflare rotates it (about hourly)
    /// would count as new lines and restart the running core; a stale configuration is refreshed at the next Connect.
    public static func fingerprint(_ lines: [Line]) -> String {
        lines.map { line -> String in
            let link = line.link
            let bare = link.firstIndex(of: "#").map { String(link[..<$0]) } ?? link
            return stableLink(bare) + "#" + line.remark
        }.sorted().joined(separator: "|")
    }

    /// The link's query without its volatile parts: `ech=` dropped, `extra=` re-encoded with sorted keys and without
    /// `downloadSettings.tlsSettings.echConfigList`; anything unparseable is kept as it is.
    static func stableLink(_ link: String) -> String {
        guard let q = link.firstIndex(of: "?") else { return link }
        let base = String(link[..<q])
        let params = link[link.index(after: q)...].split(separator: "&", omittingEmptySubsequences: true).map(String.init)
        var kept: [String] = []
        for param in params {
            let key = param.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? param
            if key.lowercased() == "ech" { continue }
            if key.lowercased() == "extra", let eq = param.firstIndex(of: "=") {
                kept.append("extra=" + stableExtra(String(param[param.index(after: eq)...])))
                continue
            }
            kept.append(param)
        }
        return kept.isEmpty ? base : base + "?" + kept.joined(separator: "&")
    }

    private static func stableExtra(_ encoded: String) -> String {
        guard let json = encoded.removingPercentEncoding, let data = json.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return encoded }
        if var download = object["downloadSettings"] as? [String: Any] {
            if var tls = download["tlsSettings"] as? [String: Any] {
                tls.removeValue(forKey: "echConfigList")
                download["tlsSettings"] = tls
            }
            object["downloadSettings"] = download
        }
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: out, encoding: .utf8) else { return encoded }
        return text
    }
}
