import Foundation

/// The Xray configs the app hands to libXray: the tunnel (extension) and a ping (app).
public enum XrayConfigBuilder {
    public struct Options {
        public var bufferSizeKB: Int = 4
        public var logLevel: String = "warning"
        public var mtu: Int = 1500
        public var directDNS: String = "178.22.122.100"
        public var proxyDNS: String = "1.1.1.1"
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

    /// The full config of the tunnel extension: the tun inbound on the utun fd, Iran-direct routing,
    /// a loopback HTTP inbound the watchdog probes through, DNS split domestic/foreign.
    public static func tunnelConfig(outboundJSON: String, tunFD: Int32, assetDir: String, xrayLogPath: String,
                                    probePort: Int, options: Options = Options()) throws -> String {
        let proxy = try outbound(from: outboundJSON)
        let config: [String: Any] = [
            "env": ["XRAY_TUN_FD": String(tunFD), "xray.tun.fd": String(tunFD), "XRAY_LOCATION_ASSET": assetDir],
            "log": ["loglevel": options.logLevel, "access": "none", "error": xrayLogPath, "dnsLog": false],
            "policy": [
                "levels": ["8": ["handshake": 4, "connIdle": 300, "uplinkOnly": 1, "downlinkOnly": 1, "bufferSize": options.bufferSizeKB]],
                "system": ["statsInboundUplink": false, "statsInboundDownlink": false, "statsOutboundUplink": false, "statsOutboundDownlink": false]
            ],
            "dns": [
                "tag": "dns-module",
                "queryStrategy": "UseIPv4",
                "servers": [
                    ["address": options.directDNS, "port": 53, "domains": ["geosite:category-ir", "domain:ir"], "skipFallback": true, "tag": "dns-domestic"],
                    options.proxyDNS
                ]
            ],
            "inbounds": [
                ["tag": "tun", "protocol": "tun", "settings": ["mtu": options.mtu, "userLevel": 8],
                 "sniffing": ["enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": false]],
                ["tag": "probe", "protocol": "http", "listen": "127.0.0.1", "port": probePort, "settings": ["userLevel": 8]]
            ],
            "outbounds": [
                proxy,
                ["tag": "direct", "protocol": "freedom", "settings": ["domainStrategy": "UseIPv4"]],
                ["tag": "block", "protocol": "blackhole", "settings": ["response": ["type": "http"]]],
                ["tag": "dns-out", "protocol": "dns"]
            ],
            "routing": [
                "domainStrategy": "AsIs",
                "rules": [
                    ["type": "field", "inboundTag": ["tun"], "port": "53", "network": "tcp,udp", "outboundTag": "dns-out"],
                    ["type": "field", "inboundTag": ["dns-domestic"], "outboundTag": "direct"],
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

    /// One outbound for pingBatch; bound to the physical interface while the tunnel is up so the
    /// measurement does not run through the tunnel.
    public static func pingConfig(outboundJSON: String, bindInterface: String? = nil) throws -> String {
        var proxy = try outbound(from: outboundJSON)
        if let iface = bindInterface, !iface.isEmpty {
            var stream = proxy["streamSettings"] as? [String: Any] ?? [:]
            var sockopt = stream["sockopt"] as? [String: Any] ?? [:]
            sockopt["interface"] = iface
            stream["sockopt"] = sockopt
            proxy["streamSettings"] = stream
        }
        return try serialize(["log": ["loglevel": "none"], "outbounds": [proxy]])
    }
}
