import AppKit
import Foundation
import os.log

/// Enforces a single active Mojito instance across the dev + release bundle IDs.
///
/// Two scenarios this guards against:
///
/// 1. **Same-bundle-ID peer.** A second copy of the *same* build launches (e.g.
///    user double-clicks the .app while the menu-bar instance is already
///    running). Two CGEventTaps would race the keystrokes and two pickers
///    would fight to render. The newcomer quits silently — the existing
///    instance keeps running.
///
/// 2. **Cross-bundle peer (dev vs release).** Dev (`ee.wells.Mojito.dev`)
///    always wins. If a release `Mojito.app` is running when the dev build
///    launches, we terminate the release peer. If a dev build is already
///    running when the release launches, the release quits itself. This makes
///    iterating on the dev build painless — you don't have to manually quit
///    the menu-bar release app first.
///
/// Sparkle's relauncher transiently spawns a process sharing our bundle ID
/// during an update. We filter that out two ways: (a) skip our own PID, and
/// (b) only terminate peers whose process has been alive for at least
/// `peerMinLifetime`, so we can't accidentally kill the post-update relauncher
/// in its first instant.
@MainActor
final class SingleInstanceCoordinator {
    static let shared = SingleInstanceCoordinator()

    private static let releaseBundleID = "ee.wells.Mojito"
    private static let devBundleID = "ee.wells.Mojito.dev"
    /// Only terminate / yield to a peer that's been running this long. Filters
    /// out Sparkle's transient relauncher (which lives for well under a second).
    private static let peerMinLifetime: TimeInterval = 3.0

    private let log = OSLog(subsystem: "ee.wells.Mojito", category: "SingleInstance")
    private var launchObserver: NSObjectProtocol?
    /// True once we've decided to quit. Prevents `applicationDidFinishLaunching`
    /// from spinning up the engine / onboarding while we're on the way out.
    private(set) var willQuitDueToPeer: Bool = false

    private init() {}

    /// Run once during `applicationWillFinishLaunching`. May call
    /// `NSApp.terminate(nil)` synchronously if we should yield to an existing
    /// peer; otherwise schedules ongoing peer monitoring.
    func enforce() {
        let ourBundleID = Bundle.main.bundleIdentifier ?? ""
        let ourPID = ProcessInfo.processInfo.processIdentifier

        // Pass 1: same-bundle-ID peer → we lose, they win.
        let sameBundlePeers = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == ourBundleID
                && $0.processIdentifier != ourPID
                && Self.hasBeenAlive(for: Self.peerMinLifetime, app: $0)
        }
        if let existing = sameBundlePeers.first {
            os_log("Another instance of %{public}@ (pid=%d) is already running; quitting self", log: log, type: .info, ourBundleID, existing.processIdentifier)
            existing.activate(options: [])
            willQuitDueToPeer = true
            // Defer terminate so callers can early-return before doing setup work.
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        // Pass 2: cross-bundle peer (dev vs release).
        let peerBundleID = (ourBundleID == Self.devBundleID) ? Self.releaseBundleID : Self.devBundleID
        let crossPeers = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == peerBundleID
                && $0.processIdentifier != ourPID
                && Self.hasBeenAlive(for: Self.peerMinLifetime, app: $0)
        }

        if ourBundleID == Self.devBundleID {
            // Dev wins → terminate any release peer.
            for peer in crossPeers {
                os_log("Dev build active; terminating release peer (pid=%d)", log: log, type: .info, peer.processIdentifier)
                _ = peer.terminate()
            }
        } else if ourBundleID == Self.releaseBundleID {
            // Release loses → if a dev peer exists, quit ourselves.
            if let dev = crossPeers.first {
                os_log("Dev build is running (pid=%d); release build quitting self", log: log, type: .info, dev.processIdentifier)
                willQuitDueToPeer = true
                DispatchQueue.main.async { NSApp.terminate(nil) }
                return
            }
        }

        // Observe future launches so a later-launched peer is handled too.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            MainActor.assumeIsolated {
                self?.handleLaunch(notification: notif)
            }
        }
    }

    deinit {
        if let obs = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    private func handleLaunch(notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let peerBundle = app.bundleIdentifier else { return }
        let ourBundleID = Bundle.main.bundleIdentifier ?? ""
        let ourPID = ProcessInfo.processInfo.processIdentifier
        guard app.processIdentifier != ourPID else { return }

        if peerBundle == ourBundleID {
            // A duplicate of us just launched. We're the incumbent — kill the newcomer.
            // No lifetime check needed; it just launched and we're the one who's been
            // alive long enough to be the legitimate instance.
            os_log("Duplicate instance of %{public}@ launched (pid=%d); terminating newcomer", log: log, type: .info, ourBundleID, app.processIdentifier)
            _ = app.terminate()
            return
        }

        // Cross-bundle peer launched.
        if ourBundleID == Self.devBundleID && peerBundle == Self.releaseBundleID {
            // Dev wins; kill the release peer that just launched.
            os_log("Release peer launched while dev is active (pid=%d); terminating", log: log, type: .info, app.processIdentifier)
            _ = app.terminate()
        } else if ourBundleID == Self.releaseBundleID && peerBundle == Self.devBundleID {
            // Dev just launched; we (release) yield.
            os_log("Dev peer launched while release is active (pid=%d); release quitting self", log: log, type: .info, app.processIdentifier)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func hasBeenAlive(for interval: TimeInterval, app: NSRunningApplication) -> Bool {
        guard let launchDate = app.launchDate else {
            // Missing launchDate (sandbox restrictions, etc.) — assume yes;
            // the worst case is we terminate Sparkle's relauncher, which is
            // mitigated by the parallel PID-based filtering in the rest of
            // the flow (we never terminate our own PID).
            return true
        }
        return Date().timeIntervalSince(launchDate) >= interval
    }
}
