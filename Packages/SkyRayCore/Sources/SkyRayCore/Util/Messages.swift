import Foundation

/// App → tunnel requests (sendProviderMessage) and the tunnel's replies, as JSON.
public struct TunnelRequest: Codable, Equatable {
    public var cmd: String            // status | probe | ping | reload | logTail (switch: an older app's pick, ignored since 2.0.0)
    public var lineId: String?
    public var lines: Int?
    public init(cmd: String, lineId: String? = nil, lines: Int? = nil) { self.cmd = cmd; self.lineId = lineId; self.lines = lines }
    public static let status = TunnelRequest(cmd: "status")
    public static let probe = TunnelRequest(cmd: "probe")   // the same as ping since 2.0.0 (the extension measures every line, never one)
    public static func switchTo(_ id: String) -> TunnelRequest { TunnelRequest(cmd: "switch", lineId: id) }
    /// Every line measured through the running core now, and the best taken by Auto's rules (AutoEngine).
    public static let ping = TunnelRequest(cmd: "ping")
    public static func logTail(_ n: Int) -> TunnelRequest { TunnelRequest(cmd: "logTail", lines: n) }
    /// The subscription on disk changed (a fetch brought other lines): Xray restarts on them, the engine with it.
    public static let reload = TunnelRequest(cmd: "reload")
}

/// Every field optional on the wire: an older or newer tunnel's reply still decodes, and `{}` means "ok".
public struct TunnelReply: Codable, Equatable {
    public var ok: Bool = true
    public var state: String?
    public var lineId: String?
    public var lineName: String?
    public var lastProbeMs: Int64?
    public var lastProbeAt: Date?
    public var footprintMB: Double?
    public var switchedTo: String?
    public var switchedAt: Date?
    public var xrayVersion: String?
    public var log: String?
    public var error: String?
    public var searching: Bool?           // no line answers; Auto keeps measuring (2.0.0)
    public var outage: Bool?              // the box says this network blocks every line right now (2.1): the text under Searching
    public var failoverAt: Date?          // Auto last left a dead line then (2.1): the app fetches once, quietly
    public var latencyMs: Int64?          // the line in use's last time, -1 failed
    public var latencyAt: Date?
    public var outcome: String?           // of a "ping": switched | kept | none
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case ok, state, lineId, lineName, lastProbeMs, lastProbeAt, footprintMB, switchedTo, switchedAt, xrayVersion, log, error, searching, latencyMs, latencyAt, outcome
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        state = try c.decodeIfPresent(String.self, forKey: .state)
        lineId = try c.decodeIfPresent(String.self, forKey: .lineId)
        lineName = try c.decodeIfPresent(String.self, forKey: .lineName)
        lastProbeMs = try c.decodeIfPresent(Int64.self, forKey: .lastProbeMs)
        lastProbeAt = try c.decodeIfPresent(Date.self, forKey: .lastProbeAt)
        footprintMB = try c.decodeIfPresent(Double.self, forKey: .footprintMB)
        switchedTo = try c.decodeIfPresent(String.self, forKey: .switchedTo)
        switchedAt = try c.decodeIfPresent(Date.self, forKey: .switchedAt)
        xrayVersion = try c.decodeIfPresent(String.self, forKey: .xrayVersion)
        log = try c.decodeIfPresent(String.self, forKey: .log)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        searching = try c.decodeIfPresent(Bool.self, forKey: .searching)
        latencyMs = try c.decodeIfPresent(Int64.self, forKey: .latencyMs)
        latencyAt = try c.decodeIfPresent(Date.self, forKey: .latencyAt)
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
    }
}
