import Foundation
import NetworkExtension
import Network
import SkyRayCore
import SkyRayXray
import SkyRayHev

enum TunnelError: Error, CustomStringConvertible {
    case noSubscription
    case noTunFD
    case hevExited(Int32)
    case balancer(String)
    var description: String {
        switch self {
        case .noSubscription: return "no subscription on this phone"
        case .noTunFD: return "the tunnel's file descriptor was not found"
        case .hevExited(let code): return "the packet tunnel stopped (code \(code))"
        case .balancer(let e): return "the balancer could not be held to the line: \(e)"
        }
    }
}

/// The shape of an iOS Xray tunnel that is known to fit the extension's memory: Xray listens on a loopback SOCKS5
/// port, hev-socks5-tunnel turns the utun's IP packets into SOCKS5 connections to it. The app writes the
/// subscription and the chosen line into the App Group; this side only reads them, runs the two and answers the
/// app's questions. Xray holds every line of the subscription behind one balancer, and AutoEngine holds the balancer
/// to the best line by measuring through that Xray — so a change of line never restarts anything (Auto's design,
/// 2026-10-29). Memory is the constraint (about 50 MiB for the whole process).
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let store = SkyRayStore.appGroup()
    private lazy var log = RingLog(url: store.tunnelLogURL)
    private let queue = DispatchQueue(label: "com.allion.skyray.tunnel")
    private let hev = HevTunnel()
    private var tunFD: Int32 = -1
    private var socksPort = Etha.socksPortFallback
    private var apiPort = Etha.apiPortFallback
    private var probePorts: [String: Int] = [:]
    private var lines: [Line] = []
    private var active: Line?
    private var engine: AutoEngine?
    private var memoryTimer: DispatchSourceTimer?
    private var pathMonitor: NWPathMonitor?
    private var pathWasSatisfied = true
    private var stopping = false
    private var memoryTicks = 0
    private var lastGuardAt = Date.distantPast
    /// iOS kills the extension at about 50 MiB; Xray restarted in place (hev stays, apps reconnect) costs a second.
    private let guardMB = 46.5

    // MARK: lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        queue.async {
            self.stopping = false
            guard let snapshot = self.store.loadSnapshot(), !snapshot.lines.isEmpty else {
                self.log.error("start: no subscription"); completionHandler(TunnelError.noSubscription); return
            }
            self.lines = snapshot.lines.sorted { $0.order < $1.order }
            let wanted = (options?["lineId"] as? String) ?? self.store.selection.selectedLineId
            let line = self.lines.first { $0.id == wanted } ?? self.lines[0]
            self.log.info(String(format: "start: %ld lines, memory %.1f MiB", self.lines.count, MemoryFootprint.currentMB()))
            self.setTunnelNetworkSettings(TunnelSettings.make()) { error in
                if let error = error {
                    self.log.error("settings: \(error)"); completionHandler(error); return
                }
                self.queue.async {
                    do {
                        guard let fd = TunFD.find(in: self) else { throw TunnelError.noTunFD }
                        self.tunFD = fd
                        self.assignPorts()
                        try self.startXray(on: line)
                        self.startHev()
                        let version = LibXrayBridge.xrayVersion()
                        self.store.updateTunnelState { $0.startedAt = Date(); $0.xrayVersion = version; $0.results = nil; $0.lastRoundAt = nil
                                                       $0.searching = nil; $0.outage = nil; $0.failoverAt = nil; $0.latencyMs = nil; $0.latencyAt = nil }
                        self.log.info("tunnel up: xray \(version), fd \(fd), socks \(self.socksPort), api \(self.apiPort)")
                        self.startEngine(on: line, policy: AutoPolicy.parse(snapshot.info.autoPolicy), hint: Hint.parse(snapshot.info.hint))
                        self.startMemoryLog()
                        self.startPathMonitor()
                        completionHandler(nil)
                    } catch {
                        self.log.error("start: \(error)")
                        try? LibXrayBridge.stopXray()
                        completionHandler(error)
                    }
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        queue.async {
            self.stopping = true
            self.engine?.stop(); self.engine = nil
            self.memoryTimer?.cancel(); self.memoryTimer = nil
            self.pathMonitor?.cancel(); self.pathMonitor = nil
            self.hev.stop()
            try? LibXrayBridge.stopXray()
            self.active = nil
            self.store.updateTunnelState { $0.activeLineId = nil; $0.startedAt = nil; $0.searching = nil; $0.outage = nil; $0.latencyMs = nil }
            self.log.info("tunnel down: reason \(reason.rawValue)")
            completionHandler()
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        queue.async { self.engine?.pause(); completionHandler() }
    }

    override func wake() {
        queue.async { self.engine?.resume() }
    }

    // MARK: the cores

    /// The loopback ports: SOCKS for hev, the API for the balancer, one probe inbound per line.
    private func assignPorts() {
        let wanted = 2 + lines.count
        if let ports = try? LibXrayBridge.getFreePorts(wanted), ports.count == wanted {
            socksPort = ports[0]; apiPort = ports[1]
            probePorts = Dictionary(uniqueKeysWithValues: zip(lines.map { $0.id }, ports.dropFirst(2)))
        } else {
            socksPort = Etha.socksPortFallback; apiPort = Etha.apiPortFallback
            probePorts = Dictionary(uniqueKeysWithValues: lines.enumerated().map { ($1.id, Etha.probePortFallback + $0) })
        }
    }

    /// Xray with every line behind the balancer, the balancer held to `line` before hev feeds it a single connection.
    private func startXray(on line: Line) throws {
        let assets = Bundle.main.resourceURL?.path ?? Bundle.main.bundlePath
        setenv("XRAY_LOCATION_ASSET", assets, 1)
        let entries = lines.map { (id: $0.id, outboundJSON: $0.outboundJSON, probePort: probePorts[$0.id] ?? Etha.probePortFallback) }
        let config = try XrayConfigBuilder.autoConfig(lines: entries, socksPort: socksPort, apiPort: apiPort,
                                                      assetDir: assets, xrayLogPath: store.xrayLogURL.path)
        try LibXrayBridge.runXray(configJSON: config)
        try holdBalancer(to: line)
        active = line
        store.updateTunnelState { $0.activeLineId = line.id; $0.switchedTo = nil; $0.switchedAt = nil }
        log.info("xray up, \(lines.count) lines, on \(line.remark)")
    }

    /// The API inbound answers as soon as Xray runs; a dial that lands before it listens is tried again.
    private func holdBalancer(to line: Line) throws {
        var lastError: Error?
        for attempt in 0..<5 {
            do {
                try LibXrayBridge.balancerOverride(api: "127.0.0.1:\(apiPort)", balancer: Etha.autoBalancerTag, target: XrayConfigBuilder.lineTag(line.id))
                return
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.1 * Double(attempt + 1))
            }
        }
        throw TunnelError.balancer("\(lastError.map { "\($0)" } ?? "?")")
    }

    /// hev-socks5-tunnel on the utun fd; its exit for any reason other than our stop takes the tunnel down.
    private func startHev() {
        let config = HevTunnel.config(mtu: Etha.tunnelMTU, ipv4: Etha.tunnelIPv4, ipv6: Etha.tunnelIPv6, socksPort: socksPort)
        hev.start(config: config, tunFD: tunFD) { [weak self] code in
            guard let self = self else { return }
            self.queue.async {
                guard !self.stopping else { return }
                self.log.error("hev-socks5-tunnel exited (\(code))")
                self.cancelTunnelWithError(TunnelError.hevExited(code))
            }
        }
    }

    private func startEngine(on line: Line, policy: AutoPolicy, hint: Hint?) {
        let members = lines.map { AutoEngine.Line(id: $0.id, remark: $0.remark, order: $0.order, probePort: probePorts[$0.id] ?? Etha.probePortFallback) }
        let engine = AutoEngine(queue: queue, store: store, log: log, lines: members, policy: policy, apiPort: apiPort, current: line.id,
                                network: networkSignature, hint: hint,
                                traffic: { [weak self] in
                                    let s = self?.hev.stats()
                                    return (up: Int64(s?.txBytes ?? 0), down: Int64(s?.rxBytes ?? 0))
                                },
                                onSwitch: { [weak self] member, reason in self?.lineChanged(to: member, reason: reason) })
        self.engine = engine
        engine.start()
    }

    /// The engine moved new connections to another line: the App Group learns it and it becomes the selection (the
    /// line the next Connect starts on). The customer is not told which line (2.0.0): only the latency changes.
    private func lineChanged(to member: AutoEngine.Line, reason: String) {
        guard let line = lines.first(where: { $0.id == member.id }) else { return }
        active = line
        store.updateSelection { $0.selectedLineId = line.id }
        store.updateTunnelState { state in
            state.activeLineId = line.id
            state.switchedTo = line.displayName; state.switchedAt = Date()
        }
    }

    /// The app fetched the subscription again and the lines changed: Xray restarts in place on the new set (hev stays,
    /// apps reconnect), the engine with it — the line in use kept when it is still there, else the first. The SOCKS and
    /// API ports stay (hev is bound to the first); a new line gets a probe port of its own.
    private func reloadLines() {
        guard let snapshot = store.loadSnapshot(), !snapshot.lines.isEmpty else { log.warn("reload: no subscription"); return }
        let fresh = snapshot.lines.sorted { $0.order < $1.order }
        let keep = fresh.first { $0.id == engine?.current } ?? fresh.first { $0.id == active?.id } ?? fresh[0]
        engine?.stop(); engine = nil
        lines = fresh
        let missing = lines.filter { probePorts[$0.id] == nil }
        if !missing.isEmpty {
            let ports = (try? LibXrayBridge.getFreePorts(missing.count)) ?? missing.indices.map { Etha.probePortFallback + 64 + $0 }
            for (line, port) in zip(missing, ports) { probePorts[line.id] = port }
        }
        reasserting = true
        try? LibXrayBridge.stopXray()
        do {
            try startXray(on: keep)
        } catch {
            reasserting = false
            log.error("reload on \(keep.remark) failed: \(error)")
            cancelTunnelWithError(error)
            return
        }
        reasserting = false
        store.updateTunnelState { $0.results = nil; $0.lastRoundAt = nil; $0.searching = nil }
        startEngine(on: keep, policy: AutoPolicy.parse(snapshot.info.autoPolicy), hint: Hint.parse(snapshot.info.hint))
        log.info("reload: xray restarted on \(fresh.count) lines, on \(keep.remark)")
    }

    /// The memory guard: Xray restarted in place on the line in use (hev stays, apps reconnect), the balancer held again.
    private func restartXrayInPlace() {
        guard let line = lines.first(where: { $0.id == engine?.current }) ?? active else { return }
        reasserting = true
        try? LibXrayBridge.stopXray()
        do {
            try startXray(on: line)
        } catch {
            reasserting = false
            log.error("restart on \(line.remark) failed: \(error)")
            cancelTunnelWithError(error)
            return
        }
        reasserting = false
        log.info("xray restarted in place on \(line.remark)")
    }

    /// "cell", "wifi" or "other": the network the phone is on, as Auto keeps its memory of the lines (and as the app
    /// remembers its fetch way; SubscriptionImporter.networkSignature reads the interfaces, this the path).
    private var networkSignature = "other"

    private static func signature(of path: Network.NWPath) -> String {   // qualified: NetworkExtension has an NWPath of its own
        if path.usesInterfaceType(.cellular) { return "cell" }
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) { return "wifi" }
        return "other"
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        networkSignature = PacketTunnelProvider.signature(of: monitor.currentPath)
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let satisfied = path.status == .satisfied
            let signature = PacketTunnelProvider.signature(of: path)
            if satisfied, signature == "other", self.networkSignature != "other" {   // the path over our own tunnel (2.1.1): no change of network
                self.pathWasSatisfied = satisfied
                return
            }
            if satisfied && (!self.pathWasSatisfied || signature != self.networkSignature) {
                self.log.info("network: \(self.networkSignature) → \(signature)\(self.pathWasSatisfied ? "" : " (back)"); measuring again in 15 s")
                self.networkSignature = signature
                self.engine?.onNetworkChanged(signature: signature)
            }
            self.pathWasSatisfied = satisfied
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    // MARK: memory

    private func startMemoryLog() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            let mb = MemoryFootprint.currentMB()
            self.store.updateTunnelState { $0.footprintMB = mb }
            self.memoryTicks += 1
            let s = self.hev.stats()
            let line = self.active?.remark ?? "?"
            let text = String(format: "memory %.1f MiB on %@, tx %.1f MiB rx %.1f MiB", mb, line, Double(s.txBytes) / 1_048_576, Double(s.rxBytes) / 1_048_576)
            if mb >= self.guardMB, Date().timeIntervalSince(self.lastGuardAt) > 45 {
                self.lastGuardAt = Date()
                self.log.warn(text + " — memory guard: restarting xray")
                self.restartXrayInPlace()
            } else if mb >= 38 {
                self.log.warn(text)
            } else if self.memoryTicks % 6 == 1 {
                self.log.info(text)
            }
        }
        t.resume()
        memoryTimer = t
    }

    // MARK: messages from the app

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        queue.async {
            let request = (try? JSONDecoder().decode(TunnelRequest.self, from: messageData)) ?? TunnelRequest(cmd: "status")
            let answer: () -> Void = { completionHandler?(try? JSONEncoder().encode(self.statusReply())) }
            if request.cmd == "status" { self.engine?.noteWatched() }   // the app's chip is on screen: the line in use is kept fresh for it
            switch request.cmd {
            case "probe", "ping":   // since 2.0.0 one thing: every line measured through the running core, the answer says what it did
                guard let engine = self.engine else { answer(); return }
                engine.pingAll { outcome in
                    var reply = self.statusReply()
                    reply.outcome = outcome
                    completionHandler?(try? JSONEncoder().encode(reply))
                }
            case "reload":
                self.reloadLines()
                answer()
            case "logTail":
                var reply = self.statusReply()
                reply.log = self.log.tail(lines: request.lines ?? 200)
                completionHandler?(try? JSONEncoder().encode(reply))
            default:
                answer()
            }
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
        r.searching = state.searching
        r.outage = state.outage
        r.failoverAt = state.failoverAt
        r.latencyMs = state.latencyMs
        r.latencyAt = state.latencyAt
        return r
    }
}
