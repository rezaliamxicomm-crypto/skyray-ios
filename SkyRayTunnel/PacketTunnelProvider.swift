import Foundation
import NetworkExtension
import Network
import SkyRayCore
import SkyRayXray

enum TunnelError: Error, CustomStringConvertible {
    case noSubscription
    case noTunFD
    var description: String {
        switch self {
        case .noSubscription: return "no subscription on this phone"
        case .noTunFD: return "the tunnel's file descriptor was not found"
        }
    }
}

/// Runs Xray on the utun file descriptor NetworkExtension hands us. The app writes the subscription and
/// the chosen line into the App Group; this side only reads them, runs the core, probes the line it is on
/// and answers the app's questions. Memory is the constraint (about 50 MiB for the whole process).
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let store = SkyRayStore.appGroup()
    private lazy var log = RingLog(url: store.tunnelLogURL)
    private let queue = DispatchQueue(label: "com.allion.skyray.tunnel")
    private var tunFD: Int32 = -1
    private var active: Line?
    private var probe: Probe?
    private var watchdog: Watchdog?
    private var memoryTimer: DispatchSourceTimer?
    private var pathMonitor: NWPathMonitor?
    private var pathWasSatisfied = true

    // MARK: lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        queue.async {
            guard let snapshot = self.store.loadSnapshot(), !snapshot.lines.isEmpty else {
                self.log.error("start: no subscription"); completionHandler(TunnelError.noSubscription); return
            }
            let wanted = (options?["lineId"] as? String) ?? self.store.selection.selectedLineId
            let line = snapshot.lines.first { $0.id == wanted } ?? snapshot.lines[0]
            self.setTunnelNetworkSettings(TunnelSettings.make()) { error in
                if let error = error {
                    self.log.error("settings: \(error)"); completionHandler(error); return
                }
                self.queue.async {
                    do {
                        guard let fd = TunFD.find() else { throw TunnelError.noTunFD }
                        self.tunFD = fd
                        try self.startXray(line)
                        let version = LibXrayBridge.xrayVersion()
                        self.store.updateTunnelState { $0.startedAt = Date(); $0.xrayVersion = version }
                        self.log.info("tunnel up: xray \(version), \(snapshot.lines.count) lines, fd \(fd)")
                        self.startWatchdog(lineCount: snapshot.lines.count)
                        self.startMemoryLog()
                        self.startPathMonitor()
                        completionHandler(nil)
                    } catch {
                        self.log.error("start: \(error)")
                        completionHandler(error)
                    }
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        queue.async {
            self.watchdog?.stop(); self.watchdog = nil
            self.memoryTimer?.cancel(); self.memoryTimer = nil
            self.pathMonitor?.cancel(); self.pathMonitor = nil
            try? LibXrayBridge.stopXray()
            self.active = nil
            self.store.updateTunnelState { $0.activeLineId = nil; $0.startedAt = nil }
            self.log.info("tunnel down: reason \(reason.rawValue)")
            completionHandler()
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        queue.async { self.watchdog?.pause(); completionHandler() }
    }

    override func wake() {
        queue.async { self.watchdog?.resume(after: 15) }
    }

    // MARK: Xray

    /// Xray gets a dup() of the utun fd: it may close its copy when it stops, and it is restarted on every
    /// line switch. A fresh loopback port carries the probe inbound.
    private func startXray(_ line: Line) throws {
        let xfd = dup(tunFD)
        guard xfd >= 0 else { throw TunnelError.noTunFD }
        let port = (try? LibXrayBridge.getFreePorts(1))?.first ?? 41_284
        let assets = Bundle.main.resourceURL?.path ?? Bundle.main.bundlePath
        let config = try XrayConfigBuilder.tunnelConfig(outboundJSON: line.outboundJSON, tunFD: xfd, assetDir: assets,
                                                        xrayLogPath: store.xrayLogURL.path, probePort: port)
        try LibXrayBridge.runXray(configJSON: config)
        active = line
        probe = Probe(port: port)
        store.updateTunnelState { $0.activeLineId = line.id; $0.switchedTo = nil; $0.switchedAt = nil }
        log.info("xray up: \(line.remark) (fd \(xfd), probe port \(port))")
    }

    private func switchLine(to line: Line, reason: String) {
        reasserting = true
        try? LibXrayBridge.stopXray()
        do {
            try startXray(line)
        } catch {
            reasserting = false
            log.error("switch to \(line.remark) failed: \(error)")
            cancelTunnelWithError(error)
            return
        }
        reasserting = false
        if !store.selection.pinned { store.updateSelection { $0.selectedLineId = line.id } }
        store.updateTunnelState { $0.switchedTo = line.displayName; $0.switchedAt = Date() }
        log.info("switched to \(line.remark): \(reason)")
    }

    // MARK: the watchdog

    private func startWatchdog(lineCount: Int) {
        guard lineCount >= 2, !store.selection.pinned else { log.info("watchdog off (pinned or a single line)"); return }
        let wd = Watchdog(queue: queue,
                          probe: { [weak self] in self?.probe?.measure() ?? -1 },
                          onProbe: { [weak self] ms in self?.recordProbe(ms) },
                          onFailure: { [weak self] tried in self?.rotate(tried: tried) ?? tried })
        wd.start(after: Etha.watchdogInterval)
        watchdog = wd
    }

    private func recordProbe(_ ms: Int64) {
        store.updateTunnelState { $0.lastProbeMs = ms; $0.lastProbeAt = Date() }
        if ms < 0 { log.warn("probe failed on \(active?.remark ?? "?")") }
    }

    /// Two misses in a row: the next line by the stored ranking (the extension cannot measure while Xray runs).
    private func rotate(tried: Set<String>) -> Set<String> {
        guard let current = active, let snapshot = store.loadSnapshot() else { return tried }
        guard let next = LineRotation.next(current: current.id, tried: tried, lines: snapshot.lines, results: store.selection.results) else {
            log.warn("watchdog: every line failed once, starting over")
            return []
        }
        guard let line = snapshot.lines.first(where: { $0.id == next.id }) else { return next.tried }
        switchLine(to: line, reason: "watchdog")
        return next.tried
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let satisfied = path.status == .satisfied
            if satisfied && !self.pathWasSatisfied {
                self.log.info("network is back; probing in 15 s")
                self.watchdog?.resume(after: 15)
            }
            self.pathWasSatisfied = satisfied
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    // MARK: memory

    private func startMemoryLog() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 30)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            let mb = MemoryFootprint.currentMB()
            self.store.updateTunnelState { $0.footprintMB = mb }
            let line = self.active?.remark ?? "?"
            if mb >= 38 { self.log.warn(String(format: "memory %.1f MiB on %@", mb, line)) }
            else { self.log.info(String(format: "memory %.1f MiB on %@", mb, line)) }
        }
        t.resume()
        memoryTimer = t
    }

    // MARK: messages from the app

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        queue.async {
            let request = (try? JSONDecoder().decode(TunnelRequest.self, from: messageData)) ?? TunnelRequest(cmd: "status")
            var reply = self.statusReply()
            switch request.cmd {
            case "probe":
                let ms = self.probe?.measure() ?? -1
                self.recordProbe(ms)
                reply = self.statusReply()
            case "switch":
                if let id = request.lineId, let line = self.store.loadSnapshot()?.lines.first(where: { $0.id == id }), line.id != self.active?.id {
                    self.switchLine(to: line, reason: "app")
                    reply = self.statusReply()
                }
            case "logTail":
                reply.log = self.log.tail(lines: request.lines ?? 200)
            default:
                break
            }
            completionHandler?(try? JSONEncoder().encode(reply))
        }
    }

    private func statusReply() -> TunnelReply {
        var r = TunnelReply()
        let state = store.tunnelState
        r.state = active == nil ? "stopped" : "connected"
        r.lineId = active?.id
        r.lineName = active?.displayName
        r.lastProbeMs = state.lastProbeMs
        r.lastProbeAt = state.lastProbeAt
        r.footprintMB = state.footprintMB
        r.switchedTo = state.switchedTo
        r.switchedAt = state.switchedAt
        r.xrayVersion = state.xrayVersion
        return r
    }
}
