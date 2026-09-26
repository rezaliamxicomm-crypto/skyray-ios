import Foundation

/// What the subscription headers say. -1 = the header was never seen; total 0 = unlimited; expire 0 = never.
public struct SubscriptionInfo: Codable, Equatable {
    public var upload: Int64 = -1
    public var download: Int64 = -1
    public var total: Int64 = -1
    public var expire: Int64 = -1
    public var profileTitle: String?
    public var announce: String?
    public var supportURL: String?
    public var webPageURL: String?
    public var updateIntervalMinutes: Int64?
    public var infoUpdated: Date?
    public init() {}
}

/// One server line of the subscription with its Xray outbound (built once, in the app process).
public struct Line: Codable, Identifiable, Equatable {
    public let id: String
    public let link: String
    public let remark: String
    public let transport: String?
    public let endpointLabel: String?
    public let port: Int?
    public let order: Int
    public let outboundJSON: String
    public init(id: String, link: String, remark: String, transport: String?, endpointLabel: String?, port: Int?, order: Int, outboundJSON: String) {
        self.id = id; self.link = link; self.remark = remark; self.transport = transport
        self.endpointLabel = endpointLabel; self.port = port; self.order = order; self.outboundJSON = outboundJSON
    }
    public var displayName: String { LineName.display(remark) }
}

public struct SubscriptionSnapshot: Codable, Equatable {
    public var url: String
    public var name: String
    public var fetchedAt: Date
    public var info: SubscriptionInfo
    public var lines: [Line]
    public init(url: String, name: String, fetchedAt: Date, info: SubscriptionInfo, lines: [Line]) {
        self.url = url; self.name = name; self.fetchedAt = fetchedAt; self.info = info; self.lines = lines
    }
}

/// The customer's choice and the last measurements. results: line id → ms (> 0), -1 failed, absent = untested.
public struct Selection: Codable, Equatable {
    public var selectedLineId: String?
    public var pinned: Bool = false
    public var lastTestAt: Date?
    public var results: [String: Int64] = [:]
    public init() {}

    public func delay(of id: String) -> Int64 { results[id] ?? 0 }
    public func candidates(_ lines: [Line]) -> [AutoSelect.Candidate] {
        lines.map { AutoSelect.Candidate(id: $0.id, delayMs: delay(of: $0.id), order: $0.order) }
    }
}

/// What the tunnel extension last reported, mirrored into the App Group for the app.
public struct TunnelState: Codable, Equatable {
    public var activeLineId: String?
    public var lastProbeMs: Int64?
    public var lastProbeAt: Date?
    public var switchedTo: String?
    public var switchedAt: Date?
    public var footprintMB: Double?
    public var xrayVersion: String?
    public var startedAt: Date?
    public init() {}
}
