import Foundation

/// A small text log file that keeps only its tail (the last ~limit bytes). Safe from one process at a time.
public final class RingLog {
    public let url: URL
    private let limit: Int
    private let queue = DispatchQueue(label: "skyray.ringlog")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()

    public init(url: URL, limit: Int = 512 * 1024) { self.url = url; self.limit = limit }

    public func log(_ level: String, _ message: String) {
        let line = "\(RingLog.stamp.string(from: Date())) \(level) \(message)\n"
        queue.async { [url, limit] in
            var data = (try? Data(contentsOf: url)) ?? Data()
            data.append(Data(line.utf8))
            if data.count > limit {
                data = data.suffix(limit / 2)
                if let nl = data.firstIndex(of: 0x0A) { data = data.suffix(from: nl + 1) }
            }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
    public func info(_ m: String) { log("I", m) }
    public func warn(_ m: String) { log("W", m) }
    public func error(_ m: String) { log("E", m) }

    public func tail(lines n: Int) -> String {
        queue.sync {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
            return text.split(separator: "\n").suffix(n).joined(separator: "\n")
        }
    }
    public func clear() { queue.sync { try? FileManager.default.removeItem(at: url) } }
}
