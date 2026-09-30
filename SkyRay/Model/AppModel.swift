import Foundation
import Combine
import NetworkExtension
import SkyRayCore

struct BannerMessage: Equatable {
    enum Kind { case ok, error, info }
    let text: String
    let kind: Kind
    let id = UUID()
}

/// The one state object of the app: the subscription, the choice of line, the tunnel's status and the
/// actions the screens trigger. Mirrors the Android HomeActivity's logic.
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
    @Published var banner: BannerMessage?

    let store: SkyRayStore
    let vpn: VPNController
    private let importer: SubscriptionImporter
    private var cancellables: Set<AnyCancellable> = []
    private var clipboardTried: String?
    private var launched = false
    private var pendingConnect = false
    private var lastSwitchNoticed: Date?

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
    }

    var lines: [Line] { snapshot?.lines ?? [] }
    var hasSubscription: Bool { !(snapshot?.lines.isEmpty ?? true) }
    var isConnected: Bool { vpn.status == .connected }
    var currentLine: Line? {
        if let id = tunnel?.lineId, let l = lines.first(where: { $0.id == id }) { return l }
        if let id = selection.selectedLineId { return lines.first { $0.id == id } }
        return nil
    }

    var stateText: String {
        switch phase {
        case .finding: return L("state.finding")
        case .connecting: return L("state.connecting")
        case .disconnecting: return L("state.disconnecting")
        case .idle: break
        }
        switch vpn.status {
        case .connected: return L("state.connected")
        case .connecting, .reasserting: return L("state.connecting")
        case .disconnecting: return L("state.disconnecting")
        default: return L("state.notconnected")
        }
    }

    var busy: Bool { phase != .idle }

    func acceptDeclaration() {
        store.declarationAccepted = true
        declarationAccepted = true
    }

    // MARK: lifecycle

    func onLaunch() async {
        guard !launched else { return }
        launched = true
        // Every open starts in Auto (fastest): a line picked from the menu is pinned for the session only.
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
            phase = .idle
            Task { await self.probeNow(); DevTools.mirrorLogs(from: self.store) }
        case .disconnected, .invalid:
            if phase == .connecting || phase == .disconnecting { phase = .idle }
            tunnel = nil
        default:
            break
        }
    }

    func pollStatus() async {
        guard vpn.isActive else { tunnel = nil; return }
        if let reply = await vpn.send(.status) {
            tunnel = reply
            noticeSwitch(reply)
        }
    }

    private func probeNow() async {
        if let reply = await vpn.send(.probe) { tunnel = reply; noticeSwitch(reply) }
    }

    private func noticeSwitch(_ reply: TunnelReply) {
        guard let name = reply.switchedTo, let at = reply.switchedAt else { return }
        if let seen = lastSwitchNoticed, seen >= at { return }
        lastSwitchNoticed = at
        banner = BannerMessage(text: L("switched", name), kind: .info)
        selection = store.selection
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
            reload()
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
            reload()
            AppLog.info("quiet refresh (\(reason)) ok")
            return true
        } catch {
            AppLog.warn("quiet refresh (\(reason)) failed: \(error)")
            return false
        }
    }

    func refreshNow() async {
        guard hasSubscription, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let snap = try await importer.refresh()
            reload()
            banner = BannerMessage(text: L("servers.updated", Int64(snap.lines.count)), kind: .ok)
        } catch {
            banner = BannerMessage(text: importer.message(for: error), kind: .error)
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
        let selectedOk = selection.selectedLineId.map { id in lines.contains { $0.id == id } } ?? false
        if selection.pinned, selectedOk {
            await startTunnel()
        } else if selectedOk, AutoSelect.resultsFresh(lastTestAt: selection.lastTestAt) {
            if let best = AutoSelect.best(selection.candidates(lines)) { store.updateSelection { $0.selectedLineId = best } ; selection = store.selection }
            await startTunnel()
        } else {
            phase = .finding
            pendingConnect = true
            let guardTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Etha.testGuard * 1_000_000_000))
                guard let self = self, self.pendingConnect else { return }
                self.pendingConnect = false
                await self.connectWithBest()
            }
            await testAll()
            guardTask.cancel()
            if pendingConnect {
                pendingConnect = false
                await connectWithBest()
            }
        }
    }

    private func connectWithBest() async {
        let best = AutoSelect.best(selection.candidates(lines))
        let fallback = selection.selectedLineId.flatMap { id in lines.first { $0.id == id }?.id } ?? lines.first?.id
        guard let chosen = best ?? fallback else {
            phase = .idle
            banner = BannerMessage(text: L("no.line"), kind: .error)
            return
        }
        if best == nil { banner = BannerMessage(text: L("no.line"), kind: .info) }
        store.updateSelection { $0.selectedLineId = chosen }
        selection = store.selection
        phase = .connecting
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

    // MARK: testing and choosing

    /// Every line through libXray; results land in the selection as they arrive.
    func testAll() async {
        guard hasSubscription else { return }
        store.updateSelection { $0.results = [:] }
        selection = store.selection
        let iface = vpn.isActive ? NetworkInterfaces.physical() : nil
        let started = Date()
        let results = await LineTester.testAll(lines, bindInterface: iface)
        store.updateSelection { $0.results = results; $0.lastTestAt = Date() }
        selection = store.selection
        // Every test in the log: the numbers per line, the interface the measurement was bound to (only while
        // the tunnel is up) and how long the whole round took — the way to compare with the Android app.
        let summary = lines.sorted { $0.order < $1.order }.map { line -> String in
            let ms = results[line.id] ?? 0
            return "\(line.displayName)=\(ms > 0 ? "\(ms)ms" : (ms < 0 ? "failed" : "untested"))"
        }.joined(separator: ", ")
        AppLog.info(String(format: "test: %d lines in %.1f s, tunnel %@, interface %@: %@", lines.count, Date().timeIntervalSince(started),
                           vpn.isActive ? "up" : "down", iface ?? "-", summary))
    }

    /// "Ping all": every line measured, then the outcome said out loud — the fastest line (moved to, in Auto), or
    /// that the picked line stays and how to let Auto choose. Same as the Android app.
    func testAgain() async {
        guard hasSubscription, phase == .idle else { return }
        phase = .finding
        await testAll()
        phase = .idle
        let best = AutoSelect.best(selection.candidates(lines))
        if selection.pinned {
            if let kept = currentLine?.displayName { banner = BannerMessage(text: L("ping.kept", kept), kind: .info) }
            return
        }
        guard let best = best, let bestLine = lines.first(where: { $0.id == best }) else {
            banner = BannerMessage(text: L("no.line"), kind: .error); return
        }
        banner = BannerMessage(text: L("ping.best", bestLine.displayName), kind: .ok)
        if best != selection.selectedLineId {
            store.updateSelection { $0.selectedLineId = best }
            selection = store.selection
            if vpn.isActive, let reply = await vpn.send(.switchTo(best)) { tunnel = reply; noticeSwitch(reply) }
        }
    }

    /// A line from the menu pins it; Auto (nil) unpins and tests again.
    func pick(lineId: String?) async {
        if let id = lineId {
            store.updateSelection { $0.selectedLineId = id; $0.pinned = true }
            selection = store.selection
            if vpn.isActive, let reply = await vpn.send(.switchTo(id)) { tunnel = reply; noticeSwitch(reply) }
        } else {
            store.updateSelection { $0.pinned = false; $0.lastTestAt = nil }
            selection = store.selection
            if vpn.isActive {
                phase = .disconnecting
                vpn.stop()
                for _ in 0..<50 where vpn.isActive { try? await Task.sleep(nanoseconds: 100_000_000) }
                phase = .idle
                await connectTapped()
            }
        }
    }

    var serverRows: [ServerRows.Row] {
        ServerRows.rows(selection.candidates(lines), nameOf: { id in self.lines.first { $0.id == id }?.remark ?? id },
                        auto: L("auto"), untested: L("ping.untested"), failed: L("ping.failed"))
    }

    /// The server field: the chosen line (Android's selected server) with its last delay, or Auto.
    var serverLabel: String {
        let id = selection.selectedLineId
        let name = id.flatMap { sid in lines.first { $0.id == sid }?.remark }
        let delay = id.map { selection.delay(of: $0) } ?? 0
        return ServerRows.currentLabel(pinned: selection.pinned, currentName: name, delayMs: delay, auto: L("auto"), autoPicked: { L("auto.picked", $0) })
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
        reload()
        banner = BannerMessage(text: L("delete.done"), kind: .ok)
        AppLog.info("account deleted from this phone")
    }
}
