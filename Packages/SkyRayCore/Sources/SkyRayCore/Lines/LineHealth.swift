import Foundation

/// What is known of each line on this network: how often it failed in a row, when it may be tried again (the retry
/// doubles from failedRetrySec at each failure up to retryCapSec), its last good time. Keyed by the line's label, which
/// is the same across fetches and across both apps; kept per network across sessions (the store), so an MCI phone that
/// learnt last night that no Cloudflare line passes does not spend its first minute today finding out again, and dead
/// lines fade from the schedule instead of being tried every quarter hour forever. Wall-clock seconds, coarse on purpose.
public struct LineHealth: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public var fails = 0
        public var retryAt: TimeInterval?
        public var lastMs: Int64?
        public var okAt: TimeInterval?
        public init() {}
    }
    public var entries: [String: Entry] = [:]

    public init() {}

    public mutating func ok(_ id: String, ms: Int64, now: TimeInterval) {
        var e = entries[id] ?? Entry()
        e.fails = 0; e.retryAt = nil; e.lastMs = ms; e.okAt = now
        entries[id] = e
    }

    public mutating func failed(_ id: String, now: TimeInterval, policy: AutoPolicy) {
        var e = entries[id] ?? Entry()
        e.fails += 1
        let wait = min(TimeInterval(policy.failedRetrySec) * pow(2, Double(e.fails - 1)), TimeInterval(policy.retryCapSec))
        e.retryAt = now + wait
        entries[id] = e
    }

    /// May the line be probed now? A line never seen, or whose retry time has come.
    public func due(_ id: String, now: TimeInterval) -> Bool {
        guard let r = entries[id]?.retryAt else { return true }
        return now >= r
    }

    public func isDead(_ id: String) -> Bool { (entries[id]?.fails ?? 0) > 0 }
    public func lastMs(_ id: String) -> Int64? { entries[id]?.lastMs }

    /// Every line forgiven: tried again at the next pass (a network change: what failed may pass now).
    public mutating func forgive() {
        for k in entries.keys { entries[k]?.retryAt = nil; entries[k]?.fails = 0 }
    }

    /// The lines in the order the trickle should take them: known good by their last time, then never seen, then the
    /// failed — the subscription's order among equals.
    public func bestFirst(_ lines: [String]) -> [String] {
        let indexed = lines.enumerated().map { ($0.offset, $0.element) }
        let good = indexed.filter { !isDead($0.1) && lastMs($0.1) != nil }.sorted { (lastMs($0.1)!, $0.0) < (lastMs($1.1)!, $1.0) }
        let unseen = indexed.filter { !isDead($0.1) && lastMs($0.1) == nil }
        let dead = indexed.filter { isDead($0.1) }
        return (good + unseen + dead).map { $0.1 }
    }

    /// Nothing answers: every line is either held as failed here or failed its last probe this session (`result` -1), and
    /// the line in use is among the failed. The moment Searching begins — a line waiting its retry counts as out, so backoff
    /// can never hide a dead network behind "not probed yet".
    public func allOut(_ labels: [String], current: String, result: (String) -> Int64) -> Bool {
        guard !labels.isEmpty, result(current) < 0 else { return false }
        return labels.allSatisfy { result($0) < 0 || isDead($0) }
    }

    /// The best line known good right now, other than `except`; nil when none is known good.
    public func bestKnown(_ lines: [String], except: String? = nil) -> String? {
        bestFirst(lines).first { $0 != except && !isDead($0) && lastMs($0) != nil }
    }
}
