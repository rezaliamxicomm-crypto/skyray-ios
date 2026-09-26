import Foundation
import Darwin

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
}
