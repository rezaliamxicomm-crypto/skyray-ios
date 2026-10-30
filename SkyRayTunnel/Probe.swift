import Foundation
import SkyRayCore

/// A request through the running Xray (its loopback HTTP inbound), so the measurement is of the line the
/// tunnel is on. Blocking; call it on the tunnel's queue, never on the main thread.
///
/// Two paths. A plain `http://` target — the box's own probe target, `Etha.probeURL` — goes over a raw socket to the
/// inbound as an absolute-form HEAD, because the system stack refuses plain HTTP unless the app declares an exception
/// (App Transport Security): in 2.0.0 every probe to the target failed before touching the network and Auto measured
/// against the fallback for the whole session. An `https://` target (the fallback) goes through URLSession with the
/// inbound as its proxy, as before.
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
            let ms = measureLine(url: url)
            if ms > 0 { return ms }
        }
        return -1
    }

    /// Auto's measurement of one line (AutoEngine) against `url` (the box's probe target, else the fallback): one
    /// window for the first request — no answer within it and the line counts as failed, -1 — then the warm second
    /// down the kept-alive connection, the smaller time kept.
    func measureLine(url: String = Etha.probeURL) -> Int64 {
        if url.lowercased().hasPrefix("http://") { return rawMeasure(url) }
        guard let first = head(url) else { return -1 }
        if let second = head(url) { return min(first, second) }
        return first
    }

    /// The session's connections closed; the probe is not used after this.
    func invalidate() { session.finishTasksAndInvalidate() }

    // MARK: https — URLSession through the inbound

    private func head(_ urlString: String) -> Int64? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let done = DispatchSemaphore(value: 0)
        var answered = false
        let started = Date()
        session.dataTask(with: request) { _, response, _ in
            answered = ((response as? HTTPURLResponse)?.statusCode ?? 600) < 400
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + .seconds(timeoutSeconds + 3))
        return answered ? Int64(Date().timeIntervalSince(started) * 1000) : nil
    }

    // MARK: http — a raw socket to the inbound

    /// One TCP connection to the inbound, two absolute-form HEAD requests on it (HTTP/1.1 keeps it open), the smaller
    /// time; -1 when the first gets no answer under 400 within the window. Nothing but the loopback is touched here:
    /// the inbound sends the request down its line, the box answers 204 from its own target.
    private func rawMeasure(_ urlString: String) -> Int64 {
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else { return -1 }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        defer { close(fd) }
        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        _ = setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return -1 }
        let authority = host + (url.port.map { ":\($0)" } ?? "")
        let path = url.path.isEmpty ? "/" : url.path
        let request = "HEAD http://\(authority)\(path) HTTP/1.1\r\nHost: \(authority)\r\nUser-Agent: SkyRay\r\nConnection: keep-alive\r\n\r\n"
        guard let first = rawExchange(fd, request) else { return -1 }
        if let second = rawExchange(fd, request) { return min(first, second) }
        return first
    }

    /// Writes one request, reads the response's head; the time to the end of the head, nil when the status is 400 or
    /// more or nothing came within the socket's timeout. A HEAD answer has no body, so the head is the whole answer.
    private func rawExchange(_ fd: Int32, _ request: String) -> Int64? {
        let started = Date()
        let bytes = Array(request.utf8)
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBufferPointer { send(fd, $0.baseAddress! + sent, $0.count - sent, 0) }
            if n <= 0 { return nil }
            sent += n
        }
        var chunk = [UInt8](repeating: 0, count: 2048)
        var got = [UInt8]()
        while got.count < 32768 {
            let n = chunk.withUnsafeMutableBufferPointer { recv(fd, $0.baseAddress!, $0.count, 0) }
            if n <= 0 { return nil }
            got.append(contentsOf: chunk[0..<n])
            guard let end = Probe.headEnd(got) else { continue }
            guard let head = String(bytes: got[0..<end], encoding: .utf8),
                  let statusLine = head.split(separator: "\r\n", omittingEmptySubsequences: true).first else { return nil }
            let parts = statusLine.split(separator: " ")
            guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let code = Int(parts[1]), code < 400 else { return nil }
            return Int64(Date().timeIntervalSince(started) * 1000)
        }
        return nil
    }

    /// The index just past the first "\r\n\r\n", or nil.
    static func headEnd(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for i in 0...(bytes.count - 4) where bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10 {
            return i + 4
        }
        return nil
    }
}
