import Foundation
import SkyRayCore
import SkyRayXray

/// SkyRay's Auto in the extension — the same design as the Android service's EthaAuto. The tunnel's Xray holds every
/// line of the subscription behind one random balancer (XrayConfigBuilder.autoConfig); this holds the balancer to one
/// line (libXray's balancer override through the API inbound) and measures the lines through that same Xray — a
/// loopback HTTP inbound per line, two HEAD requests down one kept-alive connection, the smaller time kept. The rules
/// are AutoPolicy's:
///
///   - at start every line is measured at once and new connections move to the best when the line in use failed or is
///     beaten by the margin; a change of line cuts nothing that is open;
///   - while the tunnel is in use (traffic within idleSec) every line is measured again every roundSec, a failed line
///     every failedRetrySec; idle, nothing runs;
///   - a stall — bytes out, none back for stallSec, read from hev's counters every tick — probes the line in use at
///     once, and a failed probe moves to the best of the rest, measured anew; a pinned line is never moved;
///   - every measurement lands in the App Group (TunnelState.results) for the app's picker; a move is reported to the
///     provider, which tells the app.
///
/// All state lives on the provider's queue; the measurements themselves run off it and come back to it.
final class AutoEngine {
    struct Line {
        let id: String
        let remark: String
        let order: Int
        let probePort: Int
    }

    private let queue: DispatchQueue
    private let store: SkyRayStore
    private let log: RingLog
    private let lines: [Line]
    private let policy: AutoPolicy
    private let apiPort: Int
    private let traffic: () -> (up: Int64, down: Int64)
    private let onSwitch: (Line, String, Bool) -> Void
    private let measureQueue = DispatchQueue(label: "com.allion.skyray.tunnel.measure", attributes: .concurrent)

    private(set) var current: String
    private var results: [String: Int64] = [:]
    private var probedAt: [String: Date] = [:]
    private var samples: [AutoPolicy.Sample] = []
    private var lastTrafficAt = Date()
    private var lastRoundAt = Date.distantPast
    private var lastStallProbeAt = Date.distantPast
    private var timer: DispatchSourceTimer?
    private var measuring = false
    private var paused = false
    private var stopped = false

    private static let tick: TimeInterval = 4
    private static let samplesKept = 16
    private static let stallProbeGap: TimeInterval = 20
    private static let networkSettle: TimeInterval = 15
    /// the first race measures every line at once, within what the extension's memory allows
    private static let raceConcurrency = 16

    init(queue: DispatchQueue, store: SkyRayStore, log: RingLog, lines: [Line], policy: AutoPolicy, apiPort: Int, current: String,
         traffic: @escaping () -> (up: Int64, down: Int64), onSwitch: @escaping (Line, String, Bool) -> Void) {
        self.queue = queue; self.store = store; self.log = log; self.lines = lines; self.policy = policy; self.apiPort = apiPort
        self.current = current; self.traffic = traffic; self.onSwitch = onSwitch
    }

