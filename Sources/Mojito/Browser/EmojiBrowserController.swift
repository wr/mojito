import AppKit
import SwiftUI

/// Owns the emoji-browser window and the round-trip of returning focus to the
/// app the user was typing in, then synthesizing the chosen emoji there.
///
/// Unlike the inline `PickerWindow` (a non-activating panel that never steals
/// focus), the browser is a real key window so its search field and grid work
/// the ordinary way. That means we *do* steal focus — so we capture the app to
/// return to before showing, and reactivate it on pick/close.
@MainActor
final class EmojiBrowserController: NSObject, NSWindowDelegate {
    static let shared = EmojiBrowserController()

    private var window: NSWindow?
    private var viewModel: EmojiBrowserViewModel?

    /// App to refocus when the window closes. Captured before we steal focus.
    private var targetApp: NSRunningApplication?
    /// `:query` chars to erase before typing the pick — set when opened from
    /// the inline picker, 0 from the menu bar. Applied only on a real pick.
    private var pendingDelete = 0
    /// Emoji text to type once focus returns; nil on a plain close (Esc /
    /// close button) so cancelling never mutates the user's document.
    private var pendingInsert: String?

    private override init() { super.init() }

    /// - Parameters:
    ///   - deleteCount: chars of typed `:query` to remove before inserting.
    ///   - targetPID: the app to insert into. Falls back to the frontmost app.
    func show(deleteCount: Int, targetPID: pid_t?) {
        let resolved = targetPID.flatMap { NSRunningApplication(processIdentifier: $0) }
            ?? NSWorkspace.shared.frontmostApplication
        // Never target ourselves (e.g. reopened from the menu while our own
        // window was front) — keep the last real target if so.
        if let resolved, resolved.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = resolved
        }
        pendingDelete = deleteCount

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let vm = EmojiBrowserViewModel(database: .shared, favorites: .shared)
        viewModel = vm
        let root = EmojiBrowserView(
            viewModel: vm,
            onPick: { [weak self] emoji in self?.pick(emoji) },
            onDismiss: { [weak self] in self?.close() }
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Emoji")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 460))
        window.minSize = NSSize(width: 380, height: 320)
        window.center()
        window.delegate = self

        self.window = window
        DockIconManager.windowDidOpen()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    private func pick(_ emoji: Emoji) {
        pendingInsert = emoji.supportsSkinTone
            ? SkinTone.current.apply(to: emoji.character)
            : emoji.character
        close()  // windowWillClose does the focus return + typing
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        DockIconManager.windowDidClose()

        let target = targetApp
        let text = pendingInsert
        let delete = pendingDelete
        pendingInsert = nil
        pendingDelete = 0
        window = nil
        viewModel = nil
        targetApp = nil

        // Hand focus back to where the user was typing.
        target?.activate()

        guard let text else { return }
        // Wait for the target to come forward + restore first responder
        // before posting the synthetic keystrokes, or they land nowhere.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            MainActor.assumeIsolated {
                TextInserter.replace(charactersToDelete: delete, with: text)
                DebugRecorder.record(.insert, "browser", ["del": "\(delete)", "len": "\(text.count)"])
            }
        }
    }
}
