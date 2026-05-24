import AppKit
import ApplicationServices

/// AX-focused element cache. `AXUIElementCopyAttributeValue(system, …)`
/// is a synchronous cross-process IPC that can stall hundreds of ms on
/// hung / busy apps (Electron under load). Doing that on every `:` and
/// picker show produced visible lag; this converts to a pointer read.
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
        // No teardownObserver() — we're an app-lifetime singleton and
        // dropping our AXObserver reference releases the run loop source.
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

        // Seed so the first call after an app switch isn't a miss.
        var ref: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &ref
        )
        element = status == .success ? (ref as! AXUIElement) : nil
        focusedPID = pid
        onFocusChange?()

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

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, callback, &newObserver) == .success, let obs = newObserver else {
            return
        }
        // Best-effort — fails for system apps / non-AX apps; the seeded
        // value still serves.
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
