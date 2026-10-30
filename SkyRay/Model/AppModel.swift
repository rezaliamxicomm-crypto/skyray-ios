import Foundation
import Combine
import NetworkExtension
import StoreKit
import UIKit
import SkyRayCore

struct BannerMessage: Equatable {
    enum Kind { case ok, error, info }
    let text: String
    let kind: Kind
    let id = UUID()
}

/// The one state object of the app: the subscription, the tunnel's status and the actions the screens trigger.
/// Mirrors the Android HomeActivity's logic. No line is named anywhere (2.0.0): the customer sees the latency of the
/// line in use, "Test latency" and "Refresh"; the names and every test go to the box (LineReport → the panel).
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable { case idle, finding, connecting, disconnecting }
    enum ImportSource: String { case paste, clipboard, qr, link }

    @Published private(set) var snapshot: SubscriptionSnapshot?
    @Published private(set) var selection = Selection()
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var tunnel: TunnelReply?
    @Published private(set) var refreshing = false
    @Published private(set) var declarationAccepted = false
    /// The extension's measurements of the lines through the running core (TunnelState.results), while the tunnel is up.
    @Published private(set) var tunnelResults: [String: Int64] = [:]
    /// Test latency is running: the button is busy, the chip says so.
    @Published private(set) var testing = false
    /// Auto found no line answering (the extension's state): the Searching state.
    @Published private(set) var searching = false
    /// The line in use's last time (ms, -1 failed, 0 none yet) and when it was measured.
    @Published private(set) var latencyMs: Int64 = 0
    @Published private(set) var latencyAt: Date?
    /// The string under the buttons after a test (a key of Localizable), nil = none.
    @Published private(set) var outcomeKey: String?
    @Published var banner: BannerMessage?

    let store: SkyRayStore
    let vpn: VPNController
    private let importer: SubscriptionImporter
    private var cancellables: Set<AnyCancellable> = []
    private var clipboardTried: String?
    private var launched = false
    private var rateOnLatency = false         // the customer just connected by hand: the first time that lands decides the rating ask
    private var lastSearchFetchAt: Date?
    private var lastFailoverSeen: Date?
    private var lastFailoverFetchAt: Date?

    init(store: SkyRayStore = .appGroup()) {
        self.store = store
        self.vpn = VPNController()
        self.importer = SubscriptionImporter(store: store)
        AppLog.shared = RingLog(url: store.appLogURL)
        reload()
        vpn.$status
            .removeDuplicates()
            .sink { [weak self] status in
                Task { @MainActor [weak self] in self?.statusChanged(status) }
            }
            .store(in: &cancellables)
    }

    // MARK: state

    func reload() {
        snapshot = store.loadSnapshot()
        selection = store.selection
        declarationAccepted = store.declarationAccepted
        tunnelResults = store.tunnelState.results ?? [:]
    }

    private func refreshTunnelResults() { tunnelResults = store.tunnelState.results ?? [:] }

    /// The lines' last measurements: the extension's while the tunnel is up and it has some, else the app's own test.
    private var results: [String: Int64] { vpn.isActive && !tunnelResults.isEmpty ? tunnelResults : selection.results }
    private func delay(of id: String) -> Int64 { results[id] ?? 0 }
    private var candidates: [AutoSelect.Candidate] { lines.map { AutoSelect.Candidate(id: $0.id, delayMs: delay(of: $0.id), order: $0.order) } }

    var lines: [Line] { snapshot?.lines ?? [] }
    var hasSubscription: Bool { !(snapshot?.lines.isEmpty ?? true) }
    var isConnected: Bool { vpn.status == .connected }

    var stateText: String {
        switch phase {
        case .finding: return L("state.finding")
        case .connecting: return L("state.connecting")
        case .disconnecting: return L("state.disconnecting")
        case .idle: break
        }
        switch vpn.status {
        // Connected the moment the tunnel is up: traffic flows. The chip under it says "Connecting…" until the first
        // measurement is in (the operator's wording), then the number — or "no answer yet" when the line in use failed its
        // probe (2.0.2 kept saying Connecting… in that case, which read as nothing happening).
        case .connected: return L(searching ? "state.searching" : "state.connected")
        case .connecting, .reasserting: return L("state.connecting")
        case .disconnecting: return L("state.disconnecting")
        default: return L("state.notconnected")
        }
    }

    var busy: Bool { phase != .idle }

    /// Under the buttons: what to do while no line answers, else what the last test did; nil = nothing.
    var outcomeText: String? {
        if isConnected, searching { return L(tunnel?.outage == true ? "lines.blocked" : "searching.hint") }   // the box's word when every phone of the network fails
        return outcomeKey.map { L($0) }
    }

    /// The chip's age: "just now" under a minute, else the system's relative wording.
    func ago(_ at: Date?) -> String {
        guard let at = at, Date().timeIntervalSince(at) >= 60 else { return L("just.now") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: at, relativeTo: Date())
    }

    func acceptDeclaration() {
        store.declarationAccepted = true
        declarationAccepted = true
    }

    // MARK: lifecycle

    func onLaunch() async {
        guard !launched else { return }
        launched = true
        // The declaration screen is no longer shown (Apple's review, 2026-10-29): count it as accepted, so the
        // first-open imports below run as before. acceptDeclaration() and the flag stay for the day it returns.
        if !store.declarationAccepted { acceptDeclaration() }
        // A line pinned by hand in 1.3.x would have no screen to unpin it now: nobody is pinned in 2.0.0.
        if store.selection.pinned { store.updateSelection { $0.pinned = false }; AppLog.info("launch: back to Auto") }
        await vpn.load()
        await onActive()
        await DevTools.applyLaunchArguments(model: self)
    }

    func onActive() async {
        reload()
        if declarationAccepted, !hasSubscription, store.deletedLink == nil {
            await OldAppImport.attempt(model: self)
        }
        if declarationAccepted, !hasSubscription {
            if await ClipboardImport.attempt(model: self) == false {
                try? await Task.sleep(nanoseconds: 400_000_000)
                _ = await ClipboardImport.attempt(model: self)
            }
        }
        if let s = snapshot, SubscriptionHeaders.isStale(s.fetchedAt) {
            await refreshQuietly(reason: "stale on open")
        }
        await pollStatus()
        DevTools.mirrorLogs(from: store)
    }

    private func statusChanged(_ status: NEVPNStatus) {
        switch status {
        case .connected:
            rateOnLatency = phase == .connecting   // the customer's own Connect, not the state found on opening or a reconnect by the system
            phase = .idle
            Task {
                await self.pollStatus()
                DevTools.mirrorLogs(from: self.store)
                await self.pollUntilFirstLatency()
            }
        case .disconnected, .invalid:
            if phase == .connecting || phase == .disconnecting { phase = .idle }
            tunnel = nil
            searching = false; testing = false; latencyMs = 0; latencyAt = nil; outcomeKey = nil
        default:
            break
        }
    }

    /// Right after the tunnel comes up the extension measures every line (one to five seconds): ask every two seconds
    /// until the first time is in, up to 20 s, so the number follows the measurement within a second — the regular poll
    /// is every ten.
    private func pollUntilFirstLatency() async {
        for _ in 0..<10 {
            guard isConnected, latencyAt == nil, !searching else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await pollStatus()
        }
    }

    /// The tunnel's status: the line in use's time (the chip), the Searching state, and the measurements.
    func pollStatus() async {
        guard vpn.isActive else { tunnel = nil; return }
        if let reply = await vpn.send(.status) { take(reply) }
        refreshTunnelResults()
    }

    private func take(_ reply: TunnelReply) {
        tunnel = reply
        if let ms = reply.latencyMs, let at = reply.latencyAt { latencyMs = ms; latencyAt = at }   // nil until the extension measured
        let wasSearching = searching
        searching = reply.searching ?? false
        if searching { outcomeKey = nil }
        if rateOnLatency, latencyMs > 0, let at = latencyAt, Date().timeIntervalSince(at) < 60 {
            rateOnLatency = false
            askForRating()
        }
        if searching, !wasSearching || (lastSearchFetchAt.map { Date().timeIntervalSince($0) } ?? .infinity) >= searchFetchInterval {
            Task { await refetchWhileSearching() }
        }
        // Auto left a dead line (2.1): one quiet fetch, so the box hears of it soon and the lines are fresh — at most one in ten minutes
        if let at = reply.failoverAt, at > (lastFailoverSeen ?? .distantPast) {
            lastFailoverSeen = at
            if (lastFailoverFetchAt.map { Date().timeIntervalSince($0) } ?? .infinity) >= 600, !refreshing {
                lastFailoverFetchAt = Date()
                Task { await refreshQuietly(reason: "failover") }
            }
        }
    }

    private var searchFetchInterval: TimeInterval {
        TimeInterval(AutoPolicy.parse(snapshot?.info.autoPolicy).searchFetchSec)
    }

    /// No line answers: the subscription fetched again (the link's own route works when the tunnel does not); other
    /// lines reach the running tunnel as a reload.
    private func refetchWhileSearching() async {
        guard !refreshing else { return }
        lastSearchFetchAt = Date()
        await refreshQuietly(reason: "searching")
    }

    /// A connection the customer made that works (its first measured time landed) counts towards the rating ask
    /// (RatePrompt). When one is due, iOS shows its own card — stars and "Not Now"; Apple allows no other prompt,
    /// shows it at most three times a year and never in a TestFlight build.
    private func askForRating() {
        var prompt = store.ratePrompt
        let due = prompt.connected()
        let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        if due, scene != nil { prompt.asked() }
        store.ratePrompt = prompt
        if due, let scene = scene {
            AppLog.info("rating: asked (\(prompt.asks) of \(RatePrompt.maxAsks))")
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    // MARK: importing

    func handleIncoming(_ url: URL) async {
        if url.scheme?.lowercased() == "https" {
            await importLink(url.absoluteString, source: .link)
            return
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let host = (components.host ?? "").lowercased()
        guard ["install-sub", "install-config", "import", "add"].contains(host) else { return }
        var link = components.queryItems?.first { $0.name == "url" }?.value ?? ""
        if link.isEmpty, host == "import" || host == "add" {
            let prefix = "\(url.scheme ?? "")://\(host)/"
            link = String(url.absoluteString.dropFirst(prefix.count))
        }
        let name = components.queryItems?.first { $0.name == "name" }?.value ?? components.fragment
        if let n = name, !n.isEmpty, !link.contains("#") { link += "#" + n }
        await importLink(link, source: .link)
    }

    func importFromClipboard(_ link: String) async {
        // by account, not by text: the deleted link may carry a name or an earlier address
        guard link != clipboardTried, !EthaLink.sameAccount(link, store.deletedLink) else { return }
        clipboardTried = link
        await importLink(link, source: .clipboard)
    }

    func importLink(_ raw: String, source: ImportSource) async {
        guard let link = EthaLink.extract(from: raw) else {
            banner = BannerMessage(text: L(source == .paste || source == .clipboard ? "clipboard.nolink" : "link.invalid"), kind: .error)
            return
        }
        if source != .clipboard { store.deletedLink = nil }
        refreshing = true
        defer { refreshing = false }
        do {
            let snap = try await importer.fetchAndStore(link: link)
            await afterFetch()
            banner = BannerMessage(text: L("link.added"), kind: .ok)
            AppLog.info("import (\(source.rawValue)): \(snap.lines.count) lines")
            if !vpn.isActive, phase == .idle { await connectTapped() }
        } catch {
            AppLog.warn("import (\(source.rawValue)) failed: \(error)")
            banner = BannerMessage(text: importer.message(for: error), kind: .error)
        }
    }

    // MARK: refreshing

    @discardableResult
    func refreshQuietly(reason: String) async -> Bool {
        guard hasSubscription, !refreshing else { return false }
        refreshing = true
        defer { refreshing = false }
        do {
            _ = try await importer.refresh()
            await afterFetch()
            AppLog.info("quiet refresh (\(reason)) ok")
            return true
        } catch {
            AppLog.warn("quiet refresh (\(reason)) failed: \(error)")
            return false
        }
    }

    /// Refresh: the configs fetched now, with a word at the end.
    func refreshNow() async {
        guard hasSubscription, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            _ = try await importer.refresh()
            await afterFetch()
            banner = BannerMessage(text: L("refreshed"), kind: .ok)
        } catch {
            banner = BannerMessage(text: importer.message(for: error), kind: .error)
        }
    }

    /// After any fetch: the screen, and the running tunnel told to reload when the lines changed (it holds the set it
    /// started with).
    private func afterFetch() async {
        reload()
        if store.linesChanged {
            store.linesChanged = false
            if vpn.isActive {
                AppLog.info("the fetch brought other lines: the tunnel reloads")
                _ = await vpn.send(.reload)
                await pollStatus()
            }
        }
    }

    // MARK: connecting

    func connectTapped() async {
        guard hasSubscription else { return }
        if vpn.isActive {
            phase = .disconnecting
            vpn.stop()
            guardPhase(.disconnecting, seconds: Etha.connectGuard)
            return
        }
        phase = .connecting
        // The line to start on: the best of results younger than delayFresh; else the line used last; else the first.
        // Nothing is waited for: the extension measures every line through the running core as soon as the tunnel is
        // up and moves new connections to a better one by itself (AutoEngine).
        let selectedOk = selection.selectedLineId.map { id in lines.contains { $0.id == id } } ?? false
        let selected = selectedOk ? selection.selectedLineId : nil
        let lastMeasured = [selection.lastTestAt, store.tunnelState.lastRoundAt].compactMap { $0 }.max()
        let start = AutoSelect.resultsFresh(lastTestAt: lastMeasured) ? (AutoSelect.best(candidates) ?? selected) : selected
        guard let chosen = start ?? lines.first?.id else {
            phase = .idle
            banner = BannerMessage(text: L("no.line"), kind: .error)
            return
        }
        store.updateSelection { $0.selectedLineId = chosen; $0.pinned = false }
        selection = store.selection
        await startTunnel()
    }

    private func startTunnel() async {
        guard let id = selection.selectedLineId else { phase = .idle; return }
        do {
            try await vpn.start(lineId: id)
            guardPhase(.connecting, seconds: Etha.connectGuard)
        } catch {
            phase = .idle
            AppLog.error("start failed: \(error)")
            let denied = (error as NSError).domain == NEVPNErrorDomain && (error as NSError).code == NEVPNError.configurationReadWriteFailed.rawValue
            banner = BannerMessage(text: L(denied ? "vpn.denied" : "vpn.failed"), kind: .error)
        }
    }

    /// The system answers with a status change; if none comes, the button must not stay dead.
    private func guardPhase(_ expected: Phase, seconds: TimeInterval) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self = self, self.phase == expected else { return }
            self.phase = .idle
        }
    }

    // MARK: testing

    /// Test latency: connected, the extension measures every line through the running core and says what it did
    /// (switched, kept, none); disconnected, a temporary Xray in this process measures them (LineTester) and the best is
    /// the line the next Connect starts on. Either way the result is kept for the box (LineReport) and a quiet fetch
    /// carries it there. No line is named.
    func testLatency() async {
        guard hasSubscription, !testing, phase == .idle else { return }
        testing = true
        outcomeKey = nil
        defer { testing = false }
        if vpn.isActive {
            let started = Date()
            if let reply = await vpn.send(.ping) {
                take(reply)
                switch reply.outcome {
                case "switched": outcomeKey = "switched.faster"
                case "kept": outcomeKey = "on.fastest"
                default: outcomeKey = "no.line.answers"
                }
            }
            refreshTunnelResults()
            AppLog.info(String(format: "test: %d lines through the tunnel in %.1f s: %@", lines.count, Date().timeIntervalSince(started), outcomeKey ?? "?"))
            await refreshQuietly(reason: "report")   // the report of that test reaches the box now
            return
        }
        store.updateSelection { $0.results = [:] }
        selection = store.selection
        let started = Date()
        let results = await LineTester.testAll(lines, bindInterface: nil)
        store.updateSelection { $0.results = results; $0.lastTestAt = Date() }
        selection = store.selection
        let best = AutoSelect.best(candidates)
        if let best = best { store.updateSelection { $0.selectedLineId = best }; selection = store.selection }
        let bestMs = best.map { results[$0] ?? -1 } ?? -1
        let ordered = lines.sorted { $0.order < $1.order }
        if let report = LineReport.build(now: Date(), trigger: "manual", inUseRemark: ordered.first { $0.id == best }?.remark, switched: false,
                                         results: ordered.map { ($0.remark, results[$0.id] ?? 0) }) {
            store.updateTunnelState { $0.lineReport = report }
        }
        let summary = ordered.map { line -> String in
            let ms = results[line.id] ?? 0
            return "\(line.displayName)=\(ms > 0 ? "\(ms)ms" : (ms < 0 ? "failed" : "untested"))"
        }.joined(separator: ", ")
        AppLog.info(String(format: "test: %d lines in %.1f s, tunnel down: %@", lines.count, Date().timeIntervalSince(started), summary))
        if bestMs > 0 {
            outcomeKey = "ready"
            banner = BannerMessage(text: L("ready.ms", bestMs), kind: .ok)
        } else {
            outcomeKey = "no.line.answers"
            banner = BannerMessage(text: L("no.line"), kind: .error)
        }
        await refreshQuietly(reason: "report")
    }

    // MARK: delete account

    func deleteAccount() async {
        let link = snapshot?.url
        if vpn.isActive { vpn.stop() }
        await vpn.remove()
        RefreshScheduler.cancel()
        store.wipe(rememberingDeletedLink: link)
        clipboardTried = nil
        tunnel = nil
        phase = .idle
        searching = false; testing = false; latencyMs = 0; latencyAt = nil; outcomeKey = nil
        reload()
        banner = BannerMessage(text: L("delete.done"), kind: .ok)
        AppLog.info("account deleted from this phone")
    }
}
