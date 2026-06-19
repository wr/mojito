import AppKit
import Combine
import os.log
import Sparkle

@MainActor
final class UpdaterCoordinator: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = UpdaterCoordinator()

    /// Sparkle's standard driver only shows errors for user-initiated checks.
    /// MenuBarController watches this so silent background failures get a
    /// quiet warning triangle instead of failing invisibly.
    @Published private(set) var hasUpdateError = false

    /// True from when Sparkle finds a valid update until it installs (the app
    /// relaunches) or a later check finds nothing. Drives a gentle menu-bar
    /// "update available" badge + row *alongside* Sparkle's own popup, so a
    /// deferred update still lingers as a reminder instead of vanishing.
    @Published private(set) var hasUpdateAvailable = false

    private let log = OSLog(subsystem: "ee.wells.Mojito", category: "Updater")
    private lazy var driver = SPUStandardUserDriver(hostBundle: .main, delegate: self)
    private lazy var updater: SPUUpdater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: driver,
        delegate: self
    )

    func start() {
        #if DEBUG
        // Dev bundle ID + behind-appcast build number — Sparkle would try to
        // install the release app over the dev path.
        os_log("updater disabled in Debug build", log: log, type: .info)
        return
        #else
        assertConfigured()
        do {
            try updater.start()
            // Single-knob auto-update: download follows check.
            updater.automaticallyDownloadsUpdates = updater.automaticallyChecksForUpdates
        } catch {
            os_log("updater failed to start: %{public}@", log: log, type: .error, "\(error)")
            hasUpdateError = true
        }
        #endif
    }

    /// Without `SUFeedURL`/`SUPublicEDKey`, Sparkle silently does nothing or
    /// accepts unsigned updates. release.sh guards pubkey at build time;
    /// this catches regressions during `xcodegen generate` cycles.
    private func assertConfigured() {
        #if DEBUG
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String) ?? ""
        let pubkey = (info["SUPublicEDKey"] as? String) ?? ""
        assert(!feed.isEmpty,
               "SUFeedURL missing from Info.plist — Sparkle won't check for updates.")
        assert(!pubkey.isEmpty,
               "SUPublicEDKey missing from Info.plist — Sparkle update signature verification is disabled.")
        #endif
    }

    func checkForUpdates() {
        hasUpdateError = false
        EasterEggTracker.record(.k52)
        updater.checkForUpdates()
    }

    /// Bound to General settings. Writes both flags together — otherwise
    /// Sparkle's own consent prompt can overwrite one but not the other,
    /// and the UI lies about what's actually happening.
    var automaticUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            updater.automaticallyChecksForUpdates = newValue
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        // nil → Sparkle falls back to Info.plist SUFeedURL.
        nil
    }

    /// Fires on every aborted check, including silent background polls.
    /// Sparkle routes benign "no update available" through here on some
    /// paths; filter those so they don't paint a warning triangle.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        let benign: Set<Int> = [
            1001,  // SUNoUpdateError
            4002,  // SUInstallationCanceledError
        ]
        if nsError.domain == "SUSparkleErrorDomain", benign.contains(nsError.code) {
            Task { @MainActor in
                self.hasUpdateError = false
                os_log("update check finished: %{public}@", log: self.log, type: .info, "\(error)")
            }
            return
        }
        Task { @MainActor in
            self.hasUpdateError = true
            os_log("update check failed: %{public}@", log: self.log, type: .info, "\(error)")
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.hasUpdateError = false
            self.hasUpdateAvailable = true
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.hasUpdateError = false
            self.hasUpdateAvailable = false
        }
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Getting Sparkle's window in front is harder than it looks for a menu-bar
    /// (`.accessory`) app. Once the appcast round-trip finishes, the app no
    /// longer owns the active event, so macOS denies activation — `NSApp
    /// .activate` is a no-op (Sparkle calls it too, with the same result), and
    /// the window lands behind whatever's frontmost. So instead of fighting
    /// activation, we float the window above other apps by raising its window
    /// *level* (the same trick the picker panel uses); that doesn't depend on
    /// activation at all. Promotion to `.regular` is kept as well so the app
    /// gets a dock icon / ⌘-Tab entry while the update UI is up, ref-counted
    /// through `DockIconManager` so it composes with an open settings window.
    private var didPromoteForUpdateUI = false

    private func promoteForUpdateUI() {
        if !didPromoteForUpdateUI {
            didPromoteForUpdateUI = true
            DockIconManager.windowDidOpen()
        }
        NSApp.activate(ignoringOtherApps: true)
        // The window doesn't exist yet when these hooks fire, and the no-update
        // / error path then blocks the main thread in `runModal` — so schedule
        // the raise across default + modal run-loop modes, on a short retry
        // ladder to beat the show / runModal race.
        for delay in [0.0, 0.1, 0.25] {
            perform(#selector(raiseUpdaterWindow), with: nil, afterDelay: delay,
                    inModes: [.default, .modalPanel, .common])
        }
    }

    private func demoteAfterUpdateUI() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(raiseUpdaterWindow), object: nil)
        guard didPromoteForUpdateUI else { return }
        didPromoteForUpdateUI = false
        DockIconManager.windowDidClose()
    }

    /// Float whichever window Sparkle just presented above other applications.
    /// `modalWindow` covers the no-update / error `NSAlert`; the update-found
    /// window is matched by the `SUUpdateAlert` identifier set in Sparkle's nib.
    @objc private func raiseUpdaterWindow() {
        let window = NSApp.modalWindow
            ?? NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "SUUpdateAlert" }
        guard let window else { return }
        if window.level.rawValue < NSWindow.Level.floating.rawValue {
            window.level = .floating
        }
        window.orderFrontRegardless()
    }

    // These fire on the main thread (they bracket AppKit presentation).
    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated { promoteForUpdateUI() }
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated { promoteForUpdateUI() }
    }

    nonisolated func standardUserDriverDidShowModalAlert() {
        MainActor.assumeIsolated { demoteAfterUpdateUI() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { demoteAfterUpdateUI() }
    }
}
