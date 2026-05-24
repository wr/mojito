import AppKit
import Foundation
import os.log

/// Single active Mojito across both bundle IDs:
/// - same-bundle peer → newcomer quits, incumbent wins
/// - cross-bundle peer → dev always wins
///
/// `peerMinLifetime` filters Sparkle's transient relauncher, which briefly
/// shares our bundle ID during an update.
@MainActor
final class SingleInstanceCoordinator {
    static let shared = SingleInstanceCoordinator()

    private static let releaseBundleID = "ee.wells.Mojito"
    private static let devBundleID = "ee.wells.Mojito.dev"
    /// Sparkle's relauncher lives well under a second.
    private static let peerMinLifetime: TimeInterval = 3.0

    private let log = OSLog(subsystem: "ee.wells.Mojito", category: "SingleInstance")
    private var launchObserver: NSObjectProtocol?
    /// AppDelegate checks this in `applicationDidFinishLaunching` and skips
    /// engine/onboarding setup if we're on the way out.
    private(set) var willQuitDueToPeer: Bool = false

    private init() {}

    /// Called from `applicationWillFinishLaunching`. May terminate
    /// synchronously if we yield to a peer; otherwise installs monitoring.
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
            // Defer so callers can early-return before doing setup work.
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
            // Duplicate of us just launched — we're the incumbent, kill it.
            // No lifetime check; we're already past peerMinLifetime ourselves.
            os_log("Duplicate instance of %{public}@ launched (pid=%d); terminating newcomer", log: log, type: .info, ourBundleID, app.processIdentifier)
            _ = app.terminate()
            return
        }

        if ourBundleID == Self.devBundleID && peerBundle == Self.releaseBundleID {
            os_log("Release peer launched while dev is active (pid=%d); terminating", log: log, type: .info, app.processIdentifier)
            _ = app.terminate()
        } else if ourBundleID == Self.releaseBundleID && peerBundle == Self.devBundleID {
            os_log("Dev peer launched while release is active (pid=%d); release quitting self", log: log, type: .info, app.processIdentifier)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func hasBeenAlive(for interval: TimeInterval, app: NSRunningApplication) -> Bool {
        guard let launchDate = app.launchDate else {
            // Missing launchDate (sandbox) — assume yes. Worst case is
            // killing Sparkle's relauncher, which is also mitigated by
            // the PID-based filtering elsewhere.
            return true
        }
        return Date().timeIntervalSince(launchDate) >= interval
    }
}
