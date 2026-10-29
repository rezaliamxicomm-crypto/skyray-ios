import Foundation

/// What the core's FetchSubscriptionEch takes (echfetch/echfetch.go, compiled into LibXray): the link and what to
/// reach it with. The property names are the JSON keys the core reads.
public struct EchFetchRequest: Codable, Equatable {
    public var url: String
    public var addresses: [String]          // tried first: the stored lines' clean Cloudflare addresses
    public var pinnedAddresses: [String]    // tried last
    public var resolvers: [String]          // asked over plain UDP 53 for the HTTPS record
    public var lookupName: String           // whose HTTPS record carries the key: the ECH public name
    public var pinnedKey: String            // base64 ECHConfigList, offered when no resolver delivers one
    public var userAgent: String
    public var timeoutMs: Int64
    public var interface: String            // bind every socket to it (the phone's own, past a running tunnel); "" = no binding
    public var plain: Bool                  // no ECH: a plain TLS fetch to `addresses`, the url's host as the certificate's name (the link hop inside Iran)
    public var headers: [String: String]    // extra request headers, every way (X-Etha-Lines: what Auto measured)

    public init(url: String, addresses: [String], pinnedAddresses: [String], resolvers: [String], lookupName: String,
                pinnedKey: String, userAgent: String, timeoutMs: Int64, interface: String, plain: Bool = false, headers: [String: String] = [:]) {
        self.url = url; self.addresses = addresses; self.pinnedAddresses = pinnedAddresses; self.resolvers = resolvers
        self.lookupName = lookupName; self.pinnedKey = pinnedKey; self.userAgent = userAgent
        self.timeoutMs = timeoutMs; self.interface = interface; self.plain = plain; self.headers = headers
    }

    /// The JSON text the core reads.
    public func json() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// What the core returns: the server's answer, or why there is none. echAccepted is true on every ECH answer — a
/// request is never sent without it; false on a plain one (the link hop), whose keySource is "plain".
public struct EchFetchResult: Equatable {
    public var status: Int = 0
    public var headers: [String: String] = [:]   // names lower-cased, the last value of a repeated header
    public var body: String = ""
    public var echAccepted: Bool = false
    public var address: String = ""
    public var keySource: String = ""            // "dns:<resolver>", "pinned" or "retry"; "plain" when no ECH was asked
    public var error: String = ""

    public init() {}

    /// Reads the core's JSON; nil when the text is not a JSON object. A member that is missing keeps its default.
    public static func parse(_ json: String) -> EchFetchResult? {
        guard let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var result = EchFetchResult()
        result.status = (object["status"] as? NSNumber)?.intValue ?? 0
        result.headers = (object["headers"] as? [String: String]) ?? [:]
        result.body = (object["body"] as? String) ?? ""
        result.echAccepted = (object["echAccepted"] as? Bool) ?? false
        result.address = (object["address"] as? String) ?? ""
        result.keySource = (object["keySource"] as? String) ?? ""
        result.error = (object["error"] as? String) ?? ""
        return result
    }

    /// The server itself answered, with ECH — any status. Only a fetch that reached nobody is worth another way.
    public var answered: Bool { error.isEmpty && echAccepted && status > 0 }

    /// The hop itself answered, plain — any status. Only a hop that reached nobody is worth the next one.
    public var plainAnswered: Bool { error.isEmpty && status > 0 }

    /// Why a fetch gave nothing, for the log — never a body, never a token.
    public var failure: String {
        if !error.isEmpty { return error }
        if !echAccepted && keySource != "plain" { return "ECH not accepted" }
        return "status \(status)"
    }
}

/// One link hop inside Iran: the name the link is fetched under there and the address dialled for it.
public struct LinkHop: Codable, Equatable {
    public var host: String
    public var ip: String
    public init(host: String, ip: String) { self.host = host; self.ip = ip }
}

/// Our own link is fetched with Encrypted Client Hello enforced. The pure half of it — which addresses to offer
/// and what to ask for; the call itself is LibXrayBridge.fetchSubscriptionEch, and what follows when nobody answered
/// (one last fetch without ECH) is SubscriptionImporter's.
public enum EchFetch {
    /// Dead addresses cost a dial timeout each before the pinned ones get their turn.
    public static let maxStoredAddresses = 3
    public static let timeoutMs: Int64 = 20_000
    /// The second way out (through the tunnel, after the way past it gave nothing) gets less time than the first.
    public static let secondWayTimeoutMs: Int64 = 15_000

