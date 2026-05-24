import AppKit

// When xcodebuild launches Mojito Dev as the test host, skip the
// menubar/event-tap startup — single-instance enforcement would kill the
// test runner if a real Mojito Dev is already running, and the test
// bundle doesn't need the app's behavior. Test bundle loads after the
// runloop is up; just bring NSApp online and idle.
let isUnderXCTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
if isUnderXCTest {
    _ = NSApplication.shared
    NSApp.run()
    exit(0)
}

#if DEBUG
// Dev bundle ID scopes UserDefaults separately from the released app, so
// a fresh dev launch would have no usage counts, exclusions, or
// onboarding-complete flag. Layer the release app's defaults underneath
// as a read-only fallback; dev writes shadow them per-key.
if Bundle.main.bundleIdentifier == "ee.wells.Mojito.dev",
   let releaseDefaults = UserDefaults.standard.persistentDomain(forName: "ee.wells.Mojito") {
    UserDefaults.standard.register(defaults: releaseDefaults)
}
#endif

let app = NSApplication.shared

// Enforce before AppDelegate. NSApp.terminate posts asynchronously, so
// `applicationDidFinishLaunching` still runs — the delegate checks
// `willQuitDueToPeer` and short-circuits.
MainActor.assumeIsolated {
    SingleInstanceCoordinator.shared.enforce()
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
