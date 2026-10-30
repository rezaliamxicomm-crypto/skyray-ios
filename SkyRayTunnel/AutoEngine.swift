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
///   - a settling round settleSec after the connect race (the race reads high on a core a second old); while the
///     tunnel is in use (traffic within idleSec) every line is measured again roundSec after the last measurement
///     ended, give or take the jitter, a failed line only after failedRetrySec; idle, nothing runs, and traffic
///     returning brings a round at once; a network change is one normal round 15 s later — AutoSchedule is the one
///     clock for all of it; the box's probe target, and the fallback for one round at a time only;
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
    private var schedule = AutoSchedule()           // the one clock: the next round, the settling round, the retries, the target
    private var samples: [AutoPolicy.Sample] = []
    private var lastTrafficAt = Date()
    private var wasInUse = true
    private var lastStallProbeAt = Date.distantPast
    private var timer: DispatchSourceTimer?
    private var measuring = false
    private var paused = false
    private var stopped = false
    private(set) var searching = false

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
        log.info("auto: \(lines.count) lines behind the balancer, starting on \(name(current)); round \(policy.roundSec) s ±\(policy.jitterPct) %, settle \(policy.settleSec) s, failed \(policy.failedRetrySec) s, idle \(policy.idleSec) s, search \(policy.searchSec) s, margin \(policy.marginPct) % / \(policy.floorMs) ms, stall \(policy.stallSec) s")
        race(reason: "connect") { _ in }
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

    /// Wi-Fi ↔ mobile (or the path back after a gap): what was measured no longer holds. One normal round 15 s from
    /// now, every line, in use or not — not a race of every line at once — and a second event within a minute is the
    /// same event (AutoSchedule.networkChanged).
    func onNetworkChanged() {
        samples.removeAll()
        schedule.networkChanged(now: Date(), settle: AutoEngine.networkSettle)
        log.info("auto: the network changed; every line measured again in \(Int(AutoEngine.networkSettle)) s")
    }

    /// The settling round (AutoSchedule.settleAt): every line with the normal concurrency, settleSec after the connect
    /// race — the race measured every line at once on a core a second old and read high.
    private func settleRound() {
        log.info("auto: the settling round")
        measure(lines, concurrency: policy.concurrency) { [weak self] out in
            guard let self = self else { return }
            let moved = self.decide(reason: "settle")
            self.report(trigger: "settle", switched: moved)
            self.updateSearching()
            self.schedule.roundDone(now: Date(), results: out, policy: self.policy, draw: Double.random(in: 0..<1), searching: self.searching)
        }
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
        guard !measuring else { return }
        let inUse = now.timeIntervalSince(lastTrafficAt) < TimeInterval(policy.idleSec)
        if inUse, !wasInUse { schedule.wake(now: now); log.info("auto: traffic is back after the idle gap; measuring now") }
        wasInUse = inUse
        switch schedule.action(now: now, inUse: inUse, searching: searching) {
        case .settle: schedule.settleTaken(); settleRound()
        case .round: round()
        case nil: break
        }
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
            self.measure(rest, concurrency: min(rest.count, AutoEngine.raceConcurrency)) { [weak self] out in
                guard let self = self else { return }
                let moved = self.decide(reason: "stall")
                self.report(trigger: "stall", switched: moved)
                self.updateSearching()
                self.schedule.roundDone(now: Date(), results: out, policy: self.policy, draw: Double.random(in: 0..<1), searching: self.searching)
            }
        }
    }

    private func round() {
        let now = Date()
        let ids = Set(schedule.linesForRound(now: now, lines: lines.map { $0.id }, searching: searching))
        let due = lines.filter { ids.contains($0.id) }
        if due.isEmpty {   // every line failed and waits its retry: the clock moves on, nothing is measured
            schedule.roundDone(now: now, results: [:], policy: policy, draw: Double.random(in: 0..<1), searching: searching)
            return
        }
        let trigger = schedule.forced ? "network" : "auto"
        measure(due, concurrency: policy.concurrency) { [weak self] out in
            guard let self = self else { return }
            let moved = self.decide(reason: trigger)
            self.report(trigger: trigger, switched: moved)
            self.updateSearching()
            self.schedule.roundDone(now: Date(), results: out, policy: self.policy, draw: Double.random(in: 0..<1), searching: self.searching)
        }
    }

    private func race(reason: String, completion: @escaping (String) -> Void) {
        measure(lines, concurrency: min(lines.count, AutoEngine.raceConcurrency)) { [weak self] out in
            guard let self = self else { completion("none"); return }
            let moved = self.decide(reason: reason)
            self.report(trigger: reason, switched: moved)
            self.updateSearching()
            // a manual test's numbers are warm: no settling round after it
            self.schedule.raceDone(now: Date(), results: out, policy: self.policy, draw: Double.random(in: 0..<1), searching: self.searching, settle: reason == "connect")
            let answered = self.lines.contains { (self.results[$0.id] ?? 0) > 0 }
            completion(!answered ? "none" : (moved ? "switched" : "kept"))
        }
    }

    /// The lines measured off the queue, at most concurrency at once (a request that arrives while one runs waits its
    /// turn); the results, the App Group and the completion come back on the queue. The target: the box's own, and
    /// the fallback only for a round in which a full set got no answer from it at all — never for longer: a round on the
    /// fallback starts with one probe of the target and comes back to it the moment it answers (AutoSchedule.nextFallback).
    private func measure(_ which: [Line], concurrency: Int, completion: @escaping ([String: Int64]) -> Void) {
        if which.isEmpty || stopped { completion([:]); return }
        if measuring {
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.measure(which, concurrency: concurrency, completion: completion) }
            return
        }
        measuring = true
        let started = Date()
        let full = which.count == lines.count
        if schedule.fallback {
            let scout = which.first { $0.id == current } ?? which[0]
            measureOnce([scout], concurrency: 1, url: Etha.probeURL) { [weak self] one in
                guard let self = self else { return }
                let back = (one[scout.id] ?? -1) > 0
                self.schedule.fallback = AutoSchedule.nextFallback(current: true, fullSet: full, targetAnswered: back, fallbackAnswered: false)
                if back { self.log.info("auto: the probe target answers again; measuring against it") }
                self.measureOnce(which, concurrency: concurrency, url: back ? Etha.probeURL : Etha.probeFallbackURL) { [weak self] out in
                    self?.finish(which, out, started: started, completion: completion)
                }
            }
            return
        }
        measureOnce(which, concurrency: concurrency, url: Etha.probeURL) { [weak self] first in
            guard let self = self else { return }
            if full, !first.isEmpty, first.values.allSatisfy({ $0 < 0 }) {
                self.measureOnce(which, concurrency: concurrency, url: Etha.probeFallbackURL) { [weak self] again in
                    guard let self = self else { return }
                    let answered = again.values.contains { $0 > 0 }
                    self.schedule.fallback = AutoSchedule.nextFallback(current: false, fullSet: true, targetAnswered: false, fallbackAnswered: answered)
                    if answered { self.log.warn("auto: the probe target gave no answer on any line; this round measured against the fallback, the target is tried again next round") }
                    self.finish(which, answered ? again : first, started: started, completion: completion)
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
        for (id, ms) in out { results[id] = ms }
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
