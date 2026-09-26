import Foundation
import LibXray

/// The one door to libXray (apiVersion 3): a JSON request in, a JSON response out. Every method here maps
/// to the README of the pinned release (docs/libxray-api.md). Blocking calls — run them off the main thread.
public enum LibXrayError: Error, CustomStringConvertible {
    case encoding
    case failed(String)
    case unexpected(String)

    public var description: String {
        switch self {
        case .encoding: return "libXray: request encoding failed"
        case .failed(let e): return "libXray: \(e)"
        case .unexpected(let e): return "libXray: unexpected response: \(e)"
        }
    }
}

public enum LibXrayBridge {
    /// pingBatch marks an error as 10000 ms and a timeout as 11000 ms.
    public static let pingErrorDelay: Int64 = 10000
    public static let maxPingBatch = 5

    private static let lock = NSLock()

    /// Sends one request; returns the `data` member (any JSON value) or throws the `error` text.
    @discardableResult
    public static func invoke(_ method: String, payload: [String: Any] = [:]) throws -> Any? {
        let request: [String: Any] = ["apiVersion": 3, "method": method, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: request), let json = String(data: data, encoding: .utf8) else {
            throw LibXrayError.encoding
        }
        lock.lock(); defer { lock.unlock() }
        let text: String = json.withCString { cString -> String in
            guard let copy = strdup(cString) else { return "" }
            defer { free(copy) }
            guard let out = CGoInvoke(copy) else { return "" }
            defer { CGoFree(out) }
            return String(cString: out)
        }
        guard let responseData = text.data(using: .utf8),
              let response = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] else {
            throw LibXrayError.unexpected(String(text.prefix(200)))
        }
        if (response["success"] as? Bool) == true { return response["data"] }
        throw LibXrayError.failed((response["error"] as? String) ?? String(text.prefix(200)))
    }

    public static func runXray(configJSON: String) throws { try invoke("runXray", payload: ["xrayJson": configJSON]) }
    public static func stopXray() throws { try invoke("stopXray") }

    public static func xrayVersion() -> String {
        guard let data = try? invoke("xrayVersion") else { return "?" }
        if let s = data as? String { return s }
        if let d = data as? [String: Any] {
            for key in ["version", "xrayVersion", "value"] { if let v = d[key] as? String { return v } }
        }
        return "\(data)"
    }

    public static func getFreePorts(_ count: Int) throws -> [Int] {
        let data = try invoke("getFreePorts", payload: ["count": count])
        if let d = data as? [String: Any], let ports = d["ports"] as? [Int], ports.count == count { return ports }
        if let ports = data as? [Int], ports.count == count { return ports }
        throw LibXrayError.unexpected("getFreePorts")
    }

    /// Share links (one or many, or a base64 subscription body) → the projected Xray outbounds.
    public static func convertShareLinks(_ text: String) throws -> [[String: Any]] {
        let data = try invoke("convertShareLinksToXrayJson", payload: ["text": text])
        guard let d = data as? [String: Any], let outbounds = d["outbounds"] as? [[String: Any]], !outbounds.isEmpty else {
            throw LibXrayError.unexpected("convertShareLinksToXrayJson")
        }
        return outbounds
    }

    /// Measures up to five configs at once; returns the delay per config in ms, -1 for an error or timeout.
    public static func pingBatch(configs: [String], outboundTag: String = "proxy", timeoutSeconds: Int, url: String) throws -> [Int64] {
        precondition(configs.count <= maxPingBatch)
        let items: [[String: Any]] = configs.map { ["xrayJson": $0, "outboundTag": outboundTag] }
        let data = try invoke("pingBatch", payload: ["configs": items, "timeout": timeoutSeconds, "url": url])
        let results: [Any]
        if let a = data as? [Any] { results = a }
        else if let d = data as? [String: Any], let a = (d["results"] ?? d["items"] ?? d["data"]) as? [Any] { results = a }
        else { throw LibXrayError.unexpected("pingBatch") }
        return results.map { item -> Int64 in
            guard let r = item as? [String: Any] else { return -1 }
            let delay = (r["delay"] as? NSNumber)?.int64Value ?? -1
            if (r["success"] as? Bool) == false { return -1 }
            if delay <= 0 || delay >= pingErrorDelay { return -1 }
            return delay
        }
    }
}
