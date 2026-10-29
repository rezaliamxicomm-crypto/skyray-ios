import Foundation

/// What Auto measured, for the box: the header X-Etha-Lines on the next subscription fetch (the API stores it as one
/// row of line_reports; the panel shows it — the customer sees no line name). The same shape as the Android app's
/// EthaReport:
///
///     v=1;t=<epoch s>;trig=<connect|auto|stall|manual|network>;use=<label>;sw=<0|1>;l=<label>:<ms>,<label>:-1,…
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
    public static func build(now: Date, trigger: String, inUseRemark: String?, switched: Bool, results: [(String, Int64)]) -> String? {
        var items: [String] = []
        for (remark, ms) in results {
            guard let l = label(remark), ms != 0 else { continue }
            items.append("\(l):\(ms < 0 ? -1 : ms)")
            if items.count == maxLines { break }
        }
        if items.isEmpty { return nil }
        let use = label(inUseRemark) ?? ""
        return "v=1;t=\(Int64(now.timeIntervalSince1970));trig=\(trigger);use=\(use);sw=\(switched ? 1 : 0);l=\(items.joined(separator: ","))"
    }

    /// One text for a set of lines: the same set → the same text, whatever their ids (the line's link without its name).
    public static func fingerprint(_ lines: [Line]) -> String {
        lines.map { line -> String in
            let link = line.link
            return (link.firstIndex(of: "#").map { String(link[..<$0]) } ?? link) + "#" + line.remark
        }.sorted().joined(separator: "|")
    }
}
