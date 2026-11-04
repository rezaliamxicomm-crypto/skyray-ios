import Foundation
import CryptoKit
import SkyRayCore
import SkyRayXray
import UIKit

/// Fetches the customer's link, reads the headers, turns every vless line into an Xray outbound (libXray,
/// in this process) and writes the snapshot the tunnel reads.
///
/// The link is fetched three ways at once (the operator's order of 2026-10-29): Encrypted Client Hello on the phone's
/// own network and through the running tunnel start together, the link hop inside Iran (the core's plain fetch, the
/// hop's name not listed, dialled at its address) after a head start for ECH — at once on a network where the hop
/// answered first last time. The first server answer wins, whatever it said. Only when nobody answered on any of
/// them is the link fetched once more as before 1.3.6, by name without ECH — the operator's last resort — through the core
/// like every other way (2.1), so the certificate and the box's signature are checked the same.
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
        case devices(limit: Int, active: Int)   // the device limit's signed 403 (3.0.0): this subscription is on more phones than allowed
    }

    /// The phone's model for the operator's device card (X-Etha-Model): the machine name, nothing that names the person.
    static var deviceModel: String {
        var s = utsname(); uname(&s)
        let m = withUnsafePointer(to: &s.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        return String(m.prefix(48))
    }

    /// This phone's code for the box: the Keychain's, else the one made from the vendor identifier and kept from then on (DeviceCodeStore). Main thread.
    static func phoneCode() -> String? {
        DeviceCodeStore.code(fallback: DeviceCode.make(id: UIDevice.current.identifierForVendor?.uuidString, bundle: Bundle.main.bundleIdentifier ?? ""))
    }

    /// The OS version for X-Etha-OS, read without UIKit (the background fetch runs off the main thread).
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
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
        var headers: [String: String] = report.isEmpty ? [:] : [Etha.linesHeader: report]
        if let code = deviceCode { headers[Etha.deviceHeader] = code }   // this phone as a code, on every way of the fetch (2.1.2)
        if let want = store.exitWant { headers[Etha.exitSetHeader] = want }   // the Servers box (3.0.0): this phone's choice, until the box confirms it
        headers[Etha.modelHeader] = Self.deviceModel                           // the operator's device card: the phone's model and OS version
        headers[Etha.osHeader] = "iOS " + Self.osVersion
        let tunnelUp = NetworkInterfaces.tunnelIsUp()
        let network = Self.networkSignature()
        let known = EchFetch.parseHops(snapshot?.info.linkHops)
        let ways = Self.ways(url: url, token: EthaLink.token(of: url), stored: stored, hops: known.isEmpty ? Etha.linkHops : known,
                             tunnelUp: tunnelUp, physical: NetworkInterfaces.physical(), headers: headers,
                             hopHeadStartMs: EchFetch.hopHeadStartMs(rememberedWay: store.fetchWay(on: network)), userAgent: Self.userAgent)
        if let winner = await Self.race(ways, heldSignedAt: store.lastSignedAt) {
            let (way, result) = winner
            AppLog.info("fetch: \(way.name) answered first via \(result.address) (key: \(result.keySource)), status \(result.status), signed \(result.signed.isEmpty ? "-" : result.signed)\(result.stale() ? " (stale, nothing fresher came)" : ""); network \(network)")
            store.rememberFetchWay(way.kind, on: network)
            if result.signedAt > 0 { store.lastSignedAt = max(store.lastSignedAt ?? 0, result.heldSignedAt()) }
            // the report is spent only when the box could file it under this phone's network: a fetch that won through the
            // tunnel reaches the box from its own address and is filed as "through the tunnel" (the box ignores it for the ranking)
            if !report.isEmpty, way.kind != "tunnel" { store.updateTunnelState { if $0.lineReport == report { $0.lineReport = nil } } }
            return try Self.read(status: result.status, headers: result.headers, body: Data(result.body.utf8))
        }
        // Nobody answered on any of those ways: the last resort, the link fetched by name without ECH as every version
        // before 1.3.6 did — through the core like every other way (2.1), so the certificate and the box's signature are
        // checked the same; an answer signed before the one held is refused here too.
        AppLog.warn("fetch: ECH and the hop got no answer, fetching by name without ECH (the last resort)")
        let plainRequest = EchFetchRequest(url: url, addresses: [], pinnedAddresses: [], resolvers: [], lookupName: "", pinnedKey: "",
                                           userAgent: Self.userAgent, timeoutMs: EchFetch.timeoutMs,
                                           interface: tunnelUp ? (NetworkInterfaces.physical() ?? "") : "", plain: true, headers: headers)
        guard let plain = await Self.run(plainRequest), plain.plainAnswered else {
            AppLog.warn("fetch: by name without ECH: nothing")
            throw FetchError.network
        }
        if let held = store.lastSignedAt, plain.signedAt > 0, plain.signedAt < held {
            AppLog.warn("fetch: by name without ECH: signed before the one held (\(plain.signedAt) < \(held)): not taken")
            throw FetchError.network
        }
        if plain.tooOld() {
            AppLog.warn("fetch: by name without ECH: signed \(Int64(Date().timeIntervalSince1970) - plain.signedAt) s ago: refused")
            throw FetchError.network
        }
        AppLog.info("fetch: by name without ECH via \(plain.address), status \(plain.status), signed \(plain.signed.isEmpty ? "-" : plain.signed)")
        if plain.signedAt > 0 { store.lastSignedAt = max(store.lastSignedAt ?? 0, plain.heldSignedAt()) }
        if !report.isEmpty { store.updateTunnelState { if $0.lineReport == report { $0.lineReport = nil } } }
        return try Self.read(status: plain.status, headers: plain.headers, body: Data(plain.body.utf8))
    }

    /// The server's answer as the app reads it: the subscription, or what is wrong with the link.
    private static func read(status: Int, headers: [String: String], body: Data) throws -> (info: SubscriptionInfo, links: [String]) {
        switch status {
        case 200: break
        case 403:
            if let d = Exits.devicesRefusal(String(decoding: body, as: UTF8.self)) { throw FetchError.devices(limit: d.limit, active: d.active) }   // the device limit (3.0.0)
            throw FetchError.expired
        case 404: throw FetchError.unknownLink
        default: throw FetchError.http(status)
        }
        var info = SubscriptionInfo()
        SubscriptionHeaders.apply(headers, to: &info)
        let links = SubscriptionBody.decode(body)
        if links.isEmpty { throw FetchError.emptyBody }
        return (info, links)
    }


    /// Every way started at its time; the first whose server answered wins, the others run out on their own (the
    /// core's call cannot be cut short) and their answers are dropped. nil when nobody answered.
    /// The first way whose answer is the box's own word — a signed 200 or 403 — wins and cancels the rest. Any other status
    /// (a 404, a 5xx: nothing signed) is kept aside and used only when no way brings a signed answer, so a hop answering
    /// 404 fast cannot end the race. The replay rules (2.1): an answer signed before the one this phone already holds is
    /// never taken; one older than Etha.signedMaxAge is never taken; one older than Etha.signedStaleAfter is kept aside
    /// and the freshest of those taken only when nothing fresher comes.
    static func race(_ ways: [Way], heldSignedAt: Int64?, now: Int64 = Int64(Date().timeIntervalSince1970)) async -> (Way, EchFetchResult)? {
        await withTaskGroup(of: (Way, EchFetchResult?).self) { group in
            for way in ways {
                group.addTask {
                    if way.startAfterMs > 0 { try? await Task.sleep(nanoseconds: UInt64(way.startAfterMs) * 1_000_000) }
                    if Task.isCancelled { return (way, nil) }
                    return (way, await run(way.request))
                }
            }
            var winner: (Way, EchFetchResult)?
            var staleWinner: (Way, EchFetchResult)?
            var otherStatus: (Way, EchFetchResult)?
            for await (way, result) in group {
                guard let r = result, way.answered(r) else {
                    AppLog.warn("fetch: \(way.name) gave nothing: \(result?.failure ?? "no result from the core")")
                    continue
                }
                if !r.signedWord {
                    if otherStatus == nil { otherStatus = (way, r) }
                    AppLog.warn("fetch: \(way.name) answered \(r.status) without the box's word: kept aside")
                    continue
                }
                if let held = heldSignedAt, r.signedAt > 0, r.signedAt < held {
                    AppLog.warn("fetch: \(way.name) answered with a subscription signed before the one held (\(r.signedAt) < \(held)): not taken")
                    continue
                }
                if r.tooOld(now: now) {
                    AppLog.warn("fetch: \(way.name) answered with a subscription signed \(now - r.signedAt) s ago: refused")
                    continue
                }
                if r.stale(now: now) {
                    if staleWinner == nil || r.signedAt > staleWinner!.1.signedAt { staleWinner = (way, r) }
                    AppLog.warn("fetch: \(way.name) answered with a subscription signed \(now - r.signedAt) s ago: kept aside")
                    continue
                }
                winner = (way, r)
                group.cancelAll()
                break
            }
            return winner ?? staleWinner ?? otherStatus
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

    /// This phone as a code for the box (DeviceCode, 2.1.2): set by the app on the main actor, sent on every fetch of our link.
    var deviceCode: String?

    /// The box's own word that the subscription ended (a signed 403, 2.1.2): the stored info says so at once — the expiry set to the
    /// past; a renewal's fetch sets it right (the same link) — so the account card reads «Expired», and the app tells the tunnel.
    private func noteExpired() {
        guard var snapshot = store.loadSnapshot() else { return }
        snapshot.info.expire = Int64(Date().timeIntervalSince1970) - 1
        snapshot.info.infoUpdated = Date()
        store.saveSnapshot(snapshot)
        store.lastRefreshAttempt = Date()
    }

    @discardableResult
    func fetchAndStore(link: String) async throws -> SubscriptionSnapshot {
        if let stored = store.loadSnapshot()?.url, EthaLink.token(of: EthaLink.canonical(link)) != EthaLink.token(of: stored) { store.exitWant = nil; store.exitMeasured = [:] }   // another account starts at Auto (3.0.0)
        let carried = store.exitWant   // the pending choice this fetch carries: its answer settles it, confirmed or not
        let fetched: (info: SubscriptionInfo, links: [String])
        do {
            fetched = try await fetch(link)
        } catch FetchError.expired {
            if let stored = store.loadSnapshot()?.url, EthaLink.token(of: EthaLink.canonical(link)) == EthaLink.token(of: stored) { noteExpired() }   // the stored account's own link, not a stranger's pasted one
            throw FetchError.expired
        }
        let (info, links) = fetched
        let lines = await buildLines(links)
        guard !lines.isEmpty else { throw FetchError.noLines }
        let name = EthaLink.name(of: link)
        let snapshot = SubscriptionSnapshot(url: EthaLink.canonical(link), name: name, fetchedAt: Date(), info: info, lines: lines)
        store.saveSnapshot(snapshot)
        if let carried = carried, store.exitWant == carried { store.exitWant = nil }   // the fetch that carried the choice is answered: the box's word stands, confirmed or not (3.0.0)
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
        case .devices: return L("devices.title")
        case .unknownLink: return L("link.notvalid")
        case .emptyBody, .noLines: return L("sub.empty")
        default: return L("net.unreachable")
        }
    }
}
