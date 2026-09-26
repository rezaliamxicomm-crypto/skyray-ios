import Foundation
import CryptoKit
import SkyRayCore
import SkyRayXray

/// Fetches the customer's link, reads the headers, turns every vless line into an Xray outbound (libXray,
/// in this process) and writes the snapshot the tunnel reads.
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
        guard let url = URL(string: EthaLink.canonical(link)) else { throw FetchError.unknownLink }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 40
        let session = URLSession(configuration: config)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FetchError.network
        }
        guard let http = response as? HTTPURLResponse else { throw FetchError.network }
        switch http.statusCode {
        case 200: break
        case 403: throw FetchError.expired
        case 404: throw FetchError.unknownLink
        default: throw FetchError.http(http.statusCode)
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String { headers[k.lowercased()] = v }
        }
        var info = SubscriptionInfo()
        SubscriptionHeaders.apply(headers, to: &info)
        let links = SubscriptionBody.decode(data)
        if links.isEmpty { throw FetchError.emptyBody }
        return (info, links)
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
        let link = current.name == Etha.subName ? current.url : current.url + "#" + (current.name.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? current.name)
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
