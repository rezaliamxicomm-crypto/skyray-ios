import Foundation

/// When the app asks for an App Store rating by itself (Settings always has "Rate SkyRay") — the Android
/// app's handler/RatePrompt, number for number. Counted in connections that worked (the customer tapped
/// Connect and the probe came back with a time): a rating is asked for when the service has just done its job.
///
/// The first ask comes with the 5th such connection, three days or more after the first one; the next ten
/// connections and two weeks later; three asks at most, and none once the customer went to the store from
/// Settings. iOS draws the card itself and tells the app nothing about it, so every request counts as an ask.
public struct RatePrompt: Codable, Equatable {
    public static let firstConnects = 5
    public static let firstDays = 3
    public static let againConnects = 10
    public static let againDays = 14
    public static let maxAsks = 3
    private static let day: TimeInterval = 86_400

    public var connects: Int
    public var firstAt: Date?
    public var asks: Int
    public var lastAskAt: Date?
    public var lastAskConnects: Int
    public var done: Bool

    public init(connects: Int = 0, firstAt: Date? = nil, asks: Int = 0, lastAskAt: Date? = nil, lastAskConnects: Int = 0, done: Bool = false) {
        self.connects = connects; self.firstAt = firstAt; self.asks = asks
        self.lastAskAt = lastAskAt; self.lastAskConnects = lastAskConnects; self.done = done
    }

    /// Whether to ask now (a clock set back just waits).
    public func due(now: Date = Date()) -> Bool {
        guard !done, asks < Self.maxAsks, let first = firstAt else { return false }
        if asks == 0 {
            return connects >= Self.firstConnects && now.timeIntervalSince(first) >= Double(Self.firstDays) * Self.day
        }
        guard let last = lastAskAt else { return false }
        return connects - lastAskConnects >= Self.againConnects && now.timeIntervalSince(last) >= Double(Self.againDays) * Self.day
    }

    /// One more connection that worked. True when this is the moment to ask.
    public mutating func connected(now: Date = Date()) -> Bool {
        if done || asks >= Self.maxAsks { return false }   // nothing left to count for
        connects += 1
        if firstAt == nil { firstAt = now }
        return due(now: now)
    }

    /// The app asked: the next ask is counted from here.
    public mutating func asked(now: Date = Date()) {
        asks += 1
        lastAskAt = now
        lastAskConnects = connects
    }
}
