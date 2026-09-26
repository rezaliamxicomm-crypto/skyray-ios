import Foundation
import NetworkExtension
import Combine
import SkyRayCore

enum VPNError: Error { case noManager }

/// The system's VPN configuration for SkyRay and the tunnel session on it.
@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = managers.first ?? NETunnelProviderManager()
            manager = m
            observe(m)
            status = m.connection.status
        } catch {
            AppLog.error("vpn: load failed: \(error)")
        }
    }

    private func observe(_ m: NETunnelProviderManager) {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: m.connection, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.status = m.connection.status }
        }
        status = m.connection.status
    }

    private func configure(_ m: NETunnelProviderManager) {
        let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Etha.tunnelBundleID
        proto.serverAddress = "EthaVPN"
        proto.providerConfiguration = ["v": 1]
        m.protocolConfiguration = proto
        m.localizedDescription = "SkyRay"
        m.isEnabled = true
    }

    /// Saves the configuration (the system asks the customer once), then starts the tunnel on the line.
    func start(lineId: String) async throws {
        if manager == nil { await load() }
        guard let m = manager else { throw VPNError.noManager }
        configure(m)
        try await m.saveToPreferences()
        try await m.loadFromPreferences()
        observe(m)
        try m.connection.startVPNTunnel(options: ["lineId": lineId as NSString])
    }

    func stop() { manager?.connection.stopVPNTunnel() }

    func remove() async {
        if let m = manager { try? await m.removeFromPreferences() }
        manager = nil
        status = .invalid
    }

    var isActive: Bool { status == .connected || status == .connecting || status == .reasserting }

    /// A question to the running tunnel; nil when it is not running or does not answer.
    func send(_ request: TunnelRequest) async -> TunnelReply? {
        guard let session = manager?.connection as? NETunnelProviderSession, isActive,
              let data = try? JSONEncoder().encode(request) else { return nil }
        return await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(data) { reply in
                    let decoded = reply.flatMap { try? JSONDecoder().decode(TunnelReply.self, from: $0) }
                    continuation.resume(returning: decoded)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
