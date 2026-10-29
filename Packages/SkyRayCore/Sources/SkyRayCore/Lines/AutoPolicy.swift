import Foundation

/// The rules of Auto — the same in both apps (the Android app's handler/AutoPolicy). The tunnel's Xray holds every
/// line of the subscription behind one balancer; the extension measures the lines through that core (AutoEngine) and
/// holds the balancer to the best, so a change of line moves new connections only and cuts nothing that is open. The
/// numbers here are the policy's defaults; the service's header X-Etha-Auto ("round=180,failed=900,idle=600,
/// margin=15,floor=25,stall=8,timeout=5,conc=8,fresh=600") replaces any of them on the next fetch, so they change
/// without a release.
public struct AutoPolicy: Equatable, Codable {
    /// every line measured again this often, while the tunnel is in use
    public var roundSec: Int = 180
    /// a line that failed its last probe is tried again this often instead
    public var failedRetrySec: Int = 900
    /// no traffic for this long: no rounds until traffic returns
    public var idleSec: Int = 600
    /// another line must beat the line in use by this share of its time…
    public var marginPct: Int = 15
    /// …and by at least this many ms, to take over
    public var floorMs: Int = 25
    /// bytes going out and none coming back for this long: the line in use is probed at once
    public var stallSec: Int = 8
    /// one probe request's window; a line that does not answer within it counts as failed
    public var probeTimeoutSec: Int = 5
    /// lines probed at once in a round (the first race and a "Ping all" measure every line at once)
    public var concurrency: Int = 8
    /// results younger than this are trusted at Connect
    public var freshSec: Int = 600

    public init() {}
    public init(roundSec: Int, failedRetrySec: Int, idleSec: Int, marginPct: Int, floorMs: Int, stallSec: Int,
                probeTimeoutSec: Int, concurrency: Int, freshSec: Int) {
        self.roundSec = roundSec; self.failedRetrySec = failedRetrySec; self.idleSec = idleSec; self.marginPct = marginPct
        self.floorMs = floorMs; self.stallSec = stallSec; self.probeTimeoutSec = probeTimeoutSec; self.concurrency = concurrency
        self.freshSec = freshSec
    }

    public static let `default` = AutoPolicy()
    public static let stallMinUpBytes: Int64 = 2048

    /// A traffic sample: the inbound's bytes up and down at a moment.
    public struct Sample: Equatable {
        public let at: Date
        public let up: Int64
        public let down: Int64
        public init(at: Date, up: Int64, down: Int64) { self.at = at; self.up = up; self.down = down }
    }

    /// Should new connections move from the line in use (its last time, -1 failed, 0 not measured) to the best line
    /// (bestMs > 0)? Yes when the line in use failed, or when the best is better by the margin — at least floorMs and
    /// at least marginPct of the line in use. A line not measured yet keeps its connections until its own result is in.
    public func shouldSwitch(currentMs: Int64, bestMs: Int64) -> Bool {
        if bestMs <= 0 { return false }
        if currentMs < 0 { return true }
        if currentMs == 0 { return false }
        let margin = max(Int64(floorMs), currentMs * Int64(marginPct) / 100)
        return bestMs < currentMs - margin
    }

    /// The line new connections should take, or nil to stay: the lowest measured time (AutoSelect.best: an exact tie
    /// goes to the earlier line) when the line in use failed or is beaten by the margin; never while pinned, never
    /// without a measured line, and a line in use that is not among the candidates counts as failed.
    public func target(current: String?, candidates: [AutoSelect.Candidate], pinned: Bool) -> String? {
        if pinned { return nil }
        guard let best = AutoSelect.best(candidates) else { return nil }
        if best == current { return nil }
        guard let current = current else { return best }
        let currentMs = candidates.first { $0.id == current }?.delayMs ?? -1
        let bestMs = candidates.first { $0.id == best }!.delayMs
        return shouldSwitch(currentMs: currentMs, bestMs: bestMs) ? best : nil
    }

    /// A stall: among the samples (oldest first), between the newest and the newest one at least stallSec older, at
    /// least stallMinUpBytes went out and nothing came back.
    public func stalled(_ samples: [Sample], now: Date) -> Bool {
        guard samples.count >= 2, let newest = samples.last else { return false }
        let since = now.addingTimeInterval(-TimeInterval(stallSec))
        guard let base = samples.last(where: { $0.at <= since }), base != newest else { return false }
        return newest.up - base.up >= AutoPolicy.stallMinUpBytes && newest.down - base.down <= 0
    }

    /// Is a line due for a probe in this round? Failed lines wait failedRetrySec, the rest roundSec.
    public func due(now: Date, probedAt: Date?, failed: Bool) -> Bool {
        guard let at = probedAt else { return true }
        return now.timeIntervalSince(at) >= TimeInterval(failed ? failedRetrySec : roundSec)
    }

    /// The header's "key=value" list over base: unknown keys ignored, each value clamped to its range, a value that is
    /// no number ignored; nil or blank leaves base as it is.
    public static func parse(_ header: String?, base: AutoPolicy = .default) -> AutoPolicy {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return base }
        var p = base
        for part in header.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2, let v = Int(kv[1].trimmingCharacters(in: .whitespaces)) else { continue }
            switch kv[0].trimmingCharacters(in: .whitespaces).lowercased() {
            case "round": p.roundSec = min(max(v, 30), 3600)
            case "failed": p.failedRetrySec = min(max(v, 30), 7200)
            case "idle": p.idleSec = min(max(v, 60), 7200)
            case "margin": p.marginPct = min(max(v, 0), 90)
            case "floor": p.floorMs = min(max(v, 0), 2000)
            case "stall": p.stallSec = min(max(v, 3), 60)
            case "timeout": p.probeTimeoutSec = min(max(v, 2), 30)
            case "conc": p.concurrency = min(max(v, 1), 64)
            case "fresh": p.freshSec = min(max(v, 0), 86400)
            default: break
            }
        }
        return p
    }
}
