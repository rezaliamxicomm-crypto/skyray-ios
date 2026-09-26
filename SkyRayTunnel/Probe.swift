import Foundation
import SkyRayCore

/// A request through the running Xray (its loopback HTTP inbound), so the measurement is of the line the
/// tunnel is on. Blocking; call it on the tunnel's queue, never on the main thread.
final class Probe {
    let port: Int
    private let session: URLSession

    init(port: Int) {
        self.port = port
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": port,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": port
        ]
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    /// Milliseconds to the first answer, or -1.
    func measure() -> Int64 {
        for url in [Etha.probeURL, Etha.probeFallbackURL] {
            if let ms = head(url) { return ms }
        }
        return -1
    }

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
        _ = done.wait(timeout: .now() + 13)
        return answered ? Int64(Date().timeIntervalSince(started) * 1000) : nil
    }
}
