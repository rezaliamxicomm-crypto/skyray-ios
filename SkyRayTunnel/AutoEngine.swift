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
///     box's hint, else the subscription's order); then the steady trickle, one probe per roundSec/N over the lines that
///     can be probed (the line in use among them), give or take the jitter, only while the radio is warm (bytes moved
///     within warmSec) or the app is on screen (status requests); the line in use also every currentSec while on screen;
///     a pass ended — by its last probe or by a tail of lines waiting their retry — is a decision and a report;
///   - moves (AutoDecision): the first pass corrects a cold pick once, for a line clearly better; steady state moves only
///     for a lead that persists over two pass ends (or is twice the margin), never within the dwell; a manual test by
///     the margin alone. A change of line moves new connections only and cuts nothing that is open;
///   - failover, make-before-break: a stall (bytes out, none back for stallSec) or a failed full-window probe of the
///     line in use probes it and the best-known alternative together within failoverMs; the line in use answering
///     means nothing happens (and the alarm rests for a minute); it failing and the alternative answering moves at
///     once — only then is the old line held as failed; the alternative failing too tries the next, once; then
///     Searching. The short window condemns nobody by itself. The app is asked for one quiet fetch after a failover;
///   - a failed line backs off (15 → 30 → 60 → 120 min) and the memory of the network is kept across sessions
///     (SkyRayStore.lineHealth); a network change loads the new network's memory intact (leaving a dead line for its
///     known-good one at once) and restarts the first pass in 15 s; the same network coming back forgives every line;
///     idle, nothing runs; traffic returning probes the line in use once;
///   - Searching (nothing answers: every line failed or waits its retry, the line in use among the failed): every line
///     in turn, two at a time, each once per searchSec, three times slower when the box says the network blocks
///     everything, only warm or on screen after ten minutes; no failure is held against a line meanwhile, and leaving
///     forgives them all; the app, seeing the state, fetches the subscription again;
///   - the box's probe target, the fallback only while the target answers nobody (one probe of the line in use against
///     the fallback decides before Searching; every tenth probe while on the fallback is a scout back);
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
    private let idOf: [String: String]            // label → id

    private(set) var current: String
    private var results: [String: Int64] = [:]
    private var colds: [String: Int64] = [:]       // id → the connect time of the last probe: its first request, handshakes and all (2.1.1)
    private var firstReading = false               // the line in use has answered once since Connect; before that the chip stays "Connecting…"
    private var earlyRetried = false               // the first probe after Connect failed and was given a second try
    private var startedAt: Double = 0
    private var lastPassWall = Date()              // when the whole picture was last measured (a pass end); wall time: the clock sleeps with the phone
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
    private var stallQuietUntil: Double = 0
    private var watchedAt: Double = -1_000
    private var timer: DispatchSourceTimer?
    private var timerSuspended = false
    private var measuring = false
    private var paused = false
    private var stopped = false
    private(set) var searching = false
    private var movedInPass = false
    private var movedWhileSearching = false
    private var probedSinceReport = Set<String>()
    private var probesThisPass = 0
    private var searchSteps = 0

    private static let tick: TimeInterval = 1
    private static let samplesKept = 32
    private static let stallProbeGap: Double = 10
    private static let stallFalseAlarmRest: Double = 60
    private static let networkSettle: Double = 5         // 15 until 2.1.0; Connect itself no longer counts as a change
    private static let startDelay: Double = 2            // the first probe after Connect waits for the tunnel to settle
    private static let earlyRetryWindow: Double = 10     // a first probe that fails within this gets one more try…
    private static let earlyRetry: Double = 1            // …a second later, nothing held against the line
    private static let stalePass: TimeInterval = 600     // the phone woke with a picture older than this: the quick pass again
    private static let phase1GraceMs = 2500              // phase two of a measurement starts this long after its start at the latest
    private static let watchedFor: Double = 15
    private static let rateWindow: Double = 5
    private static let rateMinBytes: Int64 = 256 * 1024
    private static let firstPassTimeoutSec = 3

    init(queue: DispatchQueue, store: SkyRayStore, log: RingLog, lines: [Line], policy: AutoPolicy, apiPort: Int, current: String,
         network: String, hint: Hint?, traffic: @escaping () -> (up: Int64, down: Int64), onSwitch: @escaping (Line, String) -> Void) {
        self.queue = queue; self.store = store; self.log = log; self.lines = lines; self.policy = policy; self.apiPort = apiPort
        self.current = current; self.traffic = traffic; self.onSwitch = onSwitch
        self.network = network; self.hint = hint
        self.health = store.lineHealth(on: network)
        self.lastTrafficAt = AutoEngine.mono()
        var map: [String: String] = [:]
        for l in lines where map[l.label] == nil { map[l.label] = l.id }
        self.idOf = map
    }

    static func mono() -> Double { ProcessInfo.processInfo.systemUptime }
    private static func wall() -> TimeInterval { Date().timeIntervalSince1970 }

    // MARK: the provider's calls

    func start() {
        let labels = lines.map { $0.label }
        // the start line: the best this network is known to have when the provider's choice is unknown here or held as
        // failed, else the hint's first, else the provider's choice
        let mine = label(current)
        if health.lastMs(mine) == nil || health.isDead(mine) {
            let known = health.bestKnown(labels)
            let best = known ?? hint?.arrange(labels).first { !health.isDead($0) && !(hint?.dead.contains($0) ?? false) }
            if let b = best, let id = idOf[b], id != current {
                switchTo(id: id, reason: known != nil ? "known best on \(network)" : "the box's advice")
            }
        }
        startedAt = AutoEngine.mono(); lastPassWall = Date()
        schedule.start(now: startedAt, order: order(), delay: AutoEngine.startDelay)   // the first probe two seconds on, when the tunnel has settled (2.1.1)
        log.info("auto: \(lines.count) lines behind the balancer, on \(name(current)); network \(network), \(health.entries.count) lines remembered\(hint.map { ", the box advises \($0.order.count) (\($0.dead.count) dead\($0.outage ? ", outage" : ""))" } ?? ""); a pass every \(policy.roundSec) s, the first at \(policy.firstPaceSec) s a step")
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + AutoEngine.tick, repeating: AutoEngine.tick, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in self?.tickNow() }
        t.resume()
        timer = t
    }

    func stop() {
        stopped = true
        if timerSuspended { timer?.resume(); timerSuspended = false }   // a suspended source must not be cancelled
        timer?.cancel(); timer = nil
        store.saveLineHealth(health, on: network)
    }

    /// The device sleeps: the clock stops with it (no 1 Hz wake-ups); traffic cannot flow meanwhile either.
    func pause() {
        paused = true
        if !timerSuspended, let t = timer { t.suspend(); timerSuspended = true }
    }

    func resume() {
        paused = false
        samples.removeAll(); rateSamples.removeAll()
        if timerSuspended, let t = timer { t.resume(); timerSuspended = false }
        // the phone woke (2.1.1): the line in use is probed now, and the whole picture again when it is old — nothing ran meanwhile
        guard schedule.nextProbeAt != nil else { return }
        let now = AutoEngine.mono()
        let age = Date().timeIntervalSince(lastPassWall)
        if !searching, age > AutoEngine.stalePass {
            schedule.freshen(now: now, order: order()); probesThisPass = 0
            log.info("auto: the phone woke with a picture \(Int(age / 60)) min old; the quick pass runs again")
        } else {
            schedule.wake(now: now)
        }
    }

    /// The app asked for the status: its chip is on screen, the line in use is kept fresh for it.
    func noteWatched() { watchedAt = AutoEngine.mono() }

    /// Wi-Fi ↔ mobile (or the path back after a gap): what was measured no longer holds. Another network's memory takes
    /// over intact — a line it holds as failed is left for its known-good one at once —; the same network coming back
    /// forgives every line. The first pass restarts in 15 s; a second event within a minute is the same.
    func onNetworkChanged(signature: String) {
        if signature != network {
            store.saveLineHealth(health, on: network)
            network = signature
            health = store.lineHealth(on: network)
            let labels = lines.map { $0.label }
            if health.isDead(label(current)), let best = health.bestKnown(labels), let id = idOf[best], id != current {
                switchTo(id: id, reason: "known good on \(network), \(name(current)) is not")
            }
        } else {
            health.forgive()
        }
        samples.removeAll(); rateSamples.removeAll()
        decision.firstSwitchDone = false
        let now = AutoEngine.mono()
        let before = schedule.lastNetworkAt
        schedule.networkChanged(now: now, settle: AutoEngine.networkSettle)
        if schedule.lastNetworkAt != before {
            schedule.order = order()
            probesThisPass = 0
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
        let timeout = policy.probeTimeoutSec * 1000
        let rest = lines.filter { $0.id != current }
        let first: [Line] = line(current).map { [$0] } ?? []
        // the line in use first, so the chip has its number within a second; then every other line at once — connected all
        // together, then read all together, so no line is read beside another's handshakes (2.1.1)
        measureSet(first, concurrency: 1, timeoutMs: timeout, whole: false) { [weak self] _ in
            guard let self = self else { completion("none"); return }
            self.measureSet(rest, concurrency: max(1, rest.count), timeoutMs: timeout, whole: true) { [weak self] _ in
            guard let self = self else { completion("none"); return }
            self.measuring = false
            let moved = self.decide(.manual, reason: "manual")
            self.report(trigger: "manual", switched: moved)
            self.updateSearching()
            if !self.searching { self.schedule.reseed(now: AutoEngine.mono(), order: self.order(), policy: self.policy, draw: Double.random(in: 0..<1)) }
            self.movedInPass = false
            self.probesThisPass = 0
            self.store.saveLineHealth(self.health, on: self.network)
            let answered = self.lines.contains { (self.results[$0.id] ?? 0) > 0 }
            completion(!answered ? "none" : (moved ? "switched" : "kept"))
            }
        }
    }

    // MARK: the loop

    private func tickNow() {
        guard !paused, !stopped else { return }
        let now = AutoEngine.mono()
        sample(now)
        guard !measuring else { return }
        if !searching, now >= stallQuietUntil, policy.stalled(samples, now: Date()) {
            stallQuietUntil = now + AutoEngine.stallProbeGap
            log.warn("auto: bytes out and none back for \(policy.stallSec) s on \(name(current))")
            failover(reason: "stall")
            return
        }
        let warm = now - lastTrafficAt < Double(policy.warmSec)
        let inUse = now - lastTrafficAt < Double(policy.idleSec)
        if inUse, !wasInUse { schedule.wake(now: now); log.info("auto: traffic is back after the idle gap; the line in use is probed") }
        wasInUse = inUse
        let watched = now - watchedAt < AutoEngine.watchedFor
        let wall = AutoEngine.wall()
        let due: (String) -> Bool = { id in self.health.due(self.label(id), now: wall) }
        let action = schedule.action(now: now, warm: warm, watched: watched, searching: searching, current: current, due: due)
        switch action {
        case .probe(let ids)?:
            searching ? searchStep(ids) : probeLines(ids)
        case .probeCurrent?:
            probeCurrentLine()
        case nil:
            // a step whose time has come with nothing left to probe before the rotation's end: the pass ends here
            if !searching, let n = schedule.nextProbeAt, now >= n, warm || watched || schedule.forced || schedule.phase == .first {
                let first = schedule.phase == .first
                if probesThisPass > 0 { passEnded(first: first) }
                schedule.nothingDue(now: now, policy: policy, draw: Double.random(in: 0..<1), active: activeCount(due))
            }
        }
    }

    /// How many lines the rotation can probe right now (the pace spreads the round over them).
    private func activeCount(_ due: (String) -> Bool) -> Int {
        lines.filter { due($0.id) && ($0.id != current || schedule.phase != .first) }.count
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
        return (good + (hint?.arrange(unseen) ?? unseen) + dead).compactMap { idOf[$0] }
    }

    private func label(_ id: String) -> String { lines.first { $0.id == id }?.label ?? id }
    private func name(_ id: String) -> String { lines.first { $0.id == id }?.remark ?? id }
    private func line(_ id: String) -> Line? { lines.first { $0.id == id } }
    private func resultOf(label: String) -> Int64 { idOf[label].flatMap { results[$0] } ?? 0 }

    /// One step of the trickle (one line; two in the first pass): measured, recorded; the first pass may correct the
    /// start once; a wrapped rotation is a pass — the steady decision and the report. The line in use failing its
    /// full-window probe here is a failover.
    private func probeLines(_ ids: [String]) {
        let which = ids.compactMap { line($0) }
        guard !which.isEmpty else { return }
        let first = schedule.phase == .first
        let scout = schedule.fallback && schedule.cursor == 0   // the first probe of a pass on the fallback tries the target
        let url = schedule.fallback && !scout ? Etha.probeFallbackURL : Etha.probeURL
        let timeout = (first ? min(policy.probeTimeoutSec, AutoEngine.firstPassTimeoutSec) : policy.probeTimeoutSec) * 1000
        measuring = true
        measureOnce(which, concurrency: which.count, url: url, timeoutMs: timeout) { [weak self] out in
            guard let self = self else { return }
            if scout {
                let back = out.values.contains { $0 > 0 }
                self.schedule.fallback = AutoSchedule.nextFallback(current: true, targetAnswered: back, fallbackAnswered: false)
                if back { self.log.info("auto: the probe target answers again; measuring against it") }
            }
            self.record(out, which: which)
            self.probesThisPass += which.count
            let now = AutoEngine.mono()
            let wall = AutoEngine.wall()
            let due: (String) -> Bool = { id in self.health.due(self.label(id), now: wall) }
            let passEnd = self.schedule.probed(now: now, ids: which.map { $0.id }, policy: self.policy, draw: Double.random(in: 0..<1), active: self.activeCount(due))
            self.measuring = false
            if first, self.decide(.first, reason: "first pass") { self.movedInPass = true }
            if passEnd { self.passEnded(first: first) }
            if which.contains(where: { $0.id == self.current }), (out[self.current] ?? -1) < 0 {
                self.log.warn("auto: \(self.name(self.current)) did not answer its probe")
                self.failover(reason: "probe")
                return
            }
            self.updateSearching()
        }
    }

    /// A pass is over, by its last probe or by a tail of lines waiting their retry: the steady decision, the report, the
    /// rate window, the memory saved.
    private func passEnded(first: Bool) {
        if !first, decide(.passEnd, reason: "pass end") { movedInPass = true }
        report(trigger: first ? "first" : "auto", switched: movedInPass)
        movedInPass = false
        passRateKbps = 0
        probesThisPass = 0
        lastPassWall = Date()
        store.saveLineHealth(health, on: network)
    }

    /// The line in use's own probe (every currentSec while the app is on screen, and once when traffic returns): its
    /// number to the chip; a full-window failure, the failover.
    private func probeCurrentLine() {
        guard let l = line(current) else { return }
        measuring = true
        measureOnce([l], concurrency: 1, url: schedule.fallback ? Etha.probeFallbackURL : Etha.probeURL, timeoutMs: policy.probeTimeoutSec * 1000) { [weak self] out in
            guard let self = self else { return }
            if (out[l.id] ?? -1) < 0, !self.firstReading, !self.earlyRetried, AutoEngine.mono() - self.startedAt < AutoEngine.earlyRetryWindow {
                // the first probe after Connect ran on a tunnel still settling: once more in a second, nothing held against the line (2.1.1)
                self.earlyRetried = true
                self.schedule.currentDueAt = AutoEngine.mono() + AutoEngine.earlyRetry
                self.measuring = false
                self.log.info("auto: \(l.remark) gave no answer right after Connect; once more in a second")
                return
            }
            self.record(out, which: [l])
            self.schedule.currentProbed(now: AutoEngine.mono(), policy: self.policy)
            self.measuring = false
            if (out[l.id] ?? -1) < 0 {
                self.log.warn("auto: \(l.remark) did not answer its probe")
                self.failover(reason: "probe")
            }
        }
    }

    /// Make-before-break: the line in use and the best alternative not yet tried probed together within failoverMs. The
    /// line in use answering: nothing moves, the alarm rests a minute. It failing and the alternative answering: new
    /// connections move at once, and only then is the old line held as failed. The alternative failing too: the next,
    /// once more; nothing answering: Searching. The short window itself condemns nobody — answers are kept, failures not.
    private func failover(reason: String, tried: Set<String> = [], attempt: Int = 1) {
        guard let cur = line(current), !measuring else { return }
        let labels = lines.map { $0.label }
        let mine = label(current)
        let excluded = tried.union([mine])
        let altLabel = health.bestKnown(labels, except: mine).flatMap { excluded.contains($0) ? nil : $0 }
            ?? (hint?.arrange(labels) ?? labels).first { !excluded.contains($0) && !health.isDead($0) && !(hint?.dead.contains($0) ?? false) }
            ?? (hint?.arrange(labels) ?? labels).first { !excluded.contains($0) }
        let alt = altLabel.flatMap { idOf[$0] }.flatMap { line($0) }
        var which = [cur]
        if let a = alt { which.append(a) }
        measuring = true
        measureOnce(which, concurrency: which.count, url: schedule.fallback ? Etha.probeFallbackURL : Etha.probeURL, timeoutMs: policy.failoverMs) { [weak self] out in
            guard let self = self else { return }
            self.record(out, which: which, condemn: false)      // a 1.5-s window: answers count, failures do not
            self.measuring = false
            if (out[cur.id] ?? -1) > 0 {
                self.stallQuietUntil = AutoEngine.mono() + AutoEngine.stallFalseAlarmRest
                self.log.info("auto: \(cur.remark) answers within \(self.policy.failoverMs) ms (\(reason)): staying")
                return
            }
            if let a = alt, (out[a.id] ?? -1) > 0 {
                self.condemn(cur.id)
                self.switchTo(id: a.id, reason: "failover after \(reason)")
                self.decision.moved(now: AutoEngine.mono())
                self.report(trigger: "failover", switched: true)
                self.store.updateTunnelState { $0.failoverAt = Date() }
                self.store.saveLineHealth(self.health, on: self.network)
                return
            }
            var next = tried
            if let a = alt { next.insert(a.label) }
            if attempt < 2, alt != nil {
                self.failover(reason: reason, tried: next, attempt: attempt + 1)
                return
            }
            // nothing answered the line in use nor two alternatives: the line in use is held as failed and Searching decides
            self.condemn(cur.id)
            self.updateSearching(force: true)
        }
    }

    /// The line failed for good within this session: its result and its memory say so (its retry backs off).
    private func condemn(_ id: String) {
        results[id] = -1
        health.failed(label(id), now: AutoEngine.wall(), policy: policy)
        probedSinceReport.insert(id)
        if id == current { tellLatency() }
    }

    /// Searching: a step over every line in turn (two lines). The first to answer takes new connections; leaving the
    /// state re-seeds the trickle and forgives every line. Every tenth step on the fallback scouts the box's target.
    private func searchStep(_ ids: [String]) {
        let which = ids.compactMap { line($0) }
        guard !which.isEmpty else { return }
        searchSteps += 1
        let scout = schedule.fallback && searchSteps % 10 == 0
        let url = schedule.fallback && !scout ? Etha.probeFallbackURL : Etha.probeURL
        measuring = true
        measureOnce(which, concurrency: which.count, url: url, timeoutMs: policy.probeTimeoutSec * 1000) { [weak self] out in
            guard let self = self else { return }
            if scout {
                let back = out.values.contains { $0 > 0 }
                self.schedule.fallback = AutoSchedule.nextFallback(current: true, targetAnswered: back, fallbackAnswered: false)
                if back { self.log.info("auto: the probe target answers again; measuring against it") }
            }
            self.record(out, which: which, condemn: false)      // while searching no failure is held against a line
            self.schedule.searchStep(now: AutoEngine.mono(), count: which.count, policy: self.policy, slow: self.hint?.outage ?? false)
            if self.searchSteps % 30 == 0 { self.refreshHint() }
            if let found = which.first(where: { (out[$0.id] ?? -1) > 0 }), found.id != self.current {
                self.switchTo(id: found.id, reason: "a line answers again")
                self.decision.moved(now: AutoEngine.mono())
                self.movedWhileSearching = true
            }
            self.measuring = false
            self.updateSearching()
        }
    }

    // MARK: measuring

    /// A set of lines at once (a manual test): the box's target; nothing from it on any line and something from the
    /// fallback moves the probes to the fallback until the target answers again.
    /// `whole`: the set stands for every line (the fallback question is asked only then).
    private func measureSet(_ which: [Line], concurrency: Int, timeoutMs: Int, whole: Bool? = nil, completion: @escaping ([String: Int64]) -> Void) {
        if which.isEmpty || stopped { completion([:]); return }
        let whole = whole ?? (which.count == lines.count)
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
            if whole, !first.isEmpty, first.values.allSatisfy({ $0 < 0 }) {
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

    /// Two phases (2.1.1), so that no line is read while another line's handshakes run beside it: every line opens its
    /// connection and sends its first request (the cold time), up to `concurrency` at once; once every open attempt has
    /// ended — or phase1Grace after the start, whichever comes first — each open connection gets its warm request, all
    /// together (one small packet each way). A warm read that fails is tried once more on a fresh connection. The connect
    /// times go to `colds` for the report; a line whose first request got nothing is -1.
    private func measureOnce(_ which: [Line], concurrency: Int, url: String, timeoutMs: Int, completion: @escaping ([String: Int64]) -> Void) {
        let slots = DispatchSemaphore(value: max(1, concurrency))
        let opened = DispatchGroup()          // phase one: every open attempt ended
        let done = DispatchGroup()            // the whole measurement
        let go = DispatchSemaphore(value: 0)  // phase two may start: one signal per line
        let lock = NSLock()
        var out: [String: Int64] = [:]
        var cold: [String: Int64] = [:]
        for line in which {
            opened.enter(); done.enter()
            measureQueue.async {
                slots.wait()
                let probe = Probe(port: line.probePort, timeoutMs: timeoutMs)
                let first = probe.open(url: url)
                slots.signal()
                opened.leave()
                var warm: Int64? = nil
                if first != nil {
                    go.wait()
                    warm = probe.warm()
                    if warm == nil, probe.open(url: url) != nil { warm = probe.warm() }   // once more on a fresh connection
                }
                probe.invalidate()
                lock.lock(); out[line.id] = warm ?? -1; if let c = first { cold[line.id] = c }; lock.unlock()
                done.leave()
            }
        }
        measureQueue.async {   // the barrier between the phases
            _ = opened.wait(timeout: .now() + .milliseconds(min(AutoEngine.phase1GraceMs, timeoutMs)))
            for _ in which { go.signal() }
        }
        done.notify(queue: queue) { [weak self] in
            self?.colds.merge(cold) { _, new in new }
            completion(out)
        }
    }

    /// Results into the engine, the memory of the network and the App Group; the line in use's number to the chip.
    /// `condemn`: whether a failure is held against the line (not from a short failover window, not while searching).
    private func record(_ out: [String: Int64], which: [Line], condemn: Bool = true) {
        let wall = AutoEngine.wall()
        for (id, ms) in out {
            if ms > 0 {
                results[id] = ms
                health.ok(label(id), ms: ms, now: wall)
                if id == current { firstReading = true }
            } else if condemn {
                results[id] = ms
                health.failed(label(id), now: wall, policy: policy)
            } else {
                continue
            }
            probedSinceReport.insert(id)
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
        if ms <= 0, !firstReading { return }   // before the first answer after Connect the chip stays "Connecting…", whatever a probe did (2.1.1)
        store.updateTunnelState { $0.latencyMs = ms; $0.latencyAt = Date() }
    }

    /// What was measured since the last report — the lines probed, not the ones waiting their retry with an old
    /// result — kept for the next fetch (the header X-Etha-Lines), with the pass's best download rate.
    private func report(trigger: String, switched: Bool) {
        let inUse = line(current)?.remark
        var coldByRemark: [String: Int64] = [:]
        for l in lines where probedSinceReport.contains(l.id) { if let c = colds[l.id], c > 0 { coldByRemark[l.remark] = c } }
        let header = LineReport.build(now: Date(), trigger: trigger, inUseRemark: inUse, switched: switched,
                                      results: lines.map { ($0.remark, probedSinceReport.contains($0.id) ? (results[$0.id] ?? 0) : 0) }, rateKbps: passRateKbps,
                                      colds: coldByRemark)
        if let h = header { store.updateTunnelState { $0.lineReport = h }; probedSinceReport.removeAll() }
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

    /// Searching = nothing answers: every line failed this session or waits its retry, the line in use among the failed
    /// (LineHealth.allOut) — or the failover exhausted its alternatives (`force`). Before entering it the line in use is
    /// probed against the fallback once: an answer there means the target is down, not the lines, and the probes move to
    /// the fallback. Entering turns the clock to the search pace; leaving re-seeds it, forgives every line and reports.
    private func updateSearching(force: Bool = false) {
        guard !measuring else { return }
        let labels = lines.map { $0.label }
        let dead = force || health.allOut(labels, current: label(current), result: { self.resultOf(label: $0) })
        if dead, !searching, !schedule.fallback, let cur = line(current) {
            measuring = true
            measureOnce([cur], concurrency: 1, url: Etha.probeFallbackURL, timeoutMs: policy.probeTimeoutSec * 1000) { [weak self] out in
                guard let self = self else { return }
                self.measuring = false
                if let ms = out[cur.id], ms > 0 {
                    self.schedule.fallback = true
                    self.results[cur.id] = ms
                    self.health.ok(self.label(cur.id), ms: ms, now: AutoEngine.wall())
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

    private func enterSearching(_ on: Bool) {
        searching = on
        let outage = on && (hint?.outage ?? false)
        log.info(on ? "auto: no line answers — searching\(outage ? " (the box says this network blocks every line right now)" : "")" : "auto: a line answers again")
        store.updateTunnelState { $0.searching = on; $0.outage = outage }
        let now = AutoEngine.mono()
        if on {
            searchSteps = 0
            movedWhileSearching = false
            schedule.searchingBegan(now: now)
            report(trigger: "search", switched: false)
        } else {
            health.forgive()                                   // what failed during the outage may well pass now
            schedule.reseed(now: now, order: order(), policy: policy, draw: Double.random(in: 0..<1))
            probesThisPass = 0
            report(trigger: "search", switched: movedWhileSearching)
            movedWhileSearching = false
        }
        store.saveLineHealth(health, on: network)
    }
}
