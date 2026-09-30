import Foundation

/// The Xray configs the app hands to libXray: the tunnel (extension) and a ping (app).
public enum XrayConfigBuilder {
    public struct Options {
        public var bufferSizeKB: Int = 4
        public var logLevel: String = "warning"
        /// Shecan, direct, for Iranian names; the rest through the line.
        public var directDNS: String = "178.22.122.100"
        public var proxyDNS: [String] = ["1.1.1.1", "8.8.8.8"]
        /// Splits the TLS ClientHello of the line's own connection (Xray's freedom `fragment`), the answer to a
        /// network that drops the handshake by its SNI. Off unless every line failed without it.
        public var fragment: Bool = false
        public var fragmentPackets: String = "tlshello"
        public var fragmentLength: String = "100-200"
        public var fragmentInterval: String = "10-20"
        /// Mux.cool: the phone's many app connections ride as substreams on a few real ones. Each real connection
        /// costs Xray TLS state, transport buffers and goroutines; a browser's burst of dozens took the extension
        /// past iOS's ~50 MiB limit on 2026-09-30, mux or not the per-byte cost is small.
        public var mux: Bool = true
        public var muxConcurrency: Int = 8
        public init() {}
    }

    public enum BuildError: Error { case invalidOutbound, serialization }

    /// The line's outbound as a dictionary with tag "proxy" and no mux.
    public static func outbound(from json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8), var ob = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw BuildError.invalidOutbound }
        ob["tag"] = "proxy"
        ob.removeValue(forKey: "mux")
        return ob
    }

    static func serialize(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        guard let s = String(data: data, encoding: .utf8) else { throw BuildError.serialization }
        return s
    }

    static func withSockopt(_ outbound: [String: Any], _ change: (inout [String: Any]) -> Void) -> [String: Any] {
        var ob = outbound
        var stream = ob["streamSettings"] as? [String: Any] ?? [:]
        var sockopt = stream["sockopt"] as? [String: Any] ?? [:]
        change(&sockopt)
        stream["sockopt"] = sockopt
        ob["streamSettings"] = stream
        return ob
    }

    /// The line's outbound — dialling through a fragmenting freedom outbound when asked — and that outbound.
    static func proxyOutbounds(_ proxy: [String: Any], options: Options, bindInterface: String? = nil) -> [[String: Any]] {
        var line = proxy
        if let iface = bindInterface, !iface.isEmpty { line = withSockopt(line) { $0["interface"] = iface } }
        guard options.fragment else { return [line] }
        line = withSockopt(line) { $0["dialerProxy"] = "fragment" }
        var fragment: [String: Any] = [
            "tag": "fragment",
            "protocol": "freedom",
            "settings": ["domainStrategy": "UseIPv4",
                         "fragment": ["packets": options.fragmentPackets, "length": options.fragmentLength, "interval": options.fragmentInterval]],
            "streamSettings": ["sockopt": ["tcpNoDelay": true]]
        ]
        if let iface = bindInterface, !iface.isEmpty { fragment = withSockopt(fragment) { $0["interface"] = iface } }
        return [line, fragment]
    }

    /// The tunnel's config: a loopback SOCKS5 inbound (TCP and UDP) that hev-socks5-tunnel feeds with the utun's
    /// packets, a loopback HTTP inbound the watchdog probes through, Iran-direct routing, DNS split domestic/foreign.
    public static func tunnelConfig(outboundJSON: String, socksPort: Int, probePort: Int, assetDir: String, xrayLogPath: String,
                                    options: Options = Options()) throws -> String {
        var proxy = try outbound(from: outboundJSON)
        if options.mux {
            proxy["mux"] = ["enabled": true, "concurrency": options.muxConcurrency, "xudpConcurrency": 16, "xudpProxyUDP443": "reject"]
        }
        var outbounds = proxyOutbounds(proxy, options: options)
        outbounds.append(["tag": "direct", "protocol": "freedom", "settings": ["domainStrategy": "UseIPv4"]])
        outbounds.append(["tag": "block", "protocol": "blackhole", "settings": ["response": ["type": "http"]]])
        outbounds.append(["tag": "dns-out", "protocol": "dns"])
        var dnsServers: [Any] = [
            ["address": options.directDNS, "port": 53, "domains": ["geosite:category-ir", "domain:ir"], "skipFallback": true]
        ]
        dnsServers.append(contentsOf: options.proxyDNS)
        let config: [String: Any] = [
            "env": ["XRAY_LOCATION_ASSET": assetDir],
            "log": ["loglevel": options.logLevel, "access": "none", "error": xrayLogPath, "dnsLog": false],
            "policy": [
                "levels": ["8": ["handshake": 4, "connIdle": 300, "uplinkOnly": 1, "downlinkOnly": 1, "bufferSize": options.bufferSizeKB]],
                "system": ["statsInboundUplink": false, "statsInboundDownlink": false, "statsOutboundUplink": false, "statsOutboundDownlink": false]
            ],
            "dns": ["tag": "dns-module", "queryStrategy": "UseIPv4", "servers": dnsServers],
            "inbounds": [
                ["tag": "socks", "protocol": "socks", "listen": "127.0.0.1", "port": socksPort,
                 "settings": ["auth": "noauth", "udp": true, "userLevel": 8],
                 "sniffing": ["enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": false]],
                ["tag": "probe", "protocol": "http", "listen": "127.0.0.1", "port": probePort, "settings": ["userLevel": 8]]
            ],
            "outbounds": outbounds,
            "routing": [
                "domainStrategy": "IPIfNonMatch",
                "domainMatcher": "linear",
                "rules": [
                    ["type": "field", "inboundTag": ["socks"], "port": "53", "network": "tcp,udp", "outboundTag": "dns-out"],
                    ["type": "field", "inboundTag": ["dns-module"], "ip": [options.directDNS], "outboundTag": "direct"],
                    ["type": "field", "inboundTag": ["dns-module"], "outboundTag": "proxy"],
                    ["type": "field", "port": "443", "network": "udp", "outboundTag": "block"],
                    ["type": "field", "ip": ["geoip:private"], "outboundTag": "direct"],
                    ["type": "field", "domain": ["domain:ir", "geosite:category-ir"], "outboundTag": "direct"],
                    ["type": "field", "ip": ["geoip:ir"], "outboundTag": "direct"]
                ]
            ]
        ]
        return try serialize(config)
    }

    /// One line for pingBatch; bound to the physical interface while the tunnel is up so the measurement does not
    /// run through the tunnel.
    public static func pingConfig(outboundJSON: String, bindInterface: String? = nil, options: Options = Options()) throws -> String {
        let proxy = try outbound(from: outboundJSON)
        let outbounds = proxyOutbounds(proxy, options: options, bindInterface: bindInterface)
        return try serialize(["log": ["loglevel": "none"], "outbounds": outbounds])
    }
}
