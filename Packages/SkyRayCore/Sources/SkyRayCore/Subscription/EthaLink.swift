import Foundation

public enum EthaLink {
    /// https://fra.mobileiphone.org/sub/<token of at least 8 characters, no slash>, fragment allowed.
    public static func isSubLink(_ text: String?) -> Bool {
        guard let text = text else { return false }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let c = URLComponents(string: t) else { return false }
        guard c.scheme?.lowercased() == "https", c.host?.lowercased() == Etha.subHost else { return false }
        let path = c.percentEncodedPath
        guard path.hasPrefix(Etha.subPath) else { return false }
        let token = path.dropFirst(Etha.subPath.count)
        return token.count >= 8 && !token.contains("/")
    }

    /// The link inside pasted text: tokens split on whitespace, trailing punctuation trimmed.
    public static func extract(from text: String?) -> String? {
        guard let text = text else { return nil }
        let trailing: Set<Character> = [".", ",", ")", "]", "؛", "،"]
        for token in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            var t = String(token)
            while let last = t.last, trailing.contains(last) { t.removeLast() }
            if isSubLink(t) { return t }
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

    public static func token(of link: String) -> String? {
        guard isSubLink(link), let c = URLComponents(string: canonical(link)) else { return nil }
        return String(c.percentEncodedPath.dropFirst(Etha.subPath.count))
    }
}
