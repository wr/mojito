import Foundation
import ServiceManagement

/// Single source of truth for the SMAppService toggle. Used by both the
/// General settings pane and the onboarding screen so they can't drift apart.
enum LaunchAtLogin {
    static func apply(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Mojito: launch-at-login toggle failed: \(error)")
        }
    }

    /// Current state of the system login-item registration.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Mirrors the system state into the UserDefaults-backed `@AppStorage` key
    /// so toggles stay accurate when the user removes Mojito from System
    /// Settings → Login Items behind our back.
    static func syncFromSystem() {
        let current = isEnabled
        if UserDefaults.standard.bool(forKey: PrefsKey.launchAtLogin) != current {
            UserDefaults.standard.set(current, forKey: PrefsKey.launchAtLogin)
        }
    }
}
