import Foundation

/// Auto's clock, pure so it is tested on its own — the same shape in both apps (the Android app's handler/AutoSchedule).
/// One rule for when the next round runs: an interval after the moment the last measurement ended, whatever it measured
/// and however long it took. Until 2.0.2 the round fired by one clock and each line was then measured only if its own
/// last probe was old enough by a second clock; a round could wake up a second too early for every line, measure
/// nothing and move the first clock on, so rounds came every six minutes instead of three.
///
///   - `nextRoundAt`: the next regular round (the Searching state: every searchSec); nil until the first race ended.
///   - `settleAt`: the one settling round, settleSec after a connect or network race (the race measures every line at
///     once on a core a second old and reads high).
///   - `retryAt`: a failed line is not measured again before its retry time (failedRetrySec after each failed probe).
///   - `fallback`: the next measurement goes to the fallback target. Never sticky: in that mode every round first
///     sends one probe to the box's target and comes back to it the moment it answers.
public struct AutoSchedule: Equatable {
    public enum Action: Equatable { case settle, round }

    public var nextRoundAt: Date?
    public var settleAt: Date?
    public var retryAt: [String: Date] = [:]
    public var fallback = false

    public init() {}

    /// A measurement ended now with these results (-1 failed): failed lines wait their retry, answered lines are free
    /// again, and the next round comes one interval after this moment.
    public mutating func roundDone(now: Date, results: [String: Int64], policy: AutoPolicy, draw: Double, searching: Bool) {
        for (id, ms) in results {
            if ms < 0 { retryAt[id] = now.addingTimeInterval(TimeInterval(policy.failedRetrySec)) } else { retryAt.removeValue(forKey: id) }
        }
        nextRoundAt = now.addingTimeInterval(searching ? TimeInterval(policy.searchSec) : policy.jitteredRound(using: draw))
    }

    /// A race ended now (connect, network: every line at once): as roundDone, plus the settling round settleSec later
    /// when `settle` is asked (not after a manual test — its numbers are warm).
    public mutating func raceDone(now: Date, results: [String: Int64], policy: AutoPolicy, draw: Double, searching: Bool, settle: Bool) {
        roundDone(now: now, results: results, policy: policy, draw: draw, searching: searching)
        settleAt = settle && policy.settleSec > 0 ? now.addingTimeInterval(TimeInterval(policy.settleSec)) : nil
    }

    /// What the tick should do now: the settling round when its time has come, else a round when the interval has
    /// passed and the tunnel is in use (or Searching), else nothing.
    public func action(now: Date, inUse: Bool, searching: Bool) -> Action? {
        if let s = settleAt, now >= s { return .settle }
        if let n = nextRoundAt, now >= n, inUse || searching { return .round }
        return nil
    }

    /// The settling round is taken: it runs once.
    public mutating func settleTaken() { settleAt = nil }

    /// The lines a round measures now: every line but a failed one still waiting its retry; Searching: every line.
    public func linesForRound(now: Date, lines: [String], searching: Bool) -> [String] {
        if searching { return lines }
        return lines.filter { id in retryAt[id].map { now >= $0 } ?? true }
    }

    /// The probe target after a measurement. On the target: a full set with no answer at all, and the fallback
    /// answering, moves the next measurement to the fallback. On the fallback: the one probe sent to the target at the
    /// start of a round brings the next measurement back to it as soon as it answers.
    public static func nextFallback(current: Bool, fullSet: Bool, targetAnswered: Bool, fallbackAnswered: Bool) -> Bool {
        if current { return !targetAnswered }
        return fullSet && !targetAnswered && fallbackAnswered
    }
}
