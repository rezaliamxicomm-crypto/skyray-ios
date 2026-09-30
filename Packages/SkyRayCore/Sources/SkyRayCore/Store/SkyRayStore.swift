import Foundation

/// Everything the app and the tunnel share, as JSON files in the App Group container (atomic writes).
/// Nothing else is stored anywhere: no analytics, no identifiers.
public final class SkyRayStore {
    public let root: URL
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; e.outputFormatting = [.sortedKeys]; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    /// The App Group container, or the caches directory when the group is missing (a misconfigured build).
    public static func appGroup() -> SkyRayStore {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Etha.appGroup)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return SkyRayStore(root: base.appendingPathComponent("skyray", isDirectory: true))
    }

    public var logsDir: URL { root.appendingPathComponent("logs", isDirectory: true) }
    public var appLogURL: URL { logsDir.appendingPathComponent("app.log") }
    public var tunnelLogURL: URL { logsDir.appendingPathComponent("tunnel.log") }
    public var xrayLogURL: URL { logsDir.appendingPathComponent("xray.log") }

    private func url(_ name: String) -> URL { root.appendingPathComponent(name) }
    private func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }
    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }
    private func remove(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }

    // MARK: the subscription
    public func loadSnapshot() -> SubscriptionSnapshot? { read("snapshot.json", as: SubscriptionSnapshot.self) }
    public func saveSnapshot(_ s: SubscriptionSnapshot) { write(s, "snapshot.json") }

    public var selection: Selection {
        get { read("selection.json", as: Selection.self) ?? Selection() }
        set { write(newValue, "selection.json") }
    }
    public func updateSelection(_ change: (inout Selection) -> Void) { var s = selection; change(&s); selection = s }

    public var tunnelState: TunnelState {
        get { read("tunnel-state.json", as: TunnelState.self) ?? TunnelState() }
        set { write(newValue, "tunnel-state.json") }
    }
    public func updateTunnelState(_ change: (inout TunnelState) -> Void) { var s = tunnelState; change(&s); tunnelState = s }

    // MARK: small flags
    private struct Flags: Codable { var deletedLink: String?; var declarationAccepted: Bool?; var lastRefreshAttempt: Date?; var oldAppImportTried: Bool? }
    private var flags: Flags { get { read("flags.json", as: Flags.self) ?? Flags() } set { write(newValue, "flags.json") } }
    public var deletedLink: String? { get { flags.deletedLink } set { var f = flags; f.deletedLink = newValue; flags = f } }
    public var declarationAccepted: Bool { get { flags.declarationAccepted ?? false } set { var f = flags; f.declarationAccepted = newValue; flags = f } }
    public var lastRefreshAttempt: Date? { get { flags.lastRefreshAttempt } set { var f = flags; f.lastRefreshAttempt = newValue; flags = f } }
    /// The previous SkyRay's files were looked at once for the customer's link (OldAppFiles).
    public var oldAppImportTried: Bool { get { flags.oldAppImportTried ?? false } set { var f = flags; f.oldAppImportTried = newValue; flags = f } }

    /// "Delete account": the subscription, the selection and the tunnel state go; the deleted link is
    /// remembered so the clipboard import never puts it straight back; the declaration stays accepted.
    public func wipe(rememberingDeletedLink link: String?) {
        remove("snapshot.json"); remove("selection.json"); remove("tunnel-state.json")
        for name in ["app.log", "tunnel.log", "xray.log"] { try? FileManager.default.removeItem(at: logsDir.appendingPathComponent(name)) }
        var f = flags; f.deletedLink = link; f.lastRefreshAttempt = nil; flags = f
    }
}
