import AppKit
import SwiftUI
import WebKit

/// One of the discoverable effects. See `EasterEgg` for the
/// (opaque) identity; the trigger keyword is decoded at runtime from
/// `EggStrings` and not present in source.
@MainActor
enum Trogdor {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?
    private static var cancelToken: (() -> Void)?

    static func start() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Defer ~180ms so the synthetic backspaces firing from
        // the keyword finish landing in the user's text field BEFORE we
        // steal focus via `NSApp.activate`. Without this delay the
        // pending backspaces race the focus switch, get delivered to
        // the WKWebView which doesn't know what to do with them, and
        // AppKit plays the system "donk" alert beep.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            MainActor.assumeIsolated { openWindow() }
        }
    }

    private static func openWindow() {
        let size = NSSize(width: 960, height: 720)
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "TROGDOR!"
        // Reverted to a regular top bar — invisible-titlebar trial broke
        // window dragging (no chrome to grab) and triggered a system
        // alert beep on first open.
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.center()
        w.level = .floating

        let config = WKWebViewConfiguration()
        // Block media autoplay — the page's embedded SWF/audio was
        // triggering the system alert beep when the WKWebView tried to
        // start audio before the user interacted with it.
        config.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        webView.autoresizingMask = [.width, .height]
        // pageZoom is the SwiftUI-friendly way to scale the page contents.
        // 0.6 leaves room for the surrounding chrome.
        webView.pageZoom = 0.8
        // Some WebKit versions expose `magnification` only via KVC — set
        // both so we cover the base. Failures here are harmless.
        webView.setValue(0.8, forKey: "magnification")

        if let url = URL(string: "https://homestarrunner.com/trogdor") {
            webView.load(URLRequest(url: url))
        }

        w.contentView = webView
        window = w
        DockIconManager.windowDidOpen()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if let obs = closeObserver {
                    NotificationCenter.default.removeObserver(obs)
                    closeObserver = nil
                }
                cancelToken?(); cancelToken = nil
                window = nil
                DockIconManager.windowDidClose()
            }
        }

        cancelToken = EffectDismisser.register {
            MainActor.assumeIsolated {
                window?.close()
            }
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
