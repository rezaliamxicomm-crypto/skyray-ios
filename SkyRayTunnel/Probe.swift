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
    private let timeoutMs: Int
    private var sessionMade: URLSession?
    private var fd: Int32 = -1              // the raw tunnel of an http:// target, from `open` to `close` (2.1.1)
    private var request = ""                // the request `open` sent, sent again by `warm`
    private var httpsURL: String?           // an https:// target measured through URLSession, from `open` to `warm`

    convenience init(port: Int, timeoutSeconds: Int = 10) { self.init(port: port, timeoutMs: timeoutSeconds * 1000) }

    /// `timeoutMs`: the window of one request (the failover probe asks for 1.5 s; the trickle for the policy's seconds).
    init(port: Int, timeoutMs: Int) {
        self.port = port
        self.timeoutMs = max(200, timeoutMs)
    }

    /// The URLSession, made only when an https target (the fallback) is measured: the raw-socket path needs none, and a
    /// session per probe would be hundreds an hour in a process the system kills near 50 MiB.
    private var session: URLSession {
        if let s = sessionMade { return s }
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": port,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": port
        ]
        config.timeoutIntervalForRequest = TimeInterval(timeoutMs) / 1000
        config.timeoutIntervalForResource = TimeInterval(timeoutMs) / 1000 + 2
        config.waitsForConnectivity = false
        config.urlCache = nil
        let s = URLSession(configuration: config)
        sessionMade = s
        return s
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

    /// One line measured against `url` (the box's probe target, else the fallback): `open` then `warm`, the warm time —
    /// the round trip, not the handshakes —, -1 when either got no answer. Until 2.1.0 the second request went to the
    /// inbound as a plain proxy request, which the inbound answers with a closed connection, so every reading was a cold
    /// one and the first (cold) time was kept when the second failed.
    func measureLine(url: String = Etha.probeURL) -> Int64 {
        defer { close() }
        guard open(url: url) != nil else { return -1 }
        return warm() ?? -1
    }

    /// Phase one of a measurement (2.1.1): the connection through the line and the first request — the cold time, the
    /// handshakes and all — kept open for `warm`; nil when nothing answered within the window. An `http://` target goes
    /// through a CONNECT tunnel to the inbound on a raw socket (nothing but the loopback is touched here: the inbound
    /// sends the bytes down its line, the box answers 204 from its own target); an `https://` one through URLSession.
    func open(url urlString: String) -> Int64? {
        close()
        if urlString.lowercased().hasPrefix("http://") { return rawOpen(urlString) }
        httpsURL = urlString
        return head(urlString)
    }

    /// Phase two: the same request once more down the connection `open` made — the warm round trip; nil when it got no
    /// answer (the connection is then closed).
    func warm() -> Int64? {
        if fd >= 0 {
            if let ms = rawExchange(fd, request) { return ms }
            close(); return nil
        }
        guard let u = httpsURL else { return nil }
        return head(u)
    }

    /// The raw tunnel closed, when one is open.
    func close() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }

    /// The session's connections closed (when one was made) and the raw tunnel; the probe is not used after this.
    func invalidate() { close(); sessionMade?.finishTasksAndInvalidate(); sessionMade = nil }

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
        _ = done.wait(timeout: .now() + .milliseconds(timeoutMs + 3000))
        return answered ? Int64(Date().timeIntervalSince(started) * 1000) : nil
    }

    // MARK: http — a raw socket to the inbound

    /// One TCP connection to the inbound, a CONNECT tunnel to the target through it, then the first HEAD request inside
    /// the tunnel: its time (the cold one), or nil when the tunnel or the request got no answer under 400 within the
    /// window. The socket stays open for `warm`.
    private func rawOpen(_ urlString: String) -> Int64? {
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else { return nil }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var tv = timeval(tv_sec: timeoutMs / 1000, tv_usec: Int32((timeoutMs % 1000) * 1000))
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
        guard connected == 0 else { Darwin.close(fd); return nil }
        let authority = host + (url.port.map { ":\($0)" } ?? "")
        let target = host + ":\(url.port ?? 80)"
        let path = url.path.isEmpty ? "/" : url.path
        let connect = "CONNECT \(target) HTTP/1.1\r\nHost: \(target)\r\nUser-Agent: SkyRay\r\n\r\n"
        guard rawExchange(fd, connect) != nil else { Darwin.close(fd); return nil }
        request = "HEAD \(path) HTTP/1.1\r\nHost: \(authority)\r\nUser-Agent: SkyRay\r\nConnection: keep-alive\r\n\r\n"
        guard let first = rawExchange(fd, request) else { Darwin.close(fd); return nil }
        self.fd = fd
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
