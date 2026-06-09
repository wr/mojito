import Foundation

/// Repeating main-runloop timer for frame-driven loops. Owns the Timer
/// lifecycle (scheduled in `.common` mode so it keeps firing during event
/// tracking) and tracks elapsed time since `start`. Per-frame closures
/// that capture their owner should do so weakly — the Timer retains the
/// closure until `stop()` (or this object's deinit) invalidates it.
@MainActor
final class AnimationTicker {
    private var timer: Timer?
    private(set) var startDate = Date()

    var elapsed: TimeInterval { Date().timeIntervalSince(startDate) }
    var isRunning: Bool { timer != nil }

    /// Starts (or restarts) the loop. `onTick` runs on the main actor once
    /// per `interval`, receiving the time elapsed since this call.
    func start(interval: TimeInterval, _ onTick: @escaping @MainActor (TimeInterval) -> Void) {
        stop()
        let start = Date()
        startDate = start
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            // Scheduled on the main run loop, so the callback is already
            // on the main thread.
            MainActor.assumeIsolated {
                onTick(Date().timeIntervalSince(start))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
