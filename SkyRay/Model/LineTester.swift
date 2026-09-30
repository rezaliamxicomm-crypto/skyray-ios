import Foundation
import SkyRayCore
import SkyRayXray

/// Measures every line the way the Android app's library does: a temporary Xray in this process with one loopback
/// inbound per line, then two HEAD requests per line down a kept-alive connection, the smaller time kept — the warm
/// round trip, not the handshakes. All lines are measured at once; libXray's managed instance is stopped after.
enum LineTester {
    static let attempts = 2

    static func testAll(_ lines: [Line], bindInterface: String?) async -> [String: Int64] {
        guard !lines.isEmpty else { return [:] }
        var results: [String: Int64] = [:]
        for line in lines { results[line.id] = -1 }
        let ports = (try? LibXrayBridge.getFreePorts(lines.count)) ?? (0..<lines.count).map { 43_000 + $0 }
        let entries = zip(lines, ports).map { (id: $0.id, outboundJSON: $0.outboundJSON, port: $1) }
        guard let config = try? XrayConfigBuilder.testConfig(lines: entries, bindInterface: bindInterface) else { return results }
        let started = await start(config)
        guard started else { AppLog.warn("test: the test instance did not start"); return results }
        defer { Task.detached(priority: .utility) { try? LibXrayBridge.stopXray() } }
        await withTaskGroup(of: (String, Int64).self) { group in
            for (line, port) in zip(lines, ports) {
                group.addTask { (line.id, await measure(port: port)) }
            }
            for await (id, ms) in group { results[id] = ms }
        }
        return results
    }

    private static func start(_ config: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                try? LibXrayBridge.stopXray()
                do { try LibXrayBridge.runXray(configJSON: config); continuation.resume(returning: true) }
                catch { AppLog.warn("test instance: \(error)"); continuation.resume(returning: false) }
            }
        }
    }

    /// Two requests through the line's loopback inbound; the smaller time in ms, -1 when neither answered.
    private static func measure(port: Int) async -> Int64 {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": port,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": port
        ]
        config.timeoutIntervalForRequest = TimeInterval(Etha.pingTimeoutSeconds)
        config.timeoutIntervalForResource = TimeInterval(Etha.pingTimeoutSeconds + 2)
        config.waitsForConnectivity = false
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let url = URL(string: Etha.probeURL) else { return -1 }
        var best: Int64 = -1
        for _ in 0..<attempts {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let t0 = Date()
            guard let (_, response) = try? await session.data(for: request), response is HTTPURLResponse else { continue }
            let ms = Int64(Date().timeIntervalSince(t0) * 1000)
            if best < 0 || ms < best { best = ms }
        }
        return best
    }
}
