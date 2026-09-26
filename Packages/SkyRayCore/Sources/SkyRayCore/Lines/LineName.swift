import Foundation

/// The service names its lines "EthaVPN-<transport>-<tag>-<endpoint>-<port>"; the app shows "<endpoint> · <transport>/<port>".
public enum LineName {
    private static let regex = try! NSRegularExpression(pattern: "^EthaVPN-([A-Za-z0-9]+)-[^-]+-(.+?)-(\\d+)$")

    public static func parse(_ remark: String) -> (transport: String, label: String, port: Int)? {
        let ns = remark as NSString
        guard let m = regex.firstMatch(in: remark, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges == 4,
              let port = Int(ns.substring(with: m.range(at: 3))) else { return nil }
        return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)), port)
    }

    public static func display(_ remark: String) -> String {
        guard let p = parse(remark) else { return remark }
        return "\(p.label) · \(p.transport)/\(p.port)"
    }
}
