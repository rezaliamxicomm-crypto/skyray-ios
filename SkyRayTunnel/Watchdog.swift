import Foundation
import SkyRayCore

/// Probes the current line every 3 minutes (20 s while a failure is being confirmed); two misses in a row
/// hand the tried set to `onFailure`, which switches the line and returns the new tried set.
final class Watchdog {
    private let queue: DispatchQueue
    private let probe: () -> Int64
    private let onProbe: (Int64) -> Void
    private let onFailure: (Set<String>) -> Set<String>
    private var timer: DispatchSourceTimer?
    private var failures = 0
    private var tried: Set<String> = []
    private var paused = false

    init(queue: DispatchQueue, probe: @escaping () -> Int64, onProbe: @escaping (Int64) -> Void, onFailure: @escaping (Set<String>) -> Set<String>) {
        self.queue = queue; self.probe = probe; self.onProbe = onProbe; self.onFailure = onFailure
    }

    func start(after delay: TimeInterval) { paused = false; schedule(delay) }

    func pause() { paused = true; timer?.cancel(); timer = nil }

    func resume(after delay: TimeInterval) { paused = false; failures = 0; schedule(delay) }

    func stop() { timer?.cancel(); timer = nil }

    private func schedule(_ delay: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + delay)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        if paused { return }
        let ms = probe()
        onProbe(ms)
        if ms > 0 {
            failures = 0
            tried = []
        } else {
            failures += 1
            if failures >= Etha.watchdogFailures {
                failures = 0
                tried = onFailure(tried)
            }
        }
        schedule(LineRotation.nextProbeDelay(failures: failures))
    }
}
