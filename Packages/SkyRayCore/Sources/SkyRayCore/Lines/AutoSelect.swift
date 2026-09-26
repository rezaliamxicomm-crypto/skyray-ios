import Foundation

/// The lowest measured delay wins outright; only an exact tie falls back to body order. Untested (0) and
/// failed (-1) lines are never chosen. Same rules as the Android app's AutoSelect.
public enum AutoSelect {
    public struct Candidate: Equatable {
        public let id: String
        public let delayMs: Int64
        public let order: Int
        public init(id: String, delayMs: Int64, order: Int) { self.id = id; self.delayMs = delayMs; self.order = order }
    }

    public static func best(_ candidates: [Candidate], exclude: Set<String> = []) -> String? {
        let ok = candidates.filter { $0.delayMs > 0 && !exclude.contains($0.id) }
        guard let min = ok.map({ $0.delayMs }).min() else { return nil }
        return ok.filter { $0.delayMs == min }.min { $0.order < $1.order }?.id
    }

    public static func resultsFresh(lastTestAt: Date?, now: Date = Date(), maxAge: TimeInterval = Etha.delayFresh) -> Bool {
        guard let t = lastTestAt else { return false }
        return now.timeIntervalSince(t) < maxAge
    }
}
