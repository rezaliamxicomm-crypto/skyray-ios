import Foundation
import SkyRayCore
import SkyRayXray

/// SkyRay's Auto in the extension — the same design as the Android service's EthaAuto. The tunnel's Xray holds every
/// line of the subscription behind one random balancer (XrayConfigBuilder.autoConfig); this holds the balancer to one
/// line (libXray's balancer override through the API inbound) and measures the lines through that same Xray — a
/// loopback HTTP inbound per line, two HEAD requests to the box's own probe target down one kept-alive connection,
/// the smaller time kept. The rules are AutoPolicy's:
///
///   - at start every line is measured at once and new connections move to the best when the line in use failed or is
///     beaten by the margin; a change of line cuts nothing that is open;
///   - while the tunnel is in use (traffic within idleSec) every line is measured again every roundSec, a failed line
///     every failedRetrySec; idle, nothing runs;
///   - a stall — bytes out, none back for stallSec, read from hev's counters every tick — probes the line in use at
///     once, and a failed probe moves to the best of the rest, measured anew;
///   - no line answers: the Searching state (TunnelState.searching) — every line again every searchSec, in use or
///     not; the app, seeing the state, fetches the subscription again for lines the box may have replaced;
///   - the line in use's time lands in the App Group as it is measured (TunnelState.latencyMs: the app's chip), every
///     round's results as the report the next fetch carries to the box (TunnelState.lineReport, the header
///     X-Etha-Lines); a move is reported to the provider, which tells the app.
///
/// Nobody picks a line by hand any more (2.0.0): the customer sees no line name, only the latency.
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
    private let onSwitch: (Line, String) -> Void
    private let measureQueue = DispatchQueue(label: "com.allion.skyray.tunnel.measure", attributes: .concurrent)

    private(set) var current: String
    private var results: [String: Int64] = [:]
    private var probedAt: [String: Date] = [:]
    private var samples: [AutoPolicy.Sample] = []
    private var lastTrafficAt = Date()
    private var lastRoundAt = Date.distantPast
    private var roundInterval: TimeInterval = 180   // this round's interval: roundSec with the jitter, drawn when a round ends
    private var lastStallProbeAt = Date.distantPast
    private var timer: DispatchSourceTimer?
    private var measuring = false
    private var paused = false
    private var stopped = false
    private(set) var searching = false
    private var probeURL = Etha.probeURL
    private var fallbackTried = false

    private static let tick: TimeInterval = 4
    private static let samplesKept = 16
    private static let stallProbeGap: TimeInterval = 20
    private static let networkSettle: TimeInterval = 15
    /// the first race measures every line at once, within what the extension's memory allows
    private static let raceConcurrency = 16

    init(queue: DispatchQueue, store: SkyRayStore, log: RingLog, lines: [Line], policy: AutoPolicy, apiPort: Int, current: String,
         traffic: @escaping () -> (up: Int64, down: Int64), onSwitch: @escaping (Line, String) -> Void) {
        self.queue = queue; self.store = store; self.log = log; self.lines = lines; self.policy = policy; self.apiPort = apiPort
        self.current = current; self.traffic = traffic; self.onSwitch = onSwitch
    }

    func start() {
        log.info("auto: \(lines.count) lines behind the balancer, starting on \(name(current)); round \(policy.roundSec) s, failed \(policy.failedRetrySec) s, idle \(policy.idleSec) s, search \(policy.searchSec) s, margin \(policy.marginPct) % / \(policy.floorMs) ms, stall \(policy.stallSec) s")
        roundInterval = TimeInterval(policy.roundSec)
        race(reason: "connect") { [weak self] _ in self?.scheduleSettle() }
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
            self.race(reason: "network") { [weak self] _ in self?.scheduleSettle() }
        }
    }

    /// The first race measures every line at once on a core a second old and reads high: a settling round with the
    /// normal concurrency, settleSec later, corrects the pick within seconds instead of at the next round.
    private func scheduleSettle() {
        guard policy.settleSec > 0 else { return }
        queue.asyncAfter(deadline: .now() + TimeInterval(policy.settleSec)) { [weak self] in
            guard let self = self, !self.stopped, !self.searching else { return }
            self.log.info("auto: the settling round")
            self.measure(self.lines, concurrency: self.policy.concurrency) { [weak self] _ in
                guard let self = self else { return }
                self.markRound()
                let moved = self.decide(reason: "settle")
                self.report(trigger: "settle", switched: moved)
                self.updateSearching()
            }
        }
    }

    /// A round ended now; the next one comes after roundSec give or take the jitter.
    private func markRound() {
        lastRoundAt = Date()
        roundInterval = policy.jitteredRound(using: Double.random(in: 0..<1))
    }

    /// The customer pressed Test latency: every line measured now, the decision made, the outcome said —
    /// "switched", "kept" or "none" (no line answers) — on the queue.
    func pingAll(completion: @escaping (String) -> Void) {
        race(reason: "manual", completion: completion)
    }

    /// New connections take the line now; what is open stays where it is.
    @discardableResult
    private func switchTo(id: String, reason: String) -> Bool {
        guard let line = lines.first(where: { $0.id == id }) else { return false }
        do {
            try LibXrayBridge.balancerOverride(api: "127.0.0.1:\(apiPort)", balancer: Etha.autoBalancerTag, target: XrayConfigBuilder.lineTag(id))
        } catch {
            log.error("auto: the balancer refused \(line.remark): \(error)")
            return false
        }
        current = id
        log.info("auto: new connections take \(line.remark) (\(reason))")
        onSwitch(line, reason)
        tellLatency()
        return true
    }

    // MARK: the loop

    private func tickNow() {
        guard !paused, !stopped else { return }
        let now = Date()
        sample(now)
        if !measuring, !searching, policy.stalled(samples, now: now), now.timeIntervalSince(lastStallProbeAt) >= AutoEngine.stallProbeGap {
            lastStallProbeAt = now
            stallProbe()
            return
        }
        if searching {
            if !measuring, now.timeIntervalSince(lastRoundAt) >= TimeInterval(policy.searchSec) { round() }
            return
        }
        let inUse = now.timeIntervalSince(lastTrafficAt) < TimeInterval(policy.idleSec)
        if !measuring, inUse, now.timeIntervalSince(lastRoundAt) >= roundInterval { round() }
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
            self.tellLatency()
            if (r[line.id] ?? -1) > 0 { return }
            self.log.warn("auto: \(line.remark) did not answer after a stall")
            let rest = self.lines.filter { $0.id != self.current }
            self.measure(rest, concurrency: min(rest.count, AutoEngine.raceConcurrency)) { [weak self] _ in
                guard let self = self else { return }
                self.markRound()
                let moved = self.decide(reason: "stall")
                self.report(trigger: "stall", switched: moved)
                self.updateSearching()
            }
        }
    }

    private func round() {
        let interval = roundInterval
        markRound()
        let now = Date()
        let due = searching ? lines : lines.filter { policy.due(now: now, probedAt: probedAt[$0.id], failed: (results[$0.id] ?? 0) < 0, roundInterval: interval) }
        if due.isEmpty { return }
        measure(due, concurrency: policy.concurrency) { [weak self] _ in
            guard let self = self else { return }
            let moved = self.decide(reason: "round")
            self.report(trigger: "auto", switched: moved)
            self.updateSearching()
        }
    }

    private func race(reason: String, completion: @escaping (String) -> Void) {
        measure(lines, concurrency: min(lines.count, AutoEngine.raceConcurrency)) { [weak self] _ in
            guard let self = self else { completion("none"); return }
            self.markRound()
            let moved = self.decide(reason: reason)
            self.report(trigger: reason, switched: moved)
            self.updateSearching()
            let answered = self.lines.contains { (self.results[$0.id] ?? 0) > 0 }
            completion(!answered ? "none" : (moved ? "switched" : "kept"))
        }
    }

    /// The lines measured off the queue, at most concurrency at once (a request that arrives while one runs waits its
    /// turn). When a full set gets no answer at all on the probe target, the fallback is tried once (a box that does
    /// not have the target yet); the results, the App Group and the completion come back on the queue.
    private func measure(_ which: [Line], concurrency: Int, completion: @escaping ([String: Int64]) -> Void) {
        if which.isEmpty || stopped { completion([:]); return }
        if measuring {
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.measure(which, concurrency: concurrency, completion: completion) }
            return
        }
        measuring = true
        let started = Date()
        measureOnce(which, concurrency: concurrency, url: probeURL) { [weak self] first in
            guard let self = self else { return }
            let full = which.count == self.lines.count
            if full, !first.isEmpty, first.values.allSatisfy({ $0 < 0 }), !self.fallbackTried {
                self.fallbackTried = true
                self.measureOnce(which, concurrency: concurrency, url: Etha.probeFallbackURL) { [weak self] again in
                    guard let self = self else { return }
                    if again.values.contains(where: { $0 > 0 }) {
                        self.log.warn("auto: the probe target gave no answer on any line; measuring with the fallback from now on")
                        self.probeURL = Etha.probeFallbackURL
                        self.finish(which, again, started: started, completion: completion)
                    } else {
                        self.finish(which, first, started: started, completion: completion)
                    }
                }
                return
            }
            self.finish(which, first, started: started, completion: completion)
        }
    }

    private func measureOnce(_ which: [Line], concurrency: Int, url: String, completion: @escaping ([String: Int64]) -> Void) {
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
                let ms = probe.measureLine(url: url)
                probe.invalidate()
                slots.signal()
                lock.lock(); out[line.id] = ms; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: queue) { completion(out) }
    }

    private func finish(_ which: [Line], _ out: [String: Int64], started: Date, completion: @escaping ([String: Int64]) -> Void) {
        let now = Date()
        for (id, ms) in out { results[id] = ms; probedAt[id] = now }
        let snapshot = results
        store.updateTunnelState { $0.results = snapshot; $0.lastRoundAt = now }
        let summary = which.sorted { $0.order < $1.order }
            .map { l in "\(l.remark)=\(out[l.id].map { $0 > 0 ? "\($0)ms" : "failed" } ?? "?")" }.joined(separator: ", ")
        log.info("auto: measured \(out.count) lines in \(Int(now.timeIntervalSince(started) * 1000)) ms after: \(summary)")
        if which.contains(where: { $0.id == current }) { tellLatency() }
        measuring = false
        completion(out)
    }

    private func decide(reason: String) -> Bool {
        let candidates = lines.map { AutoSelect.Candidate(id: $0.id, delayMs: results[$0.id] ?? 0, order: $0.order) }
        guard let target = policy.target(current: current, candidates: candidates, pinned: false) else { return false }
        return switchTo(id: target, reason: reason)
    }

    /// The line in use's time to the App Group: the app's chip.
    private func tellLatency() {
        let ms = results[current] ?? 0
        store.updateTunnelState { $0.latencyMs = ms; $0.latencyAt = Date() }
    }

    /// What this round measured, kept for the next fetch (the header X-Etha-Lines).
    private func report(trigger: String, switched: Bool) {
        let inUse = lines.first { $0.id == current }?.remark
        let header = LineReport.build(now: Date(), trigger: trigger, inUseRemark: inUse, switched: switched,
                                      results: lines.map { ($0.remark, results[$0.id] ?? 0) })
        if let h = header { store.updateTunnelState { $0.lineReport = h } }
    }

    /// Searching = every line measured and none answering; the App Group carries it to the app.
    private func updateSearching() {
        let dead = lines.allSatisfy { (results[$0.id] ?? 0) < 0 }
        if dead == searching { return }
        searching = dead
        log.info(dead ? "auto: no line answers — searching" : "auto: a line answers again")
        store.updateTunnelState { $0.searching = dead }
    }

    private func name(_ id: String) -> String { lines.first { $0.id == id }?.remark ?? id }
}