    /// The address a share link dials: vless://<id>@<address>:<port>?… → <address>. nil when there is none to read.
    public static func address(ofLink link: String) -> String? {
        guard let scheme = link.range(of: "://") else { return nil }
        let afterScheme = link[scheme.upperBound...]
        guard let at = afterScheme.firstIndex(of: "@") else { return nil }
        let rest = afterScheme[afterScheme.index(after: at)...]
        let end = rest.firstIndex(where: { $0 == "?" || $0 == "#" || $0 == "/" }) ?? rest.endIndex
        let hostPort = rest[..<end]
        if hostPort.hasPrefix("[") { return nil }   // an IPv6 literal: not offered
        let host = hostPort.lastIndex(of: ":").map { hostPort[..<$0] } ?? hostPort
        return host.isEmpty ? nil : String(host)
    }

    static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part) else { return false }
            return value <= 255
        }
    }

    /// The stored lines' IPv4 addresses in the order given (the selected line's first), no repeats, at most maxStoredAddresses.
    public static func candidateAddresses(_ stored: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in stored {
            let address = raw.trimmingCharacters(in: .whitespaces)
            guard isIPv4(address), seen.insert(address).inserted else { continue }
            out.append(address)
            if out.count == maxStoredAddresses { break }
        }
        return out
    }

    /// The addresses the stored Cloudflare lines dial, the selected line's first; a relay's (since 2026-10-24 the first lines) is never offered.
    public static func storedAddresses(lines: [Line], selectedLineId: String?) -> [String] {
        var ordered = lines.filter { Etha.cloudflareTransports.contains(($0.transport ?? "").uppercased()) }
        if let id = selectedLineId, let index = ordered.firstIndex(where: { $0.id == id }) {
            let selected = ordered.remove(at: index)
            ordered.insert(selected, at: 0)
        }
        return ordered.compactMap { address(ofLink: $0.link) }
    }

    /// The request the core gets. interface: the phone's own interface to leave by while our tunnel is up, "" otherwise.
    public static func request(url: String, stored: [String], userAgent: String, interface: String = "",
                               timeoutMs: Int64 = EchFetch.timeoutMs, headers: [String: String] = [:]) -> EchFetchRequest {
        EchFetchRequest(url: url, addresses: candidateAddresses(stored), pinnedAddresses: Etha.echAddresses,
                        resolvers: Etha.echResolvers, lookupName: Etha.echLookupName, pinnedKey: Etha.echPinnedKey,
                        userAgent: userAgent, timeoutMs: timeoutMs, interface: interface, headers: headers)
    }

    /// Pure: the hop's head start on a network — none where it answered first last time (SubscriptionImporter).
    public static func hopHeadStartMs(rememberedWay: String?) -> Int64 { rememberedWay == "hop" ? 0 : Etha.hopHeadStartMs }

    // ---- the link hop inside Iran (the plain way, after the two ECH ways)

    /// A name as a hop's: labels of letters, digits and hyphens, none starting or ending with one, at least two of them.
    static func isHostName(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 253 else { return false }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            guard !label.isEmpty, label.count <= 63, label.first != "-", label.last != "-" else { return false }
            return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// The service's X-Etha-Link-Hops, "host=ip, host=ip" → the hops in that order, no repeats; an entry that is not a
    /// name and an IPv4 address is skipped.
    public static func parseHops(_ header: String?) -> [LinkHop] {
        guard let header = header else { return [] }
        var out: [LinkHop] = []
        for entry in header.split(separator: ",") {
            let kv = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            let host = kv[0].lowercased()
            guard isHostName(host), isIPv4(kv[1]) else { continue }
            let hop = LinkHop(host: host, ip: kv[1])
            if !out.contains(hop) { out.append(hop) }
        }
        return out
    }

    /// The hops back into the header's form, for keeping.
    public static func format(_ hops: [LinkHop]) -> String { hops.map { "\($0.host)=\($0.ip)" }.joined(separator: ",") }

    /// The request for a hop: its address of the token, its address dialled, no ECH; interface as for the ECH ways.
    public static func hopRequest(token: String, hop: LinkHop, userAgent: String, interface: String = "",
                                  timeoutMs: Int64 = Etha.hopTimeoutMs, headers: [String: String] = [:]) -> EchFetchRequest {
        EchFetchRequest(url: "https://\(hop.host)\(Etha.subPath)\(token)", addresses: [hop.ip], pinnedAddresses: [], resolvers: [],
                        lookupName: "", pinnedKey: "", userAgent: userAgent, timeoutMs: timeoutMs, interface: interface, plain: true, headers: headers)
    }
}
