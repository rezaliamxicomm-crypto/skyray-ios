import Foundation

/// Auto's clock, pure so it is tested on its own — the same shape in both apps (the Android app's handler/AutoSchedule).
/// Monotonic seconds: a phone that adjusts its time can neither fire nor delay anything.
///
/// The lines are measured as a trickle, never in bursts: one probe at a time (two during the first pass), every line —
/// the line in use among them — once per roundSec while the radio is warm or the app is on screen, the line in use also
/// every currentSec while watched. The first pass after Connect and
/// after a network change goes best-known-first at firstPaceSec per step, so the whole picture is in hand within seconds
/// and a pick made on cold numbers is corrected (AutoDecision) without a second burst. A pass ended is the moment of the
/// steady-state decision and of the report to the box. Searching (no line answers) is the fast trickle over every line,
/// retries ignored, until one answers.
///
///   - `order`, `cursor`: the rotation; a line waiting its retry (LineHealth) is skipped.
///   - `nextProbeAt`, `currentDueAt`: the next step, the line in use's probe (only while watched, or forced).
///   - `phase`: `.first` (quick, two at a time) or `.steady`.
///   - `fallback`: probes go to the fallback target; never sticky — the first probe of every pass is a scout to the box's
///     target and the pass comes back the moment it answers.
public struct AutoSchedule: Equatable {
    public enum Action: Equatable { case probe([String]), probeCurrent }
    public enum Phase: Equatable { case first, steady }

    public var order: [String] = []
    public var cursor = 0
    public var phase: Phase = .first
    public var passes = 0
    public var nextProbeAt: Double?
    public var currentDueAt: Double?
    public var forced = false
    public var lastNetworkAt: Double?
    public var fallback = false
    /// traffic returned after the idle gap: one probe of the line in use, watched or not, then the trickle under its gate
    public var wakeDue = false
    public var searchingSince: Double?
    /// Searching probes freely for this long; after it only while the radio is warm or the app on screen
    public static let searchGateAfter: Double = 600

    public init() {}

    /// Connect: the rotation in the order the health memory suggests, the line in use probed first, then the quick pass.
    public mutating func start(now: Double, order: [String]) {
        self.order = order
        cursor = 0; phase = .first; passes = 0; forced = true
        nextProbeAt = now
        currentDueAt = now
    }

    /// A manual test ended now (every line measured, warm): the rotation re-seeded best-first at the steady pace.
    public mutating func reseed(now: Double, order: [String], policy: AutoPolicy, draw: Double) {
        self.order = order
        cursor = 0; phase = .steady; forced = false
        nextProbeAt = now + pace(policy: policy, draw: draw)
        currentDueAt = now + Double(policy.currentSec)
    }

    /// What the tick should do now. `warm`: bytes moved within warmSec (the radio is up anyway: a probe costs no wake-up);
    /// `watched`: the app asked for the status in the last seconds (the chip is on screen); `due`: whether a line may be
    /// probed now (LineHealth). A steady step fires only warm or watched — otherwise the phone sleeps —; the first pass and
    /// a network change are forced; traffic returning after the idle gap gets one probe of the line in use. Searching:
    /// every line in turn, two at a time, at its own pace (searchStep), freely for searchGateAfter seconds and then only
    /// warm or watched. In the first pass the line in use is left out (it was probed first); in steady state it is in the
    /// rotation like any line, once per pass.
    public func action(now: Double, warm: Bool, watched: Bool, searching: Bool, current: String, due: (String) -> Bool) -> Action? {
        if searching {
            if let since = searchingSince, now - since > AutoSchedule.searchGateAfter, !(warm || watched) { return nil }
            guard let n = nextProbeAt, now >= n else { return nil }
            let ids = next(count: 2, current: nil, due: { _ in true })
            return ids.isEmpty ? nil : .probe(ids)
        }
        if wakeDue, let c = currentDueAt, now >= c { return .probeCurrent }
        guard warm || watched || forced || phase == .first else { return nil }
        if let c = currentDueAt, now >= c, watched || forced { return .probeCurrent }
        guard let n = nextProbeAt, now >= n else { return nil }
        let ids = next(count: phase == .first ? 2 : 1, current: phase == .first ? current : nil, due: due)
        return ids.isEmpty ? nil : .probe(ids)
    }

