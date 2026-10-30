import Foundation
import SkyRayCore
import SkyRayXray

/// SkyRay's Auto in the extension — the same design as the Android service's EthaAuto (2.1). The tunnel's Xray holds
/// every line of the subscription behind one random balancer (XrayConfigBuilder.autoConfig); this holds the balancer to
/// one line (libXray's balancer override through the API inbound) and measures the lines through that same Xray — a
/// loopback HTTP inbound per line, two HEAD requests to the box's own probe target down one kept-alive connection, the
/// smaller time kept. The rules are the pure objects': AutoSchedule (when), AutoDecision (whether to move), LineHealth
/// (what is known of each line on this network), AutoPolicy (the numbers), Hint (the box's advice):
///
///   - no bursts: after Connect the line in use is probed first (its number on the chip within a second), then the
///     first pass — every other line, two at a time, a step a second, best-known first (this network's memory, else the
///     box's hint, else the subscription's order); then the steady trickle, one probe per roundSec/N, give or take the
///     jitter, only while the radio is warm (bytes moved within warmSec) or the app is on screen (status requests);
///     the line in use every currentSec while on screen; a pass ended is a decision and a report;
///   - moves (AutoDecision): the first pass corrects a cold pick once, for a line clearly better; steady state moves only
///     for a lead that persists over two pass ends (or is twice the margin), never within the dwell; a manual test by
///     the margin alone. A change of line moves new connections only and cuts nothing that is open;
///   - failover, make-before-break: a stall (bytes out, none back for stallSec) or a failed probe of the line in use
///     probes the line in use and the best-known alternative together within failoverMs; the line in use answering
///     means nothing happens; it failing and the alternative answering moves at once; the alternative failing too tries
///     the next best once; then Searching. The app is asked for one quiet fetch after a failover (TunnelState.failoverAt);
///   - a failed line backs off (15 → 30 → 60 → 120 min) and the memory of the network is kept across sessions
///     (SkyRayStore.lineHealth); a network change forgives every line and restarts the first pass in 15 s; idle, nothing
///     runs, and traffic returning probes the line in use at once;
///   - Searching (no line answers): the fast trickle over every line, retries ignored, until one answers; the app, seeing
///     the state, fetches the subscription again; the hint's outage flag changes the text ("it is not you");
///   - the box's probe target, the fallback only while the target answers nobody (one probe of the line in use against
///     the fallback decides, the first probe of every pass is a scout back);
///   - what is measured goes to the App Group as it lands (the chip), every pass as the report the next fetch carries to
///     the box (TunnelState.lineReport, the header X-Etha-Lines) with the best five-second download rate seen on the
///     line in use during the pass — the passive throughput figure the box's ranking folds in.
///
/// Nobody picks a line by hand any more (2.0.0): the customer sees no line name, only the latency.
/// All state lives on the provider's queue; the measurements themselves run off it and come back to it.
final class AutoEngine {
    struct Line {
        let id: String
        let remark: String
        let order: Int
        let probePort: Int
        var label: String { LineReport.label(remark) ?? remark }
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
    private var schedule = AutoSchedule()
    private var decision = AutoDecision()
    private var health: LineHealth
    private var network: String
    private var hint: Hint?
    private var samples: [AutoPolicy.Sample] = []
    private var rateSamples: [(at: Double, down: Int64)] = []
    private var passRateKbps: Int64 = 0
    private var lastTrafficAt: Double
    private var wasInUse = true
    private var lastStallProbeAt: Double = -1_000
    private var watchedAt: Double = -1_000
    private var timer: DispatchSourceTimer?
    private var measuring = false
    private var paused = false
    private var stopped = false
    private(set) var searching = false
    private var movedInPass = false
    private var probedSinceReport = Set<String>()
    private var searchSteps = 0

    private static let tick: TimeInterval = 1
    private static let samplesKept = 32
    private static let stallProbeGap: Double = 10
    private static let networkSettle: Double = 15
    private static let watchedFor: Double = 15
    private static let rateWindow: Double = 5
    private static let rateMinBytes: Int64 = 256 * 1024
    /// a manual test measures every line at once, within what the extension's memory allows
    private static let manualConcurrency = 16

