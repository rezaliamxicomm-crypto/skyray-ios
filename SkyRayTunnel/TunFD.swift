import Foundation
import Darwin
import NetworkExtension

/// The utun file descriptor NetworkExtension opened for this process. First the packet flow's own socket (the
/// way the previous SkyRay found it on every iOS it ran on), else the socket that answers
/// getsockopt(SYSPROTO_CONTROL, UTUN_OPT_IFNAME) with a "utun…" name.
enum TunFD {
    static func find(in provider: NEPacketTunnelProvider) -> Int32? {
        if let fd = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32, fd >= 0 { return fd }
        return scan()
    }

    static func scan() -> Int32? {
        let sysprotoControl: Int32 = 2
        let utunOptIfname: Int32 = 2
        var buffer = [CChar](repeating: 0, count: 16)   // IFNAMSIZ
        for fd in Int32(0)...Int32(1024) {
            var length = socklen_t(buffer.count)
            let rc = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
                getsockopt(fd, sysprotoControl, utunOptIfname, ptr.baseAddress, &length)
            }
            if rc == 0 {
                let name = String(cString: buffer)
                if name.hasPrefix("utun") { return fd }
            }
        }
        return nil
    }
}