    /// The next lines of the rotation that may be probed: not the line in use, not one waiting its retry; from the
    /// cursor to the end of the rotation (a step never straddles a pass boundary), up to `count`. Empty when nothing
    /// before the end may be probed: the pass ends there (`nothingDue`).
    public func next(count: Int, current: String?, due: (String) -> Bool) -> [String] {
        var out: [String] = []
        var k = cursor
        while k < order.count, out.count < count {
            let id = order[k]
            k += 1
            if id == current || !due(id) { continue }
            out.append(id)
        }
        return out
    }

    /// `ids` (what `next` gave) were probed now: the cursor moves past them and past every line skipped on the way; a
    /// cursor at the end of the rotation is a pass. Returns true at a pass end. `active`: how many lines the rotation
    /// has to probe right now (the pace spreads roundSec over them, not over lines waiting their retry).
    public mutating func probed(now: Double, ids: [String], policy: AutoPolicy, draw: Double, active: Int? = nil) -> Bool {
        if let last = ids.last, let at = order[min(cursor, order.count)...].firstIndex(of: last) {
            cursor = at + 1
        } else {
            cursor += max(1, ids.count)
        }
        var passEnd = false
        if cursor >= order.count {
            cursor = 0; passes += 1; passEnd = true
            if phase == .first { phase = .steady }
            forced = false
        }
        nextProbeAt = now + (phase == .first ? Double(policy.firstPaceSec) : pace(policy: policy, draw: draw, active: active))
        return passEnd
    }

    /// Nothing before the end of the rotation may be probed (the line in use, lines waiting their retry): the pass ends
    /// here without a probe; the next step starts the rotation again after the pace.
    public mutating func nothingDue(now: Double, policy: AutoPolicy, draw: Double, active: Int? = nil) {
        cursor = 0; passes += 1
        if phase == .first { phase = .steady }
        forced = false
        nextProbeAt = now + pace(policy: policy, draw: draw, active: active)
    }

    /// The line in use was probed now.
    public mutating func currentProbed(now: Double, policy: AutoPolicy) {
        currentDueAt = now + Double(policy.currentSec)
        wakeDue = false
    }

    /// Searching begins: every line in turn, two at a time, the first step now; ends: `reseed`/`start` as the engine decides.
    public mutating func searchingBegan(now: Double) {
        cursor = 0; phase = .steady
        nextProbeAt = now
        currentDueAt = nil
        searchingSince = now
    }

    /// Searching: one step taken; the rotation wraps without end, each line once per searchSec (two lines a step), three
    /// times slower when the box says the network blocks every line (`slow`).
    public mutating func searchStep(now: Double, count: Int, policy: AutoPolicy, slow: Bool = false) {
        cursor = (cursor + max(1, count)) % max(1, order.count)
        let steps = max(1.0, (Double(order.count) / 2).rounded(.up))
        nextProbeAt = now + max(1.0, Double(policy.searchSec) / steps) * (slow ? 3 : 1)
    }

    /// Wi-Fi ↔ mobile (or the path back after a gap): the trickle restarts in `settle` seconds as a quick first pass,
    /// in use or not; a second event within `debounce` seconds is the same event.
    public mutating func networkChanged(now: Double, settle: Double = 15, debounce: Double = 60) {
        if let last = lastNetworkAt, now - last < debounce { return }
        lastNetworkAt = now
        cursor = 0; phase = .first; forced = true
        nextProbeAt = now + settle
        currentDueAt = now + settle
    }

    /// Traffic returned after the idle gap: one probe of the line in use now, watched or not; the trickle itself resumes
    /// under its gate (warm or watched), never a forced pass.
    public mutating func wake(now: Double) {
        guard nextProbeAt != nil else { return }
        wakeDue = true
        currentDueAt = now
    }

    /// The steady pace: roundSec spread over the lines the rotation has to probe (`active`, else every line), give or
    /// take jitterPct (`draw` in 0 ..< 1).
    public func pace(policy: AutoPolicy, draw: Double, active: Int? = nil) -> Double {
        let n = (active ?? 0) > 0 ? active! : order.count
        let base = Double(policy.roundSec) / Double(max(1, n))
        let share = Double(policy.jitterPct) / 100 * (2 * min(max(draw, 0), 1) - 1)
        return base * (1 + share)
    }

    /// The probe target after a measurement: on the target, nothing from it and something from the fallback moves the
    /// next probes to the fallback; on the fallback, the scout probe sent to the target decides.
    public static func nextFallback(current: Bool, targetAnswered: Bool, fallbackAnswered: Bool) -> Bool {
        if current { return !targetAnswered }
        return !targetAnswered && fallbackAnswered
    }
}
