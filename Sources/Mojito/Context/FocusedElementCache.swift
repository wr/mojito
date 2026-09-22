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

    /// Nil during transitions / when AX is unusable. Any reassignment (app
    /// switch, seed install, within-app focus move) invalidates the cached
    /// field info below — it described the *previous* focus.
    private(set) var element: AXUIElement? {
        didSet {
            haveFieldInfo = false
            focusedRole = nil
            _ = fieldGeneration.withLock { $0 += 1 }   // cancel in-flight reclassifies
        }
    }

    /// Bumped on every `element` change so a queued off-thread reclassify can bail
    /// before its (up to `seedTimeout`) AX round-trips instead of piling up a
    /// serial backlog under a focus storm. Lock-protected so `reclassify` can read
    /// it from the seed queue.
    private let fieldGeneration = OSAllocatedUnfairLock(initialState: 0)

    // Cached per focus to skip AX IPC on the tap thread; reset on element change (see element.didSet), fail-closed until set.
    private(set) var focusedIsSecure = false
    private(set) var focusedIsEditable = false
    private(set) var haveFieldInfo = false
    /// Raw AXRole the classification was read from (nil if AX couldn't answer).
    /// Diagnostics only — lets a debug line tell "field not classified yet"
    /// apart from "classified as a real secure/opaque role".
    private(set) var focusedRole: String?

    /// Publishes an off-thread classification for the *current* `element`. Guard
    /// with a `CFEqual` element check at the call site so a classify that lands
    /// after focus moved on can't attach stale info to the new focus.
    private func publishFieldInfo(secure: Bool, editable: Bool, role: String?) {
        focusedIsSecure = secure
        focusedIsEditable = editable
        focusedRole = role
        haveFieldInfo = true
    }

    // Classifies off-thread; publishes iff focus hasn't moved. AX-opaque apps that miss within-app moves rely on the exclusion list as backstop.
    private nonisolated func reclassify(_ element: AXUIElement) {
        let generation = fieldGeneration.withLock { $0 }
        Self.seedQueue.async {
            // Focus already moved on again → skip the round-trips entirely.
            guard self.fieldGeneration.withLock({ $0 }) == generation else { return }
            AXUIElementSetMessagingTimeout(element, Self.seedTimeout)
            let info = AppContextDetector.classify(element)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let cache = FocusedElementCache.shared
                    guard let current = cache.element, CFEqual(current, element) else { return }
                    cache.publishFieldInfo(secure: info.secure, editable: info.editable, role: info.role)
                    cache.onFieldInfoPublished?()
                }
            }
        }
    }

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

    /// Fires when an in-app focus move's off-thread classification lands.
    var onFieldInfoPublished: (() -> Void)?

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

    /// Backoff for re-seeding while the seed comes back empty (~25s total). A
    /// cold-launching app (Slack right after `open`) answers every AX call with
    /// kAXErrorCannotComplete for its first seconds, so the first seed gets
    /// neither a focused element nor an observer — and with no observer no
    /// focus notification will ever correct it. Chromium also builds its tree
    /// asynchronously after AXManualAccessibility is set and doesn't announce
    /// the already-focused field once it's up. Either way only a re-read helps.
    private static let seedRetryDelays: [TimeInterval] =
        [0.25, 0.5, 1] + Array(repeating: 2, count: 12)

    /// True from scheduling a seed until its install lands, so the trigger-time
    /// backstop doesn't start a second retry chain alongside a live one.
    private var seedInFlight = false

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
            seedInFlight = false
            onFocusChange?()
            return
        }
        let pid = app.processIdentifier
        element = nil
        focusedPID = pid
        DebugRecorder.record(.focus, "app", ["bundleID": app.bundleIdentifier ?? "—"])
        onFocusChange?()

        seedInFlight = true
        let work = DispatchWorkItem { [weak self] in
            Self.seedQueue.async {
                self?.seed(pid: pid, generation: generation, attempt: 0, registerObserver: true)
            }
        }
        pendingSeed = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.seedDebounce, execute: work)
    }

    /// Backstop for a trigger that failed closed because the cache is empty:
    /// restarts the re-seed chain once the retries above have run out (an app
    /// whose AX came up late). Too late for the keystroke that called it, but
    /// the next trigger in the same field works. No IPC here — safe on the tap.
    /// Runs as a retry (attempt 1), so an empty read can't clobber an element
    /// the observer delivers meanwhile.
    func reseedIfEmpty() {
        guard element == nil, !seedInFlight, let pid = focusedPID else { return }
        let generation = refreshGeneration.withLock { $0 }
        let registerObserver = observer == nil
        seedInFlight = true
        Self.seedQueue.async {
            self.seed(pid: pid, generation: generation, attempt: 1, registerObserver: registerObserver)
        }
    }

    /// Runs on `seedQueue`. Both AX calls here block on the target app's
    /// reply, which is the whole reason they're off the main thread. A seed
    /// superseded by a newer activation bails before each round-trip — its
    /// result would be discarded anyway, and dead seeds draining serially
    /// would delay the live one.
    private nonisolated func seed(pid: pid_t, generation: Int, attempt: Int, registerObserver: Bool) {
        guard refreshGeneration.withLock({ $0 }) == generation else { return }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, Self.seedTimeout)

        // C function pointer — no captures allowed, route via refcon.
        let callback: AXObserverCallback = { _, focusedElement, _, refcon in
            guard let refcon else { return }
            let cache = Unmanaged<FocusedElementCache>.fromOpaque(refcon).takeUnretainedValue()
            // Source is on the main run loop (added in install()), so we're on main.
            MainActor.assumeIsolated {
                cache.element = focusedElement          // didSet clears field info → fail closed
                cache.onFocusChange?()
                cache.reclassify(focusedElement)        // recompute secure/editable off-thread
            }
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Register BEFORE reading the focused element. A move after the read
        // but before registration would be missed entirely — no callback, and
        // install() would publish the stale element as truth. Registered
        // first, a move during/after the read fires a notification that
        // queues on the observer's mach port and drains once install() adds
        // the source to the main run loop, correcting the cache.
        var newObserver: AXObserver?
        var addStatus: AXError?
        if registerObserver, AXObserverCreate(pid, callback, &newObserver) == .success, let obs = newObserver {
            // Re-check after create (local, but a bump can land any time):
            // the registration below is the blocking IPC worth skipping.
            guard refreshGeneration.withLock({ $0 }) == generation else { return }
            // Best-effort — fails for system apps / non-AX apps; the seeded
            // value still serves. Synchronous IPC, hence off-main.
            addStatus = AXObserverAddNotification(
                obs,
                axApp,
                kAXFocusedUIElementChangedNotification as CFString,
                refcon
            )
        }
        // An observer whose registration failed never fires; drop it so the
        // retry registers a fresh one.
        let observer = addStatus == .success ? newObserver : nil

        guard refreshGeneration.withLock({ $0 }) == generation else { return }
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

        // Chromium/Electron apps (Slack, VS Code, Discord…) gate their AX tree
        // behind AXManualAccessibility: until a client sets it the app exposes
        // no focused element, so every trigger fails closed as "unknown →
        // secure" (W-572). Only flip it when the read above came back empty —
        // native apps hand back a focused element and never reach here, so we
        // never touch them. Chromium builds the tree asynchronously, so an
        // empty seed is retried (see `seedRetryDelays`).
        if seeded == nil {
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        // Classify while we're already off the main thread and holding the app's
        // tight timeout, so `current()` (on the tap thread) reads it for free.
        var fieldInfo: (secure: Bool, editable: Bool, role: String?)?
        if let seeded {
            AXUIElementSetMessagingTimeout(seeded, Self.seedTimeout)
            fieldInfo = AppContextDetector.classify(seeded)
        }

        let diag = [
            "attempt": "\(attempt)",
            "copy": "\(status.rawValue)",
            "add": addStatus.map { "\($0.rawValue)" } ?? "-",
            "elem": "\(seeded != nil)",
        ]
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard generation == self.refreshGeneration.withLock({ $0 }) else { return }
                // Empty retries would flood the small focus ring; log the
                // first attempt and the one that lands.
                if attempt == 0 || seeded != nil {
                    DebugRecorder.record(.focus, "seed", diag)
                }
                self.install(
                    seeded: seeded, fieldInfo: fieldInfo,
                    observer: observer, pid: pid, attempt: attempt
                )
            }
        }
    }

    /// Publishes a finished seed, unless a newer activation made it stale.
    /// Deliberately does NOT fire `onFocusChange`: focus hasn't moved — this
    /// is the same focus the activation-time fire announced, just resolved.
    /// A synthetic fire here would cancel a capture the user started during
    /// the seed window (its snapshot is nil) and clear a fresh emoticon undo.
    private func install(
        seeded: AXUIElement?,
        fieldInfo: (secure: Bool, editable: Bool, role: String?)?,
        observer: AXObserver?,
        pid: pid_t,
        attempt: Int
    ) {
        seedInFlight = false
        // An empty retry must not clobber an element the observer delivered
        // in the meantime.
        if seeded != nil || attempt == 0 {
            element = seeded                              // didSet clears field info
            if let fieldInfo {                            // then publish this seed's classification
                publishFieldInfo(secure: fieldInfo.secure, editable: fieldInfo.editable, role: fieldInfo.role)
            }
        }
        if let observer, self.observer == nil {
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
            self.observer = observer
            self.observedPID = pid
        }
        if seeded != nil || attempt == 0 {
            onSeedInstalled?()
        }

        if element == nil, attempt < Self.seedRetryDelays.count {
            let generation = refreshGeneration.withLock { $0 }
            let registerObserver = self.observer == nil
            seedInFlight = true
            Self.seedQueue.asyncAfter(deadline: .now() + Self.seedRetryDelays[attempt]) {
                self.seed(pid: pid, generation: generation, attempt: attempt + 1, registerObserver: registerObserver)
            }
        }
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
