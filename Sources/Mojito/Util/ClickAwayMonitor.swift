import AppKit

/// Dismiss-on-click-away for the floating picker panels: a local monitor
/// (clicks inside our own app, ignoring the panel itself) plus a global
/// monitor (clicks in any other app). Neither consumes the click.
@MainActor
final class ClickAwayMonitor {
    private var local: Any?
    private var global: Any?

    /// Installs both monitors. No-op when already installed.
    func install(ignoring panel: NSWindow, onClickAway: @escaping () -> Void) {
        guard local == nil else { return }
        let types: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        local = NSEvent.addLocalMonitorForEvents(matching: types) { [weak panel] event in
            if event.window !== panel {
                onClickAway()
            }
            return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: types) { _ in
            onClickAway()
        }
    }

    func remove() {
        if let m = local { NSEvent.removeMonitor(m) }
        if let m = global { NSEvent.removeMonitor(m) }
        local = nil
        global = nil
    }
}
