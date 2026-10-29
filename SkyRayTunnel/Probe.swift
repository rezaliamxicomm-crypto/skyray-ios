import Foundation
import SkyRayCore

/// A request through the running Xray (its loopback HTTP inbound), so the measurement is of the line the
/// tunnel is on. Blocking; call it on the tunnel's queue, never on the main thread.
final class Probe {
    let port: Int
    private let session: URLSession

    private let timeoutSeconds: Int

    init(port: Int, timeoutSeconds: Int = 10) {
        self.port = port
        self.timeoutSeconds = timeoutSeconds
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": port,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": port
        ]
        config.timeoutIntervalForRequest = TimeInterval(timeoutSeconds)
        config.timeoutIntervalForResource = TimeInterval(timeoutSeconds + 2)
        config.waitsForConnectivity = false
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    /// The warm round trip in milliseconds — two requests down the kept-alive connection, the smaller one, as
    /// the app's line test and the Android app measure — or -1 when nothing answered.
    func measure() -> Int64 {
        for url in [Etha.probeURL, Etha.probeFallbackURL] {
            guard let first = head(url) else { continue }
            if let second = head(url) { return min(first, second) }
            return first
        }
        return -1
    }

    /// Auto's measurement of one line (AutoEngine): one window for the first request — no answer within it and the
    /// line counts as failed, -1 — then the warm second down the kept-alive connection, the smaller time kept.
    func measureLine() -> Int64 {
        guard let first = head(Etha.probeURL) else { return -1 }
        if let second = head(Etha.probeURL) { return min(first, second) }
        return first
    }

    /// The session's connections closed; the probe is not used after this.
    func invalidate() { session.finishTasksAndInvalidate() }

    private func head(_ urlString: String) -> Int64? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let done = DispatchSemaphore(value: 0)
        var answered = false
        let started = Date()
        session.dataTask(with: request) { _, response, _ in
            answered = (response as? HTTPURLResponse) != nil
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + .seconds(timeoutSeconds + 3))
        return answered ? Int64(Date().timeIntervalSince(started) * 1000) : nil
    }
}
