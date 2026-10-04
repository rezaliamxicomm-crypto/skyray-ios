import Foundation
import Darwin
import SkyRayCore

/// The physical interface to bind measurements to while the tunnel is up (en0 = Wi-Fi, pdp_ip0 = cellular).
enum NetworkInterfaces {
    static func physical() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let flags = Int32(entry.pointee.ifa_flags)
            let up = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0 && (flags & IFF_LOOPBACK) == 0
            if up, let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: entry.pointee.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("pdp_ip") { found.append(name) }
            }
            cursor = entry.pointee.ifa_next
        }
        if found.contains("en0") { return "en0" }
        if found.contains("pdp_ip0") { return "pdp_ip0" }
        return found.first
    }

    /// True while our tunnel is up: a utun interface carries the tunnel's own address. The app's own traffic then
    /// runs through the tunnel unless a socket is bound to the physical interface.
    static func tunnelIsUp() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let flags = Int32(entry.pointee.ifa_flags)
            if (flags & IFF_UP) != 0, let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: entry.pointee.ifa_name).hasPrefix("utun") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let size = socklen_t(host.count)
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, size, nil, 0, NI_NUMERICHOST) == 0,
                   host.withUnsafeBufferPointer({ String(cString: $0.baseAddress!) }) == Etha.tunnelIPv4 {
                    return true
                }
            }
            cursor = entry.pointee.ifa_next
        }
        return false
    }
}
