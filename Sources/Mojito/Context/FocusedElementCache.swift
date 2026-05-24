import AppKit
import ApplicationServices

/// Caches the AX-focused UI element for the currently-active app and
/// keeps it up to date via `AXObserver` (`kAXFocusedUIElementChangedNotification`).
///
/// The cache exists because `AXUIElementCopyAttributeValue(system, kAXFocusedUIElement)`
/// is a synchronous cross-process IPC call that can stall hundreds of
/// milliseconds when the focused app is busy (Electron under load, hung apps).
/// Doing that call on every `:` trigger and every picker show — both of which
/// are user-perceptible — produced visible lag. The observer-driven cache
/// converts those reads into a thread-local pointer read.
///
/// Falls back gracefully: if observer creation fails (e.g. AX permission not
/// yet granted, or the active app isn't AX-introspectable), `element` returns
/// nil and callers should fetch fresh.
@MainActor
final class FocusedElementCache {
    static let shared = FocusedElementCache()

    /// Last known focused element. Nil during transitions or when AX is unusable.
    private(set) var element: AXUIElement?

    /// PID of the app whose focused element we last observed. Used by the
    /// Engine to detect cross-app focus changes (e.g. user types `:` in Notes,
    /// then ⌘-Tabs to Spotlight before the deferred picker show fires).
    private(set) var focusedPID: pid_t?

    /// Invoked on every focus change (including cross-app activations). The
    /// Engine subscribes to cancel in-flight captures when focus shifts.
    /// Called on the main actor.
    var onFocusChange: (() -> Void)?

    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var workspaceObserver: NSObjectProtocol?

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
        // No teardownObserver() — AXObserver retains the run loop source until
        // released; dropping our reference is sufficient and we're a singleton
        // that lives for the lifetime of the app.
    }

    private func refreshActiveApp() {
        teardownObserver()

        guard let app = NSWorkspace.shared.frontmostApplication else {
            element = nil
            focusedPID = nil
            onFocusChange?()
            return
        }
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        // Seed the cache with the currently focused element so the first call
        // after an app switch isn't a miss.
        var ref: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &ref
        )
        element = status == .success ? (ref as! AXUIElement) : nil
        focusedPID = pid
        onFocusChange?()

        // C function pointer — Swift requires no captures, so we route via
        // refcon back to the singleton.
        let callback: AXObserverCallback = { _, focusedElement, _, refcon in
            guard let refcon else { return }
            let cache = Unmanaged<FocusedElementCache>.fromOpaque(refcon).takeUnretainedValue()
            // AXObserverGetRunLoopSource was attached to the main run loop in
            // refreshActiveApp(), so we're already on main here.
            MainActor.assumeIsolated {
                cache.element = focusedElement
                cache.onFocusChange?()
            }
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, callback, &newObserver) == .success, let obs = newObserver else {
            return
        }
        // Best-effort — observer add can fail for system apps or apps that
        // don't expose AX. Either way the cache still has the seeded value.
        AXObserverAddNotification(
            obs,
            axApp,
            kAXFocusedUIElementChangedNotification as CFString,
            refcon
        )
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(obs),
            .commonModes
        )
        self.observer = obs
        self.observedPID = pid
    }

    private func teardownObserver() {
        if let obs = observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(obs),
                .commonModes
            )
        }
        observer = nil
        observedPID = nil
    }
}
