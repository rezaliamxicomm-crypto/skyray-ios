import Foundation
import NetworkExtension

/// The tunnel's addresses and routes: everything through the tunnel except the LAN ranges; all DNS enters
/// the tunnel (Xray's DNS module answers it: Iranian names direct, the rest through the proxy).
enum TunnelSettings {
    static func make() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "198.18.0.2")
        settings.mtu = NSNumber(value: 1500)

        let v4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.252"])
        v4.includedRoutes = [NEIPv4Route.default()]
        v4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0")
        ]
        settings.ipv4Settings = v4

        let v6 = NEIPv6Settings(addresses: ["fd00:5379:5261:7900::1"], networkPrefixLengths: [64])
        v6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = v6

        let dns = NEDNSSettings(servers: ["1.1.1.1"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        return settings
    }
}
