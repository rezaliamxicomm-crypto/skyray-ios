import Foundation

/// Our link: https://<the link address>/sub/<token>, a fragment allowed (it names the subscription). A link on
/// an earlier address is the same account and is moved to the current address, as the Android app does.
public enum EthaLink {
    /// The token of an https://<one of hosts>/sub/<token> link (≥ 8 characters, no slash), else nil.
    static func token(in text: String?, hosts: [String]) -> String? {
        guard let text = text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let c = URLComponents(string: t), c.scheme?.lowercased() == "https",
              let host = c.host?.lowercased(), hosts.contains(where: { $0.lowercased() == host }) else { return nil }
        let path = c.percentEncodedPath
        guard path.hasPrefix(Etha.subPath) else { return nil }
        let token = String(path.dropFirst(Etha.subPath.count))
        return token.count >= 8 && !token.contains("/") ? token : nil
    }

    /// A link on the current address.
    public static func isSubLink(_ text: String?) -> Bool { token(in: text, hosts: Etha.subHosts) != nil }

    /// The account token of a link on the current address.
    public static func token(of link: String?) -> String? { token(in: link, hosts: Etha.subHosts) }

    /// A link on an earlier address → the same token on the current one, the name after '#' kept. Anything else: nil.
    public static func migratedUrl(_ link: String?) -> String? {
        guard let link = link, let token = token(in: link, hosts: Etha.oldSubHosts) else { return nil }
        let t = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = t.firstIndex(of: "#").map { String(t[t.index(after: $0)...]) } ?? ""
        let next = "https://\(Etha.subHost)\(Etha.subPath)\(token)"
        return name.isEmpty ? next : next + "#" + name
    }

    /// The link as the app uses it: the current address as it is, an earlier one moved; anything else nil.
    public static func normalized(_ text: String?) -> String? {
        guard let text = text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSubLink(t) { return t }
        return migratedUrl(t)
    }

    /// Whether two links name the same account, whatever address or name either carries.
    public static func sameAccount(_ a: String?, _ b: String?) -> Bool {
        guard let ta = token(of: normalized(a)) else { return false }
        return ta == token(of: normalized(b))
    }

    /// The link inside pasted text: tokens split on whitespace, trailing punctuation trimmed, an earlier address moved.
    public static func extract(from text: String?) -> String? {
        guard let text = text else { return nil }
        let trailing: Set<Character> = [".", ",", ")", "]", "؛", "،"]
        for piece in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            var t = String(piece)
            while let last = t.last, trailing.contains(last) { t.removeLast() }
            if let link = normalized(t) { return link }
        }
        return nil
    }

    /// The link without its fragment: the identity of a subscription and the URL that is fetched.
    public static func canonical(_ link: String) -> String {
        if let i = link.firstIndex(of: "#") { return String(link[..<i]) }
        return link
    }

    /// The fragment as the subscription's name, else the service's name.
    public static func name(of link: String) -> String {
        guard let i = link.firstIndex(of: "#") else { return Etha.subName }
        let frag = String(link[link.index(after: i)...]).removingPercentEncoding ?? ""
        let t = frag.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? Etha.subName : t
    }
}
