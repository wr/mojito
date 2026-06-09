import AppKit
import SwiftUI
import WebKit

/// TROGDOR! WKWebView window on homestarrunner.com/trogdor, zoomed so the
/// flash-era game frame fits. Real close button + Esc dismisses.
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
        // Defer ~180ms so synthetic backspaces from the trigger deletion land
        // in the user's text field BEFORE we steal focus — otherwise they
        // arrive at the WKWebView and AppKit plays the system "donk" beep.
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
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.center()
        w.level = .floating

        let config = WKWebViewConfiguration()
        // Block media autoplay — the page's SWF/audio fires the system
        // alert beep before any user interaction.
        config.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.pageZoom = 0.8
        // Some WebKit versions only expose `magnification` via KVC.
        webView.setValue(0.8, forKey: "magnification")

        if let url = URL(string: "https://homestarrunner.com/trogdor") {
            webView.load(URLRequest(url: url))
        }

        w.contentView = webView
        window = w
        DockIconManager.windowDidOpen()
        // Also drops the web view at close, so page media stops now.
        ParticlePanel.tearDownOnClose(w)

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
