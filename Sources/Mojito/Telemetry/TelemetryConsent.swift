import AppKit

/// One-time consent notice for anonymous usage stats, shown *before any data
/// is sent* (the Homebrew model). New users reach this right after onboarding;
/// existing users at the next launch. No-op once seen. Viewing the Privacy
/// settings tab also satisfies the gate (same disclosure + toggle live there),
/// so a user who pokes around Settings first never gets the alert.
@MainActor
enum TelemetryConsent {
    static var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: PrefsKey.telemetryConsentSeen)
    }

    static func presentIfNeeded() {
        guard !hasBeenSeen else { return }
        // Defer so it doesn't slam the user the instant onboarding closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated { present() }
        }
    }

    private static func present() {
        guard !hasBeenSeen else { return }
        let name = AppInfo.displayName
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Help improve \(name)?")
        alert.informativeText = String(localized: """
            \(name) can share anonymous usage stats — popular emoji, which features get used, and your macOS version. Nothing you type is ever included.

            It's all public at mojito.wells.ee/stats, and you can turn it off anytime in Settings ▸ Privacy.
            """)
        alert.addButton(withTitle: String(localized: "Share anonymous stats"))
        alert.addButton(withTitle: String(localized: "Not now"))

        NSApp.activate(ignoringOtherApps: true)
        let shared = alert.runModal() == .alertFirstButtonReturn

        let defaults = UserDefaults.standard
        defaults.set(shared, forKey: PrefsKey.telemetryEnabled)
        defaults.set(true, forKey: PrefsKey.telemetryConsentSeen)
        if shared { TelemetryUploader.shared.uploadIfDue() }
    }
}
