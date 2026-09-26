import Foundation
import SkyRayCore
import SkyRayXray

/// Measures every line with libXray's pingBatch (five per call). libXray serialises the batches itself,
/// so a 14-line subscription takes three batches, each bounded by the timeout.
enum LineTester {
    static func testAll(_ lines: [Line], bindInterface: String?) async -> [String: Int64] {
        let size = LibXrayBridge.maxPingBatch
        let chunks = stride(from: 0, to: lines.count, by: size).map { Array(lines[$0..<min($0 + size, lines.count)]) }
        var all: [String: Int64] = [:]
        for chunk in chunks {
            let part = await measure(chunk, bindInterface: bindInterface)
            all.merge(part) { _, new in new }
        }
        return all
    }

    private static func measure(_ chunk: [Line], bindInterface: String?) async -> [String: Int64] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var out: [String: Int64] = [:]
                let configs = chunk.compactMap { try? XrayConfigBuilder.pingConfig(outboundJSON: $0.outboundJSON, bindInterface: bindInterface) }
                guard configs.count == chunk.count,
                      let delays = try? LibXrayBridge.pingBatch(configs: configs, timeoutSeconds: Etha.pingTimeoutSeconds, url: Etha.probeURL),
                      delays.count == chunk.count else {
                    for line in chunk { out[line.id] = -1 }
                    continuation.resume(returning: out)
                    return
                }
                for (line, delay) in zip(chunk, delays) { out[line.id] = delay > 0 ? delay : -1 }
                continuation.resume(returning: out)
            }
        }
    }
}
