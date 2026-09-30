import Foundation

/// SkyRay 1.1.6 and earlier — a different codebase in the same App Store record — kept the customer's servers and
/// subscriptions as JSON files at the root of the shared App Group container. The first launch after the update
/// takes the link from there once, so nobody has to import it again. Nothing is written back.
public enum OldAppFiles {
    public static let names = ["subscriptions.json", "profiles.json", "profiles.backup.json", "active-profile.json"]

    /// The first of our links in the old app's files, on the current address.
    public static func link(inContainer root: URL) -> String? {
        for name in names {
            guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { continue }
            if let link = firstLink(in: data) { return link }
        }
        return nil
    }

    /// Any string value in the JSON that is one of our links (subscriptionURL, url, …), moved to the current address.
    public static func firstLink(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var found: String?
        func walk(_ value: Any) {
            if found != nil { return }
            if let s = value as? String {
                if let link = EthaLink.normalized(s) { found = link }
            } else if let dict = value as? [String: Any] {
                for key in ["subscriptionURL", "url"] {
                    if let s = dict[key] as? String, let link = EthaLink.normalized(s) { found = link; return }
                }
                for v in dict.values { walk(v) }
            } else if let list = value as? [Any] {
                for v in list { walk(v) }
            }
        }
        walk(json)
        return found
    }
}
