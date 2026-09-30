import Foundation
import HevSocks5Tunnel

/// hev-socks5-tunnel (MIT): reads the IP packets of the utun device and turns them into SOCKS5 connections, TCP and
/// UDP, to Xray's loopback inbound. One instance per process; `main` blocks on its thread until `quit`.
public final class HevTunnel {
    public struct Stats: Equatable {
        public let txPackets: Int
        public let txBytes: Int
        public let rxPackets: Int
        public let rxBytes: Int
    }

    private var thread: Thread?

    public init() {}

    /// The YAML hev reads. The misc values follow upstream's advice for low-memory iOS (small TCP buffers, the task
    /// stack sized to them): with the previous app's 64 KiB buffers the extension reached 46 MiB under a download on
    /// 2026-09-30 and iOS killed it at its ~50 MiB limit.
    public static func config(mtu: Int, ipv4: String, ipv6: String, socksPort: Int) -> String {
        """
        tunnel:
          mtu: \(mtu)
          ipv4: \(ipv4)
          ipv6: '\(ipv6)'
        socks5:
          port: \(socksPort)
          address: 127.0.0.1
          udp: 'udp'
        misc:
          task-stack-size: 24576
          tcp-buffer-size: 4096
          max-session-count: 256
          connect-timeout: 5000
          tcp-read-write-timeout: 300000
          udp-read-write-timeout: 60000
          limit-nofile: 65535
          log-level: warn

        """
    }

    /// Runs the tunnel on its own 4 MiB-stack thread; `onExit` gets the return code when it stops for any reason
    /// (a `stop()` included), on that thread.
    public func start(config: String, tunFD: Int32, onExit: @escaping (Int32) -> Void) {
        let t = Thread {
            var bytes = Array(config.utf8)
            let code = bytes.withUnsafeMutableBufferPointer { buffer -> Int32 in
                hev_socks5_tunnel_main_from_str(buffer.baseAddress, UInt32(buffer.count), tunFD)
            }
            onExit(code)
        }
        t.name = "hev-socks5-tunnel"
        t.stackSize = 4 << 20
        t.qualityOfService = .userInitiated
        thread = t
        t.start()
    }

    public func stop() {
        hev_socks5_tunnel_quit()
        thread = nil
    }

    public func stats() -> Stats {
        var tp = 0, tb = 0, rp = 0, rb = 0
        hev_socks5_tunnel_stats(&tp, &tb, &rp, &rb)
        return Stats(txPackets: tp, txBytes: tb, rxPackets: rp, rxBytes: rb)
    }
}