    init(queue: DispatchQueue, store: SkyRayStore, log: RingLog, lines: [Line], policy: AutoPolicy, apiPort: Int, current: String,
         network: String, hint: Hint?, traffic: @escaping () -> (up: Int64, down: Int64), onSwitch: @escaping (Line, String) -> Void) {
        self.queue = queue; self.store = store; self.log = log; self.lines = lines; self.policy = policy; self.apiPort = apiPort
        self.current = current; self.traffic = traffic; self.onSwitch = onSwitch
        self.network = network; self.hint = hint
        self.health = store.lineHealth(on: network)
        self.lastTrafficAt = AutoEngine.mono()
    }

    static func mono() -> Double { ProcessInfo.processInfo.systemUptime }
    private static func wall() -> TimeInterval { Date().timeIntervalSince1970 }

    // MARK: the provider's calls

    func start() {
        let labels = lines.map { $0.label }
        // the start line: the best this network is known to have, else the hint's first, else what the provider chose
        if health.lastMs(label(current)) == nil {
            let best = health.bestKnown(labels) ?? hint?.arrange(labels).first { !(hint?.dead.contains($0) ?? false) }
            if let b = best, let line = lines.first(where: { $0.label == b }), line.id != current {
                switchTo(id: line.id, reason: health.bestKnown(labels) != nil ? "known best on \(network)" : "the box's advice")
            }
        }
        schedule.start(now: AutoEngine.mono(), order: order())
        log.info("auto: \(lines.count) lines behind the balancer, on \(name(current)); network \(network), \(health.entries.count) lines remembered\(hint.map { ", the box advises \($0.order.count) (\($0.dead.count) dead\($0.outage ? ", outage" : ""))" } ?? ""); a pass every \(policy.roundSec) s, the first at \(policy.firstPaceSec) s a step")
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + AutoEngine.tick, repeating: AutoEngine.tick)
        t.setEventHandler { [weak self] in self?.tickNow() }
        t.resume()
        timer = t
    }

    func stop() {
        stopped = true
        timer?.cancel(); timer = nil
        store.saveLineHealth(health, on: network)
    }

    func pause() { paused = true }

    func resume() { paused = false; samples.removeAll(); rateSamples.removeAll() }

    /// The app asked for the status: its chip is on screen, the line in use is kept fresh for it.
    func noteWatched() { watchedAt = AutoEngine.mono() }

    /// Wi-Fi ↔ mobile (or the path back after a gap): what was measured no longer holds. The memory of the new network
    /// takes over, every line is forgiven, the first pass restarts in 15 s; a second event within a minute is the same.
    func onNetworkChanged(signature: String) {
        if signature != network {
            store.saveLineHealth(health, on: network)
            network = signature
            health = store.lineHealth(on: network)
        }
        health.forgive()
        samples.removeAll(); rateSamples.removeAll()
        decision.firstSwitchDone = false
        let now = AutoEngine.mono()
        let before = schedule.lastNetworkAt
        schedule.networkChanged(now: now, settle: AutoEngine.networkSettle)
        if schedule.lastNetworkAt != before {
            schedule.order = order()
            log.info("auto: the network changed (\(network)); the first pass runs again from \(Int(AutoEngine.networkSettle)) s on")
        }
    }

