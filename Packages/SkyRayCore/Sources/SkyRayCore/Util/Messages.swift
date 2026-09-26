import Foundation

/// App → tunnel requests (sendProviderMessage) and the tunnel's replies, as JSON.
public struct TunnelRequest: Codable, Equatable {
    public var cmd: String            // status | probe | switch | logTail
    public var lineId: String?
    public var lines: Int?
    public init(cmd: String, lineId: String? = nil, lines: Int? = nil) { self.cmd = cmd; self.lineId = lineId; self.lines = lines }
    public static let status = TunnelRequest(cmd: "status")
    public static let probe = TunnelRequest(cmd: "probe")
    public static func switchTo(_ id: String) -> TunnelRequest { TunnelRequest(cmd: "switch", lineId: id) }
    public static func logTail(_ n: Int) -> TunnelRequest { TunnelRequest(cmd: "logTail", lines: n) }
}

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
    public init() {}
}
