import Foundation

/// Auto's clock, pure so it is tested on its own — the same shape in both apps (the Android app's handler/AutoSchedule).
/// Monotonic seconds: a phone that adjusts its time can neither fire nor delay anything.
///
/// The lines are measured as a trickle, never in bursts: one probe at a time (two during the first pass), every line
/// once per roundSec while the radio is warm or the app is on screen, the line in use every currentSec while watched. The first pass after Connect and
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
    /// probed now (LineHealth). A steady step fires only warm or watched — otherwise the phone sleeps —; the first pass,
    /// a network change and a wake are forced. Searching: every line, two at a time, a step a second, nothing else.
    public func action(now: Double, warm: Bool, watched: Bool, searching: Bool, current: String, due: (String) -> Bool) -> Action? {
        if searching {
            guard let n = nextProbeAt, now >= n else { return nil }
            let ids = next(count: 2, current: nil, due: { _ in true })
            return ids.isEmpty ? nil : .probe(ids)
        }
        guard warm || watched || forced || phase == .first else { return nil }
        if let c = currentDueAt, now >= c, watched || forced { return .probeCurrent }
        guard let n = nextProbeAt, now >= n else { return nil }
        let ids = next(count: phase == .first ? 2 : 1, current: current, due: due)
        return ids.isEmpty ? nil : .probe(ids)
    }

    /// The next lines of the rotation that may be probed: not the line in use, not one waiting its retry; from the
    /// cursor on, wrapping, up to `count`.
    public func next(count: Int, current: String?, due: (String) -> Bool) -> [String] {
        guard !order.isEmpty else { return [] }
        var out: [String] = []
        for k in 0..<order.count where out.count < count {
            let id = order[(cursor + k) % order.count]
            if id == current || !due(id) { continue }
            out.append(id)
        }
        return out
    }

    /// `n` lines were probed now: the cursor moves past them; a wrapped rotation is a pass. Returns true at a pass end.
    public mutating func probed(now: Double, count: Int, policy: AutoPolicy, draw: Double) -> Bool {
        let before = cursor
        cursor += max(1, count)
        var passEnd = false
        if cursor >= order.count || before >= order.count {
            cursor = 0; passes += 1; passEnd = true
            if phase == .first { phase = .steady }
            forced = false
        }
        nextProbeAt = now + (phase == .first ? Double(policy.firstPaceSec) : pace(policy: policy, draw: draw))
        return passEnd
    }

    /// Nothing could be probed at this step (every other line waits its retry): the step is spent.
    public mutating func nothingDue(now: Double, policy: AutoPolicy, draw: Double) {
        nextProbeAt = now + (phase == .first ? Double(policy.firstPaceSec) : pace(policy: policy, draw: draw))
        if phase == .first { phase = .steady; forced = false }
    }

    /// The line in use was probed now.
    public mutating func currentProbed(now: Double, policy: AutoPolicy) {
        currentDueAt = now + Double(policy.currentSec)
    }

    /// Searching begins: the fast trickle over every line, a step a second; ends: `reseed`/`start` as the engine decides.
    public mutating func searchingBegan(now: Double) {
        cursor = 0; phase = .steady
        nextProbeAt = now
        currentDueAt = nil
    }

    /// Searching: one step taken.
    public mutating func searchStep(now: Double, count: Int) {
        cursor = (cursor + max(1, count)) % max(1, order.count)
        nextProbeAt = now + 1
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

    /// Traffic returned after the idle gap: the line in use is probed now and the trickle resumes at once.
    public mutating func wake(now: Double) {
        guard nextProbeAt != nil else { return }
        forced = true
        nextProbeAt = now
        currentDueAt = now
    }

    /// The steady pace: roundSec spread over the lines of the rotation, give or take jitterPct (`draw` in 0 ..< 1).
    public func pace(policy: AutoPolicy, draw: Double) -> Double {
        let base = Double(policy.roundSec) / Double(max(1, order.count))
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
