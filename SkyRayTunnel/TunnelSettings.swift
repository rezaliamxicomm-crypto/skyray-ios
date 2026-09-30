import Foundation
import NetworkExtension
import SkyRayCore

/// The tunnel's addresses and routes: everything through the tunnel except the LAN ranges; all DNS enters
/// the tunnel (Xray's DNS module answers it: Iranian names direct, the rest through the line). No
/// enforceRoutes / includeAllNetworks: they stopped all traffic on the previous SkyRay.
enum TunnelSettings {
    static func make() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: Etha.tunnelRemoteIPv4)
        settings.mtu = NSNumber(value: Etha.tunnelMTU)

        let v4 = NEIPv4Settings(addresses: [Etha.tunnelIPv4], subnetMasks: ["255.255.255.252"])
        v4.includedRoutes = [NEIPv4Route.default()]
        v4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0")
        ]
        settings.ipv4Settings = v4

        let v6 = NEIPv6Settings(addresses: [Etha.tunnelIPv6], networkPrefixLengths: [64])
        v6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = v6

        let dns = NEDNSSettings(servers: Etha.tunnelDNS)
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        return settings
    }
}
