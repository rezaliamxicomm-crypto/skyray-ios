import Foundation
import Darwin

/// The utun file descriptor NetworkExtension opened for this process: the socket that answers
/// getsockopt(SYSPROTO_CONTROL, UTUN_OPT_IFNAME) with a "utun…" name (the method Xray's own docs use).
enum TunFD {
    static func find() -> Int32? {
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
