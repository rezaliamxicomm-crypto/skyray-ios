import Foundation

/// The watchdog's next line after the current one failed: the best of the untried ones by the stored
/// measurements, else the first untried in body order; nil when every line has been tried (start over).
public enum LineRotation {
    public static func next(current: String, tried: Set<String>, lines: [Line], results: [String: Int64]) -> (id: String, tried: Set<String>)? {
        var t = tried; t.insert(current)
        let others = lines.filter { !t.contains($0.id) }
        if others.isEmpty { return nil }
        let candidates = others.map { AutoSelect.Candidate(id: $0.id, delayMs: results[$0.id] ?? 0, order: $0.order) }
        let pick = AutoSelect.best(candidates) ?? others.min { $0.order < $1.order }!.id
        return (pick, t)
    }

    /// 180 s between probes; 20 s while a failure is being confirmed.
    public static func nextProbeDelay(failures: Int) -> TimeInterval {
        failures > 0 ? Etha.watchdogRetry : Etha.watchdogInterval
    }
}
