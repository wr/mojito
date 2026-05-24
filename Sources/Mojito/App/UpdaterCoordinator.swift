import AppKit
import Combine
import os.log
import Sparkle

@MainActor
final class UpdaterCoordinator: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdaterCoordinator()

    /// True after a background update check failed. MenuBarController watches this
    /// to render a quiet warning triangle next to "Check for Updates…" — the
    /// standard user driver only surfaces errors for user-initiated checks, so
    /// silent automatic checks would otherwise fail invisibly.
    @Published private(set) var hasUpdateError = false

    private let log = OSLog(subsystem: "ee.wells.Mojito", category: "Updater")
    private let driver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
    private lazy var updater: SPUUpdater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: driver,
        delegate: self
    )

    func start() {
        #if DEBUG
        // Dev builds carry bundle ID `ee.wells.Mojito.dev` and a build number
        // that's typically behind the live appcast. Starting Sparkle here
        // would offer (and try to install) a release Mojito.app over the dev
        // build's path — which is both wrong and very confusing.
        os_log("updater disabled in Debug build", log: log, type: .info)
        return
        #else
        assertConfigured()
        do {
            try updater.start()
            // The "Automatic updates" toggle is single-knob: download follows check.
            // No opt-in by default — Sparkle's first-launch consent dialog asks
            // the user whether to enable automatic checks.
            updater.automaticallyDownloadsUpdates = updater.automaticallyChecksForUpdates
        } catch {
            os_log("updater failed to start: %{public}@", log: log, type: .error, "\(error)")
            hasUpdateError = true
        }
        #endif
    }

    /// In DEBUG builds, assert that `SUFeedURL` and `SUPublicEDKey` are present
    /// and non-empty in `Info.plist`. Without either, Sparkle silently does
    /// nothing (no auto-check) or accepts unsigned updates — both of which
    /// have bitten this project before. The release.sh script already guards
    /// against an empty pubkey at build time, but this catches accidental
    /// regressions during `xcodegen generate` cycles.
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
        updater.checkForUpdates()
    }

    /// Single-knob auto-update toggle bound to General settings. Writing flips
    /// both `automaticallyChecksForUpdates` and `automaticallyDownloadsUpdates`
    /// together — otherwise the two settings can drift (e.g. Sparkle's own
    /// "Automatically download and install updates" prompt overrides one but
    /// not the other) and the UI starts lying about what's actually happening.
    var automaticUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            updater.automaticallyChecksForUpdates = newValue
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        // Falls back to Info.plist SUFeedURL.
        nil
    }

    /// Fires on every aborted check — silent background polls included. We use
    /// this to surface a quiet menu-bar indicator without a modal alert, BUT
    /// only for true failures (network unreachable, malformed appcast, signing
    /// mismatch). Sparkle also routes benign "no update available" through this
    /// callback on some paths — those shouldn't paint a warning triangle.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        // Sparkle's SUErrorCode.noUpdateError = 1001. Filter it (and the
        // user-cancelled installation code) since they aren't real failures.
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
            // A successful find clears any stale error indicator.
            self.hasUpdateError = false
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.hasUpdateError = false
        }
    }
}
