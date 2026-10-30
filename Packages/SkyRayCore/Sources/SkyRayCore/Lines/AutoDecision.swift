import Foundation

/// When new connections move to another line — pure, the same in both apps. Three cases, each with its own rule:
///
///   - the line in use failed (its probe, or the stall detector's probe): failover at once to the best line known
///     good, no dwell (the engine verifies it with one probe before the move);
///   - the first pass after Connect or a network change: at most one move, for a line clearly better — twice the margin
///     — than the line in use's fresh number; that is the correction of a pick made on cold numbers;
///   - steady state, at the end of a pass: a latency-only move needs the best line ahead by the margin at
///     `persistPasses` consecutive pass ends, or ahead by twice the margin at one, and never within `dwellSec` of the
///     last move. A line 20 ms faster this minute and slower the next never moves anyone.
///   - a manual test (the customer asked): the margin alone decides, no dwell.
public struct AutoDecision: Equatable {
    public enum Phase: Equatable { case first, passEnd, manual, failover }
    public struct Candidate: Equatable {
        public let id: String
        public let ms: Int64      // -1 failed, 0 not measured
        public let order: Int
        public init(id: String, ms: Int64, order: Int) { self.id = id; self.ms = ms; self.order = order }
    }

    public var lastSwitchAt: Double?           // monotonic seconds
    public var leading: [String: Int] = [:]    // candidate → consecutive pass ends ahead by the margin
    public var firstSwitchDone = false

    public init() {}

    /// The best measured line: the lowest time, the subscription's order among equals.
    public static func best(_ candidates: [Candidate]) -> Candidate? {
        candidates.filter { $0.ms > 0 }.min { ($0.ms, $0.order) < ($1.ms, $1.order) }
    }

    /// The line new connections should take now, or nil to stay. `current` is the line in use with its fresh time.
    public mutating func target(now: Double, phase: Phase, current: Candidate, candidates: [Candidate], policy: AutoPolicy) -> String? {
        let others = candidates.filter { $0.id != current.id }
        guard let best = AutoDecision.best(others) else { return nil }
        if current.ms < 0 || phase == .failover {           // the line in use failed: the best known takes over
            return commit(best.id, now: now)
        }
        switch phase {
        case .manual:
            return policy.shouldSwitch(currentMs: current.ms, bestMs: best.ms) ? commit(best.id, now: now) : nil
        case .first:
            if firstSwitchDone { return nil }
            guard policy.shouldSwitch(currentMs: current.ms, bestMs: best.ms, factor: 2) else { return nil }
            firstSwitchDone = true
            return commit(best.id, now: now)
        case .passEnd:
            let ahead = policy.shouldSwitch(currentMs: current.ms, bestMs: best.ms)
            let clearly = policy.shouldSwitch(currentMs: current.ms, bestMs: best.ms, factor: 2)
            leading = ahead ? [best.id: (leading[best.id] ?? 0) + 1] : [:]
            let persistent = clearly || (leading[best.id] ?? 0) >= policy.persistPasses
            guard persistent else { return nil }
            if let last = lastSwitchAt, now - last < Double(policy.dwellSec) { return nil }   // the counter keeps; the dwell decides later
            return commit(best.id, now: now)
        case .failover:
            return commit(best.id, now: now)
        }
    }

    /// A move was made by the engine for its own reasons (a failover it verified): the clocks follow.
    public mutating func moved(now: Double) { _ = commit("", now: now) }

    private mutating func commit(_ id: String, now: Double) -> String {
        lastSwitchAt = now
        leading = [:]
        return id
    }
}