    func start() {
        log.info("auto: \(lines.count) lines behind the balancer, starting on \(name(current)); round \(policy.roundSec) s, failed \(policy.failedRetrySec) s, idle \(policy.idleSec) s, margin \(policy.marginPct) % / \(policy.floorMs) ms, stall \(policy.stallSec) s, timeout \(policy.probeTimeoutSec) s")
        race(reason: "connect", byHand: false) { _ in }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + AutoEngine.tick, repeating: AutoEngine.tick)
        t.setEventHandler { [weak self] in self?.tickNow() }
        t.resume()
        timer = t
    }

    func stop() {
        stopped = true
        timer?.cancel(); timer = nil
    }

    func pause() { paused = true }

    func resume() { paused = false; samples.removeAll() }

    /// Wi-Fi ↔ mobile: what was measured no longer holds; measure again once the network has settled.
    func onNetworkChanged() {
        samples.removeAll()
        queue.asyncAfter(deadline: .now() + AutoEngine.networkSettle) { [weak self] in
            guard let self = self, !self.stopped else { return }
            self.race(reason: "network", byHand: false) { _ in }
        }
    }

    /// The customer asked for every line to be measured now (Ping all, or Auto chosen again after a pick):
    /// completion(moved) on the queue.
    func pingAll(completion: @escaping (Bool) -> Void) {
        race(reason: "asked", byHand: true, completion: completion)
    }

    /// One measurement of the line in use (the app's "probe", the chip's number): ms or -1, on the queue.
    func probeCurrent(completion: @escaping (Int64) -> Void) {
        guard let line = lines.first(where: { $0.id == current }) else { completion(-1); return }
        measure([line], concurrency: 1) { r in completion(r[line.id] ?? -1) }
    }

    /// New connections take the line now; what is open stays where it is. byHand: the customer's pick.
    @discardableResult
    func switchTo(id: String, reason: String, byHand: Bool) -> Bool {
        guard let line = lines.first(where: { $0.id == id }) else { return false }
        do {
            try LibXrayBridge.balancerOverride(api: "127.0.0.1:\(apiPort)", balancer: Etha.autoBalancerTag, target: XrayConfigBuilder.lineTag(id))
        } catch {
            log.error("auto: the balancer refused \(line.remark): \(error)")
            return false
        }
        current = id
        log.info("auto: new connections take \(line.remark) (\(reason))")
        onSwitch(line, reason, byHand)
        return true
    }

    // MARK: the loop

    private func tickNow() {
        guard !paused, !stopped else { return }
        let now = Date()
        sample(now)
        if !measuring, !pinned, policy.stalled(samples, now: now), now.timeIntervalSince(lastStallProbeAt) >= AutoEngine.stallProbeGap {
            lastStallProbeAt = now
            stallProbe()
            return
        }
        let inUse = now.timeIntervalSince(lastTrafficAt) < TimeInterval(policy.idleSec)
        if !measuring, inUse, now.timeIntervalSince(lastRoundAt) >= TimeInterval(policy.roundSec) { round() }
    }

    private func sample(_ now: Date) {
        let t = traffic()
        if let last = samples.last, t.up != last.up || t.down != last.down { lastTrafficAt = now }
        samples.append(AutoPolicy.Sample(at: now, up: t.up, down: t.down))
        if samples.count > AutoEngine.samplesKept { samples.removeFirst(samples.count - AutoEngine.samplesKept) }
    }

    /// The line in use looks dead: one probe of it; failed, the rest measured anew and the best takes over.
    private func stallProbe() {
        guard let line = lines.first(where: { $0.id == current }) else { return }
        measure([line], concurrency: 1) { [weak self] r in
            guard let self = self else { return }
            if (r[line.id] ?? -1) > 0 { return }
            self.log.warn("auto: \(line.remark) did not answer after a stall")
            let rest = self.lines.filter { $0.id != self.current }
            self.measure(rest, concurrency: min(rest.count, AutoEngine.raceConcurrency)) { [weak self] _ in
                guard let self = self else { return }
                self.lastRoundAt = Date()
                _ = self.decide(reason: "stall", byHand: false)
            }
        }
    }

    private func round() {
        lastRoundAt = Date()
        let now = Date()
        let due = lines.filter { policy.due(now: now, probedAt: probedAt[$0.id], failed: (results[$0.id] ?? 0) < 0) }
        if due.isEmpty { return }
        measure(due, concurrency: policy.concurrency) { [weak self] _ in
            _ = self?.decide(reason: "round", byHand: false)
        }
    }

    private func race(reason: String, byHand: Bool, completion: @escaping (Bool) -> Void) {
        measure(lines, concurrency: min(lines.count, AutoEngine.raceConcurrency)) { [weak self] _ in
            guard let self = self else { completion(false); return }
            self.lastRoundAt = Date()
            completion(self.decide(reason: reason, byHand: byHand))
        }
    }

    /// The lines measured off the queue, at most concurrency at once (a request that arrives while one runs waits its
    /// turn); the results, the App Group and the completion back on the queue.
    private func measure(_ which: [Line], concurrency: Int, completion: @escaping ([String: Int64]) -> Void) {
        if which.isEmpty || stopped { completion([:]); return }
        if measuring {
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.measure(which, concurrency: concurrency, completion: completion) }
            return
        }
        measuring = true
        let timeout = policy.probeTimeoutSec
        let slots = DispatchSemaphore(value: max(1, concurrency))
        let group = DispatchGroup()
        let lock = NSLock()
        var out: [String: Int64] = [:]
        for line in which {
            group.enter()
            measureQueue.async {
                slots.wait()
                let probe = Probe(port: line.probePort, timeoutSeconds: timeout)
                let ms = probe.measureLine()
                probe.invalidate()
                slots.signal()
                lock.lock(); out[line.id] = ms; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: queue) { [weak self] in
            guard let self = self else { return }
            let now = Date()
            for (id, ms) in out { self.results[id] = ms; self.probedAt[id] = now }
            let snapshot = self.results
            self.store.updateTunnelState { $0.results = snapshot; $0.lastRoundAt = now }
            let summary = which.sorted { $0.order < $1.order }
                .map { l in "\(l.remark)=\(out[l.id].map { $0 > 0 ? "\($0)ms" : "failed" } ?? "?")" }.joined(separator: ", ")
            self.log.info("auto: measured \(out.count) lines in \(Int(Date().timeIntervalSince(now) * 1000)) ms after: \(summary)")
            self.measuring = false
            completion(out)
        }
    }

    private func decide(reason: String, byHand: Bool) -> Bool {
        let candidates = lines.map { AutoSelect.Candidate(id: $0.id, delayMs: results[$0.id] ?? 0, order: $0.order) }
        guard let target = policy.target(current: current, candidates: candidates, pinned: pinned) else { return false }
        return switchTo(id: target, reason: reason, byHand: byHand)
    }

    private var pinned: Bool { store.selection.pinned }
    private func name(_ id: String) -> String { lines.first { $0.id == id }?.remark ?? id }
}
