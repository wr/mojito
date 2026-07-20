import AppKit
import ApplicationServices
import os

/// AX-focused element cache. `AXUIElementCopyAttributeValue(system, …)`
/// is a synchronous cross-process IPC that can stall hundreds of ms on
/// hung / busy apps (Electron under load). Doing that on every `:` and
/// picker show produced visible lag; this converts to a pointer read.
///
/// The seed query and observer registration are themselves synchronous IPC
/// into the newly-activated app, so they run on a background queue — the
/// main thread also services the keystroke event tap, and a focus-flap storm
/// (notification banners, menu-bar overlay apps) blocking it there stalled
/// typing system-wide (W-547). Until the seed lands, `element` is nil and
/// callers fall back to a fresh fetch.
///
/// Falls back gracefully: if observer creation fails (no AX permission,
/// non-introspectable app), `element` returns nil and callers fetch fresh.
@MainActor
final class FocusedElementCache {
    static let shared = FocusedElementCache()

    /// Nil during transitions / when AX is unusable.
    private(set) var element: AXUIElement?

    /// Engine uses this to detect cross-app focus changes during the
    /// deferred picker-show window.
    private(set) var focusedPID: pid_t?

    /// Fires on every focus change. Engine cancels in-flight captures.
    var onFocusChange: (() -> Void)?

    /// Fires when a background seed publishes its element. NOT a focus
    /// event — but focus may have moved while the observer wasn't yet
    /// registered, so Engine reconciles any in-flight capture against the
    /// freshly seeded element (and only cancels on a positive mismatch).
    var onSeedInstalled: (() -> Void)?

    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var workspaceObserver: NSObjectProtocol?

    /// Invalidates in-flight background seeds when a newer activation
    /// supersedes them. Lock-protected (not main-actor state) so `seed` can
    /// check staleness from the background queue and skip its blocking IPC
    /// instead of running a full round-trip only to be discarded — under a
    /// sustained activation storm those dead seeds would otherwise queue up
    /// serially and delay the one that matters.
    private let refreshGeneration = OSAllocatedUnfairLock(initialState: 0)

    /// Coalesces activation bursts (banner appears → app reactivates within
    /// ~100ms) into one seed round-trip.
    private var pendingSeed: DispatchWorkItem?
    private static let seedDebounce: TimeInterval = 0.1

    /// Serial so a hung app's seed can't overlap the next one; each call is
    /// bounded by `seedTimeout` below.
    private static let seedQueue = DispatchQueue(label: "mojito.ax.focusSeed", qos: .userInitiated)

    /// Per-element AX timeout for the seed round-trips. Tighter than the
    /// process-wide 0.5s: a stale seed is discarded by the generation check
    /// anyway, so waiting long for a slow app buys nothing.
    private static let seedTimeout: Float = 0.25

    private init() {
        refreshActiveApp()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                FocusedElementCache.shared.refreshActiveApp()
            }
        }
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        // No teardownObserver() — we're an app-lifetime singleton and
        // dropping our AXObserver reference releases the run loop source.
    }

    /// Synchronous part of an app switch: drop the stale element immediately
    /// (a cross-app pointer must never be served) and schedule the IPC-heavy
    /// seed off the main thread.
    private func refreshActiveApp() {
        teardownObserver()
        let generation = refreshGeneration.withLock { value in
            value += 1
            return value
        }
        pendingSeed?.cancel()

        guard let app = NSWorkspace.shared.frontmostApplication else {
            element = nil
            focusedPID = nil
            onFocusChange?()
            return
        }
        let pid = app.processIdentifier
        element = nil
        focusedPID = pid
        DebugRecorder.record(.focus, "app", ["bundleID": app.bundleIdentifier ?? "—"])
        onFocusChange?()

        let work = DispatchWorkItem { [weak self] in
            Self.seedQueue.async { self?.seed(pid: pid, generation: generation) }
        }
        pendingSeed = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.seedDebounce, execute: work)
    }

    /// Runs on `seedQueue`. Both AX calls here block on the target app's
    /// reply, which is the whole reason they're off the main thread. A seed
    /// superseded by a newer activation bails before each round-trip — its
    /// result would be discarded anyway, and dead seeds draining serially
    /// would delay the live one.
    private nonisolated func seed(pid: pid_t, generation: Int) {
        guard refreshGeneration.withLock({ $0 }) == generation else { return }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, Self.seedTimeout)

        var ref: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &ref
        )
        var seeded: AXUIElement?
        if status == .success, let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() {
            seeded = (ref as! AXUIElement)
        }

        // C function pointer — no captures allowed, route via refcon.
        let callback: AXObserverCallback = { _, focusedElement, _, refcon in
            guard let refcon else { return }
            let cache = Unmanaged<FocusedElementCache>.fromOpaque(refcon).takeUnretainedValue()
            // Source is on the main run loop (added below), so we're on main.
            MainActor.assumeIsolated {
                cache.element = focusedElement
                cache.onFocusChange?()
            }
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard refreshGeneration.withLock({ $0 }) == generation else { return }
        var newObserver: AXObserver?
        if AXObserverCreate(pid, callback, &newObserver) == .success, let obs = newObserver {
            // Re-check after create (local, but a bump can land any time):
            // the registration below is the blocking IPC worth skipping.
            guard refreshGeneration.withLock({ $0 }) == generation else { return }
            // Best-effort — fails for system apps / non-AX apps; the seeded
            // value still serves. Synchronous IPC, hence off-main.
            AXObserverAddNotification(
                obs,
                axApp,
                kAXFocusedUIElementChangedNotification as CFString,
                refcon
            )
        }
        let observer = newObserver

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.install(seeded: seeded, observer: observer, pid: pid, generation: generation)
            }
        }
    }

    /// Publishes a finished seed, unless a newer activation made it stale.
    /// Deliberately does NOT fire `onFocusChange`: focus hasn't moved — this
    /// is the same focus the activation-time fire announced, just resolved.
    /// A synthetic fire here would cancel a capture the user started during
    /// the seed window (its snapshot is nil) and clear a fresh emoticon undo.
    private func install(seeded: AXUIElement?, observer: AXObserver?, pid: pid_t, generation: Int) {
        guard generation == refreshGeneration.withLock({ $0 }) else { return }
        element = seeded
        if let observer {
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
            self.observer = observer
            self.observedPID = pid
        }
        onSeedInstalled?()
    }

    private func teardownObserver() {
        if let obs = observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(obs),
                .commonModes
            )
        }
        observer = nil
        observedPID = nil
    }
}