    /// The customer pressed Test latency: every line measured now, the decision made by the margin alone, the outcome
    /// said — "switched", "kept" or "none" (no line answers) — on the queue; the trickle re-seeded best-first after it.
    func pingAll(completion: @escaping (String) -> Void) {
        if measuring {
            queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.pingAll(completion: completion) }
            return
        }
        measuring = true
        measureSet(lines, concurrency: min(lines.count, AutoEngine.manualConcurrency), timeoutMs: policy.probeTimeoutSec * 1000) { [weak self] out in
            guard let self = self else { completion("none"); return }
            let moved = self.decide(.manual, reason: "manual")
            self.report(trigger: "manual", switched: moved)
            self.updateSearching()
            if !self.searching { self.schedule.reseed(now: AutoEngine.mono(), order: self.order(), policy: self.policy, draw: Double.random(in: 0..<1)) }
            self.movedInPass = false
            self.measuring = false
            self.store.saveLineHealth(self.health, on: self.network)
            let answered = self.lines.contains { (self.results[$0.id] ?? 0) > 0 }
            completion(!answered ? "none" : (moved ? "switched" : "kept"))
        }
    }

    // MARK: the loop

    private func tickNow() {
        guard !paused, !stopped else { return }
        let now = AutoEngine.mono()
        sample(now)
        guard !measuring else { return }
        if !searching, policy.stalled(samples, now: Date()), now - lastStallProbeAt >= AutoEngine.stallProbeGap {
            lastStallProbeAt = now
            log.warn("auto: bytes out and none back for \(policy.stallSec) s on \(name(current))")
            failover(reason: "stall")
            return
        }
        let warm = now - lastTrafficAt < Double(policy.warmSec)
        let inUse = now - lastTrafficAt < Double(policy.idleSec)
        if inUse, !wasInUse { schedule.wake(now: now); log.info("auto: traffic is back after the idle gap; measuring now") }
        wasInUse = inUse
        let watched = now - watchedAt < AutoEngine.watchedFor
        let wall = AutoEngine.wall()
        let action = schedule.action(now: now, warm: warm, watched: watched, searching: searching, current: current,
                                     due: { id in self.health.due(self.label(id), now: wall) })
        switch action {
        case .probe(let ids)?:
            searching ? searchStep(ids) : probeLines(ids)
        case .probeCurrent?:
            probeCurrentLine()
        case nil:
            // a step whose time has come with nothing to probe (every other line waits its retry): spent
            if !searching, let n = schedule.nextProbeAt, now >= n, warm || watched || schedule.forced || schedule.phase == .first {
                schedule.nothingDue(now: now, policy: policy, draw: Double.random(in: 0..<1))
            }
        }
    }

    /// The counters every tick: traffic (the idle and warm clocks, the stall detector) and the download rate window.
    private func sample(_ now: Double) {
        let t = traffic()
        if let last = samples.last, t.up != last.up || t.down != last.down { lastTrafficAt = now }
        samples.append(AutoPolicy.Sample(at: Date(), up: t.up, down: t.down))
        if samples.count > AutoEngine.samplesKept { samples.removeFirst(samples.count - AutoEngine.samplesKept) }
        rateSamples.append((at: now, down: t.down))
        rateSamples.removeAll { now - $0.at > AutoEngine.rateWindow + AutoEngine.tick }
        if let base = rateSamples.first(where: { now - $0.at >= AutoEngine.rateWindow }) ?? rateSamples.first, now - base.at >= AutoEngine.rateWindow - 0.5 {
            let bytes = t.down - base.down
            if bytes >= AutoEngine.rateMinBytes {
                let kbps = Int64(Double(bytes) * 8 / (now - base.at) / 1000)
                passRateKbps = max(passRateKbps, kbps)
            }
        }
    }

    // MARK: the trickle

    /// The lines in the order the trickle takes them: what this network's memory knows good, by time; then the lines it
    /// has not seen, in the box's advised order where there is one (its dead ones last among them), else the
    /// subscription's; then the lines the memory holds as failed. By id.
    private func order() -> [String] {
        let labels = lines.map { $0.label }
        let good = health.bestFirst(labels).filter { health.lastMs($0) != nil && !health.isDead($0) }
        let unseen = labels.filter { health.lastMs($0) == nil && !health.isDead($0) }
        let dead = labels.filter { health.isDead($0) }
        let arranged = good + (hint?.arrange(unseen) ?? unseen) + dead
        return arranged.compactMap { l in lines.first { $0.label == l }?.id }
    }

    private func label(_ id: String) -> String { lines.first { $0.id == id }?.label ?? id }
    private func name(_ id: String) -> String { lines.first { $0.id == id }?.remark ?? id }
    private func line(_ id: String) -> Line? { lines.first { $0.id == id } }

    /// One step of the trickle (one line; two in the first pass): measured, recorded; the first pass may correct the
    /// start once; a wrapped rotation is a pass — the steady decision and the report.
    private func probeLines(_ ids: [String]) {
        let which = ids.compactMap { line($0) }
        guard !which.isEmpty else { return }
        let scout = schedule.fallback && schedule.cursor == 0   // the first probe of a pass on the fallback tries the target
        let url = schedule.fallback && !scout ? Etha.probeFallbackURL : Etha.probeURL
        measuring = true
        measureOnce(which, concurrency: which.count, url: url, timeoutMs: policy.probeTimeoutSec * 1000) { [weak self] out in
            guard let self = self else { return }
            if scout {
                let back = out.values.contains { $0 > 0 }
                self.schedule.fallback = AutoSchedule.nextFallback(current: true, targetAnswered: back, fallbackAnswered: false)
                if back { self.log.info("auto: the probe target answers again; measuring against it") }
            }
            self.record(out, which: which)
            let now = AutoEngine.mono()
            let first = self.schedule.phase == .first
            let passEnd = self.schedule.probed(now: now, ids: which.map { $0.id }, policy: self.policy, draw: Double.random(in: 0..<1))
            if first, self.decide(.first, reason: "first pass") { self.movedInPass = true }
            if passEnd {
                if !first, self.decide(.passEnd, reason: "pass end") { self.movedInPass = true }
                self.report(trigger: first ? "first" : "auto", switched: self.movedInPass)
                self.movedInPass = false
                self.passRateKbps = 0
                self.store.saveLineHealth(self.health, on: self.network)
            }
            self.updateSearching()
            self.measuring = false
        }
    }

    /// The line in use's own probe (every currentSec while the app is on screen, and when traffic returns): its number
    /// to the chip; failed, the failover.
    private func probeCurrentLine() {
        guard let l = line(current) else { return }
        measuring = true
        measureOnce([l], concurrency: 1, url: schedule.fallback ? Etha.probeFallbackURL : Etha.probeURL, timeoutMs: policy.probeTimeoutSec * 1000) { [weak self] out in
            guard let self = self else { return }
            self.record(out, which: [l])
            self.schedule.currentProbed(now: AutoEngine.mono(), policy: self.policy)
            self.measuring = false
            if (out[l.id] ?? -1) < 0 {
                self.log.warn("auto: \(l.remark) did not answer its probe")
                self.failover(reason: "probe")
            }
        }
    }

    /// Make-before-break: the line in use and the best-known alternative probed together within failoverMs. The line in
    /// use answering: nothing moves (a false alarm costs this one probe). It failing and the alternative answering: new
    /// connections move at once. The alternative failing too: the next best, once more; nothing: Searching decides.
    private func failover(reason: String, attempt: Int = 1) {
        guard let cur = line(current), !measuring else { return }
        let labels = lines.map { $0.label }
        let altLabel = health.bestKnown(labels, except: label(current))
            ?? hint?.arrange(labels).first { $0 != label(current) && !(hint?.dead.contains($0) ?? false) }
            ?? labels.first { $0 != label(current) }
        let alt = altLabel.flatMap { l in lines.first { $0.label == l } }
        var which = [cur]
        if let a = alt { which.append(a) }
        measuring = true
        measureOnce(which, concurrency: which.count, url: schedule.fallback ? Etha.probeFallbackURL : Etha.probeURL, timeoutMs: policy.failoverMs) { [weak self] out in
            guard let self = self else { return }
            self.record(out, which: which)
            self.measuring = false
            if (out[cur.id] ?? -1) > 0 {
                self.log.info("auto: \(cur.remark) answers within \(self.policy.failoverMs) ms (\(reason)): staying")
                return
            }
            if let a = alt, (out[a.id] ?? -1) > 0 {
                self.switchTo(id: a.id, reason: "failover after \(reason)")
                self.decision.moved(now: AutoEngine.mono())
                self.report(trigger: "failover", switched: true)
                self.store.updateTunnelState { $0.failoverAt = Date() }
                self.store.saveLineHealth(self.health, on: self.network)
                return
            }
            if attempt < 2, alt != nil {
                self.failover(reason: reason, attempt: attempt + 1)
                return
            }
            self.updateSearching()
        }
    }

    /// Searching: a step of the fast trickle (two lines, a second a step, every line in turn). The first to answer takes
    /// new connections; leaving the state re-seeds the trickle.
    private func searchStep(_ ids: [String]) {
        let which = ids.compactMap { line($0) }
        guard !which.isEmpty else { return }
        measuring = true
        measureOnce(which, concurrency: which.count, url: schedule.fallback ? Etha.probeFallbackURL : Etha.probeURL, timeoutMs: policy.probeTimeoutSec * 1000) { [weak self] out in
            guard let self = self else { return }
            self.record(out, which: which)
            self.schedule.searchStep(now: AutoEngine.mono(), count: which.count)
            self.searchSteps += 1
            if self.searchSteps % 30 == 0 { self.refreshHint() }
            if let found = which.first(where: { (out[$0.id] ?? -1) > 0 }), found.id != self.current {
                self.switchTo(id: found.id, reason: "a line answers again")
                self.decision.moved(now: AutoEngine.mono())
            }
            self.measuring = false
            self.updateSearching()
        }
    }

    // MARK: measuring

    /// A set of lines at once (a manual test): the box's target; nothing from it on any line and something from the
    /// fallback moves the probes to the fallback until the target answers again.
    private func measureSet(_ which: [Line], concurrency: Int, timeoutMs: Int, completion: @escaping ([String: Int64]) -> Void) {
        if which.isEmpty || stopped { completion([:]); return }
        if schedule.fallback {
            let scout = which.first { $0.id == current } ?? which[0]
            measureOnce([scout], concurrency: 1, url: Etha.probeURL, timeoutMs: timeoutMs) { [weak self] one in
                guard let self = self else { return }
                let back = (one[scout.id] ?? -1) > 0
                self.schedule.fallback = AutoSchedule.nextFallback(current: true, targetAnswered: back, fallbackAnswered: false)
                if back { self.log.info("auto: the probe target answers again; measuring against it") }
                self.measureOnce(which, concurrency: concurrency, url: back ? Etha.probeURL : Etha.probeFallbackURL, timeoutMs: timeoutMs) { [weak self] out in
                    guard let self = self else { return }
                    self.record(out, which: which); completion(out)
                }
            }
            return
        }
        measureOnce(which, concurrency: concurrency, url: Etha.probeURL, timeoutMs: timeoutMs) { [weak self] first in
            guard let self = self else { return }
            if which.count == self.lines.count, !first.isEmpty, first.values.allSatisfy({ $0 < 0 }) {
                self.measureOnce(which, concurrency: concurrency, url: Etha.probeFallbackURL, timeoutMs: timeoutMs) { [weak self] again in
                    guard let self = self else { return }
                    let answered = again.values.contains { $0 > 0 }
                    self.schedule.fallback = AutoSchedule.nextFallback(current: false, targetAnswered: false, fallbackAnswered: answered)
                    if answered { self.log.warn("auto: the probe target gave no answer on any line; measuring against the fallback until it answers again") }
                    let out = answered ? again : first
                    self.record(out, which: which); completion(out)
                }
                return
            }
            self.record(first, which: which); completion(first)
        }
    }

    private func measureOnce(_ which: [Line], concurrency: Int, url: String, timeoutMs: Int, completion: @escaping ([String: Int64]) -> Void) {
        let slots = DispatchSemaphore(value: max(1, concurrency))
        let group = DispatchGroup()
        let lock = NSLock()
        var out: [String: Int64] = [:]
        for line in which {
            group.enter()
            measureQueue.async {
                slots.wait()
                let probe = Probe(port: line.probePort, timeoutMs: timeoutMs)
                let ms = probe.measureLine(url: url)
                probe.invalidate()
                slots.signal()
                lock.lock(); out[line.id] = ms; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: queue) { completion(out) }
    }

    /// Results into the engine, the memory of the network and the App Group; the line in use's number to the chip.
    private func record(_ out: [String: Int64], which: [Line]) {
        let wall = AutoEngine.wall()
        for (id, ms) in out {
            results[id] = ms
            probedSinceReport.insert(id)
            if ms > 0 { health.ok(label(id), ms: ms, now: wall) } else { health.failed(label(id), now: wall, policy: policy) }
        }
        let snapshot = results
        store.updateTunnelState { $0.results = snapshot; $0.lastRoundAt = Date() }
        if which.count > 1 {
            let summary = which.sorted { $0.order < $1.order }
                .map { l in "\(l.remark)=\(out[l.id].map { $0 > 0 ? "\($0)ms" : "failed" } ?? "?")" }.joined(separator: ", ")
            log.info("auto: measured \(out.count) lines: \(summary)")
        } else if let l = which.first {
            log.info("auto: \(l.remark) \(out[l.id].map { $0 > 0 ? "\($0) ms" : "failed" } ?? "?")")
        }
        if which.contains(where: { $0.id == current }) { tellLatency() }
    }

    // MARK: deciding

    /// New connections take the line now; what is open stays where it is.
    @discardableResult
    private func switchTo(id: String, reason: String) -> Bool {
        guard let l = line(id) else { return false }
        do {
            try LibXrayBridge.balancerOverride(api: "127.0.0.1:\(apiPort)", balancer: Etha.autoBalancerTag, target: XrayConfigBuilder.lineTag(id))
        } catch {
            log.error("auto: the balancer refused \(l.remark): \(error)")
            return false
        }
        current = id
        passRateKbps = 0
        log.info("auto: new connections take \(l.remark) (\(reason))")
        onSwitch(l, reason)
        tellLatency()
        return true
    }

    private func decide(_ phase: AutoDecision.Phase, reason: String) -> Bool {
        let candidates = lines.map { AutoDecision.Candidate(id: $0.id, ms: results[$0.id] ?? 0, order: $0.order) }
        guard let cur = candidates.first(where: { $0.id == current }) else { return false }
        guard let target = decision.target(now: AutoEngine.mono(), phase: phase, current: cur, candidates: candidates, policy: policy) else { return false }
        return switchTo(id: target, reason: reason)
    }

    /// The line in use's time to the App Group: the app's chip.
    private func tellLatency() {
        let ms = results[current] ?? 0
        store.updateTunnelState { $0.latencyMs = ms; $0.latencyAt = Date() }
    }

    /// What was measured since the last report — the lines probed, not the ones waiting their retry with an old
    /// result — kept for the next fetch (the header X-Etha-Lines), with the pass's best download rate.
    private func report(trigger: String, switched: Bool) {
        let inUse = line(current)?.remark
        let header = LineReport.build(now: Date(), trigger: trigger, inUseRemark: inUse, switched: switched,
                                      results: lines.map { ($0.remark, probedSinceReport.contains($0.id) ? (results[$0.id] ?? 0) : 0) }, rateKbps: passRateKbps)
        if let h = header { store.updateTunnelState { $0.lineReport = h }; probedSinceReport.removeAll() }
    }

    /// Searching = every line measured and none answering. Before entering it the line in use is probed against the
    /// fallback once: an answer there means the target is down, not the lines, and the probes move to the fallback.
    /// Entering turns the clock to the fast trickle; leaving re-seeds it and reports.
    private func updateSearching() {
        let dead = !lines.isEmpty && lines.allSatisfy { (results[$0.id] ?? 0) < 0 }
        if dead, !searching, !schedule.fallback, !measuring, let cur = line(current) {
            measuring = true
            measureOnce([cur], concurrency: 1, url: Etha.probeFallbackURL, timeoutMs: policy.probeTimeoutSec * 1000) { [weak self] out in
                guard let self = self else { return }
                self.measuring = false
                if (out[cur.id] ?? -1) > 0 {
                    self.schedule.fallback = true
                    self.results[cur.id] = out[cur.id]
                    self.health.ok(self.label(cur.id), ms: out[cur.id]!, now: AutoEngine.wall())
                    self.tellLatency()
                    self.log.warn("auto: the probe target gave no answer on any line but the fallback answers on \(cur.remark): measuring against the fallback until the target answers again")
                } else {
                    self.enterSearching(true)
                }
            }
            return
        }
        if dead != searching { enterSearching(dead) }
    }

    /// The box's latest advice (the app's refetch while searching brings a fresh hint): the outage flag follows it.
    private func refreshHint() {
        guard let fresh = Hint.parse(store.loadSnapshot()?.info.hint) else { return }
        if fresh == hint { return }
        hint = fresh
        if searching {
            let outage = fresh.outage
            store.updateTunnelState { $0.outage = outage }
            log.info("auto: the box's advice changed while searching (outage: \(outage))")
        }
    }

    private func enterSearching(_ on: Bool) {
        searching = on
        let outage = on && (hint?.outage ?? false)
        log.info(on ? "auto: no line answers — searching\(outage ? " (the box says this network blocks every line right now)" : "")" : "auto: a line answers again")
        store.updateTunnelState { $0.searching = on; $0.outage = outage }
        let now = AutoEngine.mono()
        if on {
            searchSteps = 0
            schedule.searchingBegan(now: now)
            report(trigger: "search", switched: false)
        } else {
            schedule.reseed(now: now, order: order(), policy: policy, draw: Double.random(in: 0..<1))
            report(trigger: "search", switched: true)
        }
        store.saveLineHealth(health, on: network)
    }
}
