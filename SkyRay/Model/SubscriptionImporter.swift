import Foundation
import CryptoKit
import SkyRayCore
import SkyRayXray

/// Fetches the customer's link, reads the headers, turns every vless line into an Xray outbound (libXray,
/// in this process) and writes the snapshot the tunnel reads.
///
/// The link is fetched with Encrypted Client Hello enforced (the core's fetch, EchFetch): its host's name is not
/// stated in the clear. Only when nobody answered that way is it fetched once more as before 1.3.6, by URLSession
/// without ECH — the operator's last resort for a network that blocks ECH itself.
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

    func fetch(_ link: String) async throws -> (info: SubscriptionInfo, links: [String]) {
        let url = EthaLink.canonical(link)
        guard URL(string: url) != nil else { throw FetchError.unknownLink }
        let stored = EchFetch.storedAddresses(lines: store.loadSnapshot()?.lines ?? [], selectedLineId: store.selection.selectedLineId)
        // While our tunnel is up the app's own traffic runs through it. First past it, bound to the phone's own
        // interface — that way does not depend on the line that is connected; when nobody answers, through the tunnel.
        var ways: [(interface: String, timeoutMs: Int64, name: String)] = [("", EchFetch.timeoutMs, "directly")]
        if NetworkInterfaces.tunnelIsUp(), let physical = NetworkInterfaces.physical() {
            ways = [(physical, EchFetch.timeoutMs, "past the tunnel (\(physical))"), ("", EchFetch.secondWayTimeoutMs, "through the tunnel")]
        }
        var answer: EchFetchResult?
        for way in ways {
            let request = EchFetch.request(url: url, stored: stored, userAgent: Self.userAgent, interface: way.interface, timeoutMs: way.timeoutMs)
            let result = await Self.run(request)
            if let result, result.answered {
                AppLog.info("fetch: ECH \(way.name) via \(result.address) (key: \(result.keySource)), status \(result.status)")
                answer = result
                break   // the server answered, whatever it said: another way out would hear the same
            }
            AppLog.warn("fetch: ECH \(way.name) gave nothing: \(result?.failure ?? "no result from the core")")
        }
        if let result = answer {
            return try Self.read(status: result.status, headers: result.headers, body: Data(result.body.utf8))
        }
        // Nobody answered with ECH on any way: the last resort, the link fetched as every version before 1.3.6 did.
        AppLog.warn("fetch: ECH got no answer, fetching without it (the last resort)")
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
