import AppKit

#if DEBUG
// Dev builds run with bundle ID `ee.wells.Mojito.dev` so macOS TCC tracks
// Accessibility / Input Monitoring grants independently from the released
// app. The downside is `UserDefaults.standard` is also scoped per-bundle —
// so a fresh dev launch would otherwise have no top-emoji counts, no
// exclusions, no onboarding-complete flag, etc.
//
// Inherit the release app's defaults as a fallback layer via
// `register(defaults:)`. Reads fall through to release for any key the dev
// build hasn't written yet; writes from the dev build land in
// `~/Library/Preferences/ee.wells.Mojito.dev.plist` and start shadowing the
// release values from that key forward. The release app's store is never
// mutated by the dev build.
if Bundle.main.bundleIdentifier == "ee.wells.Mojito.dev",
   let releaseDefaults = UserDefaults.standard.persistentDomain(forName: "ee.wells.Mojito") {
    UserDefaults.standard.register(defaults: releaseDefaults)
}
#endif

let app = NSApplication.shared

// Enforce single-instance *before* creating AppDelegate. If a peer is already
// running and we should yield to it, AppDelegate runs `applicationDidFinishLaunching`
// anyway (NSApp.terminate posts asynchronously); the delegate checks the
// coordinator's `willQuitDueToPeer` flag and short-circuits.
MainActor.assumeIsolated {
    SingleInstanceCoordinator.shared.enforce()
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
