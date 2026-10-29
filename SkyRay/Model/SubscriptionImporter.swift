import Foundation
import CryptoKit
import SkyRayCore
import SkyRayXray

/// Fetches the customer's link, reads the headers, turns every vless line into an Xray outbound (libXray,
/// in this process) and writes the snapshot the tunnel reads.
///
/// The link is fetched three ways at once (the operator's order of 2026-10-29): Encrypted Client Hello on the phone's
/// own network and through the running tunnel start together, the link hop inside Iran (the core's plain fetch, the
/// hop's name not listed, dialled at its address) after a head start for ECH — at once on a network where the hop
/// answered first last time. The first server answer wins, whatever it said. Only when nobody answered on any of
/// them is the link fetched once more as before 1.3.6, by URLSession without ECH — the operator's last resort.
/// What Auto measured rides on every way as the header X-Etha-Lines (TunnelState.lineReport, LineReport).
struct SubscriptionImporter {
    let store: SkyRayStore

    enum FetchError: Error {
        case network
        case expired
        case unknownLink
        case emptyBody
        case noLines
        case http(Int)
    }

    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return Etha.userAgent(version: version)
    }

    /// One way to the server: when it starts, what it asks the core, and whether it is the plain one (the hop).
    struct Way {
        let name: String
        let kind: String          // ech | tunnel | hop: what is remembered per network
        let startAfterMs: Int64
        let request: EchFetchRequest
        /// The server answered on this way — any status (the hop answers plain, the ECH ways with ECH accepted).
        func answered(_ r: EchFetchResult) -> Bool { kind == "hop" ? r.plainAnswered : r.answered }
    }

    /// "cell", "wifi" or "other": the network the phone is on, for remembering which way answered first there.
    static func networkSignature() -> String {
        guard let name = NetworkInterfaces.physical() else { return "other" }
        if name.hasPrefix("pdp_ip") { return "cell" }
        if name.hasPrefix("en") { return "wifi" }
        return "other"
    }

    /// The ways of a fetch, in the order they start. tunnelUp: the ECH way through the tunnel exists only then.
    static func ways(url: String, token: String?, stored: [String], hops: [LinkHop], tunnelUp: Bool, physical: String?,
                     headers: [String: String], hopHeadStartMs: Int64, userAgent: String) -> [Way] {
        var out: [Way] = []
        // While our tunnel is up the app's own traffic runs through it: this way is bound to the phone's own interface.
        out.append(Way(name: "ECH on the phone's network", kind: "ech", startAfterMs: 0,
                       request: EchFetch.request(url: url, stored: stored, userAgent: userAgent, interface: tunnelUp ? (physical ?? "") : "",
                                                 timeoutMs: EchFetch.timeoutMs, headers: headers)))
        if tunnelUp {
            out.append(Way(name: "ECH through the tunnel", kind: "tunnel", startAfterMs: 0,
                           request: EchFetch.request(url: url, stored: stored, userAgent: userAgent, interface: "",
                                                     timeoutMs: EchFetch.secondWayTimeoutMs, headers: headers)))
        }
        if let token = token {
            for hop in hops {
                out.append(Way(name: "the hop \(hop.host)", kind: "hop", startAfterMs: hopHeadStartMs,
                               request: EchFetch.hopRequest(token: token, hop: hop, userAgent: userAgent,
                                                            interface: tunnelUp ? (physical ?? "") : "", headers: headers)))
            }
        }
        return out
    }

    func fetch(_ link: String) async throws -> (info: SubscriptionInfo, links: [String]) {
        let url = EthaLink.canonical(link)
        guard URL(string: url) != nil else { throw FetchError.unknownLink }
        let snapshot = store.loadSnapshot()
        let stored = EchFetch.storedAddresses(lines: snapshot?.lines ?? [], selectedLineId: store.selection.selectedLineId)
        let report = store.tunnelState.lineReport ?? ""
        let headers: [String: String] = report.isEmpty ? [:] : [Etha.linesHeader: report]
        let tunnelUp = NetworkInterfaces.tunnelIsUp()
        let network = Self.networkSignature()
        let known = EchFetch.parseHops(snapshot?.info.linkHops)
        let ways = Self.ways(url: url, token: EthaLink.token(of: url), stored: stored, hops: known.isEmpty ? Etha.linkHops : known,
                             tunnelUp: tunnelUp, physical: NetworkInterfaces.physical(), headers: headers,
                             hopHeadStartMs: EchFetch.hopHeadStartMs(rememberedWay: store.fetchWay(on: network)), userAgent: Self.userAgent)
        if let winner = await Self.race(ways) {
            let (way, result) = winner
            AppLog.info("fetch: \(way.name) answered first via \(result.address) (key: \(result.keySource)), status \(result.status); network \(network)")
            store.rememberFetchWay(way.kind, on: network)
            if !report.isEmpty { store.updateTunnelState { if $0.lineReport == report { $0.lineReport = nil } } }
            return try Self.read(status: result.status, headers: result.headers, body: Data(result.body.utf8))
        }
        // Nobody answered on any of those ways: the last resort, the link fetched as every version before 1.3.6 did.
        AppLog.warn("fetch: ECH and the hop got no answer, fetching without them (the last resort)")
        let plain = try await Self.fetchPlain(url)
        AppLog.info("fetch: without ECH, status \(plain.status)")
        return try Self.read(status: plain.status, headers: plain.headers, body: plain.body)
    }

    /// The server's answer as the app reads it: the subscription, or what is wrong with the link.
    private static func read(status: Int, headers: [String: String], body: Data) throws -> (info: SubscriptionInfo, links: [String]) {
        switch status {
        case 200: break
        case 403: throw FetchError.expired
        case 404: throw FetchError.unknownLink
        default: throw FetchError.http(status)
        }
        var info = SubscriptionInfo()
        SubscriptionHeaders.apply(headers, to: &info)
        let links = SubscriptionBody.decode(body)
        if links.isEmpty { throw FetchError.emptyBody }
        return (info, links)
    }

    /// The fetch as it was before 1.3.6: URLSession, the host's name in the clear. Only after ECH got no answer.
    private static func fetchPlain(_ link: String) async throws -> (status: Int, headers: [String: String], body: Data) {
        guard let url = URL(string: link) else { throw FetchError.unknownLink }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FetchError.network
        }
        guard let http = response as? HTTPURLResponse else { throw FetchError.network }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String { headers[k.lowercased()] = v }
        }
        return (http.statusCode, headers, data)
    }

    /// Every way started at its time; the first whose server answered wins, the others run out on their own (the
    /// core's call cannot be cut short) and their answers are dropped. nil when nobody answered.
    private static func race(_ ways: [Way]) async -> (Way, EchFetchResult)? {
        await withTaskGroup(of: (Way, EchFetchResult?).self) { group in
            for way in ways {
                group.addTask {
                    if way.startAfterMs > 0 { try? await Task.sleep(nanoseconds: UInt64(way.startAfterMs) * 1_000_000) }
                    if Task.isCancelled { return (way, nil) }
                    return (way, await run(way.request))
                }
            }
            var winner: (Way, EchFetchResult)?
            for await (way, result) in group {
                if let r = result, way.answered(r) {
                    winner = (way, r)
                    group.cancelAll()
                    break
                }
                AppLog.warn("fetch: \(way.name) gave nothing: \(result?.failure ?? "no result from the core")")
            }
            return winner
        }
    }

    /// The core's fetch blocks until its answer or its timeout: off the main thread.
    private static func run(_ request: EchFetchRequest) async -> EchFetchResult? {
        guard let json = request.json() else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: EchFetchResult.parse(LibXrayBridge.fetchSubscriptionEch(json)))
            }
        }
    }

    /// vless links → Line values with their Xray outbound JSON. libXray is blocking: off the main thread.
    func buildLines(_ links: [String]) async -> [Line] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var out: [Line] = []
                for (index, link) in links.enumerated() {
                    guard let outbound = try? LibXrayBridge.convertShareLinks(link).first,
                          let data = try? JSONSerialization.data(withJSONObject: outbound),
                          let json = String(data: data, encoding: .utf8) else { continue }
                    let remark = Self.remark(of: link)
                    let parsed = LineName.parse(remark)
                    out.append(Line(id: Self.lineId(link), link: link, remark: remark, transport: parsed?.transport,
                                    endpointLabel: parsed?.label, port: parsed?.port, order: index, outboundJSON: json))
                }
                continuation.resume(returning: out)
            }
        }
    }

    static func remark(of link: String) -> String {
        guard let hash = link.firstIndex(of: "#") else { return "line" }
        let fragment = String(link[link.index(after: hash)...])
        let name = (fragment.removingPercentEncoding ?? fragment).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "line" : name
    }

    /// Stable across refreshes: the link without its remark, hashed.
    static func lineId(_ link: String) -> String {
        let base = link.firstIndex(of: "#").map { String(link[..<$0]) } ?? link
        let digest = SHA256.hash(data: Data(base.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    func fetchAndStore(link: String) async throws -> SubscriptionSnapshot {
        let (info, links) = try await fetch(link)
        let lines = await buildLines(links)
        guard !lines.isEmpty else { throw FetchError.noLines }
        let name = EthaLink.name(of: link)
        let snapshot = SubscriptionSnapshot(url: EthaLink.canonical(link), name: name, fetchedAt: Date(), info: info, lines: lines)
        store.saveSnapshot(snapshot)
        // the running tunnel holds the set it started with: a different set has to reach it (AppModel sends .reload)
        let fingerprint = LineReport.fingerprint(lines)
        if let before = store.linesFingerprint, before != fingerprint { store.linesChanged = true }
        store.linesFingerprint = fingerprint
        store.updateSelection { selection in
            let ids = Set(lines.map { $0.id })
            selection.results = selection.results.filter { ids.contains($0.key) }
            if let selected = selection.selectedLineId, !ids.contains(selected) {
                selection.selectedLineId = nil
                selection.pinned = false
            }
        }
        store.lastRefreshAttempt = Date()
        RefreshScheduler.schedule(after: info.updateIntervalMinutes ?? Etha.defaultUpdateMinutes)
        return snapshot
    }

    /// Refetches the stored subscription; failures keep the current servers.
    @discardableResult
    func refresh() async throws -> SubscriptionSnapshot {
        guard let current = store.loadSnapshot() else { throw FetchError.unknownLink }
        let base = EthaLink.migratedUrl(current.url) ?? current.url   // a snapshot from before the address moved
        let link = current.name == Etha.subName ? base : base + "#" + (current.name.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? current.name)
        return try await fetchAndStore(link: link)
    }

    func message(for error: Error) -> String {
        switch error as? FetchError {
        case .expired: return L("sub.expired")
        case .unknownLink: return L("link.notvalid")
        case .emptyBody, .noLines: return L("sub.empty")
        default: return L("net.unreachable")
        }
    }
}
