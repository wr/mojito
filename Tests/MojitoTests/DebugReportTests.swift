import Testing
@testable import Mojito
import Foundation

/// Anonymization + shape invariants for the About → Copy Debug Info
/// output. The tests stay loud about what the report MUST NOT contain so
/// future additions can't silently leak.
@MainActor
struct DebugReportTests {
    @Test func forbiddenStringsNeverAppear() {
        DebugRecorder.reset()
        // Drive the recorder through one of every category so the
        // generated report exercises real code paths.
        DebugRecorder.record(.picker, "open", ["outcome": "axBounds", "resultCount": "12"])
        DebugRecorder.record(.insert, "fromPicker", ["scope": "normal"])
        DebugRecorder.record(.emoticon, "convert", ["consumesTerminator": "true"])
        DebugRecorder.record(.gif, "open", ["outcome": "elementTopLeft"])
        DebugRecorder.record(.keyMonitor, "tapStart")
        DebugRecorder.record(.permissions, "axGranted")
        DebugRecorder.record(.focus, "app", ["bundleID": "com.apple.TextEdit"])
        DebugRecorder.record(.engine, "pause")

        let out = DebugReport.markdown()

        // Sensitive raw pref keys never appear (we surface counts only).
        for forbidden in [
            PrefsKey.usageCounts,
            PrefsKey.excludedBundleIDs,
            PrefsKey.excludedURLPatterns,
            PrefsKey.giphyApiKey,
            PrefsKey.easterEggsDiscovered,
        ] {
            #expect(!out.contains(forbidden), "report leaks \(forbidden)")
        }
        // Path / network / email-like surface.
        for substring in ["/Users/", "http://", "https://", "@"] {
            #expect(!out.contains(substring), "report leaks substring '\(substring)'")
        }
    }

    @Test func reportFitsUnderEightKB() {
        DebugRecorder.reset()
        // Fill the recorder past the surfacing window (50 events) — the
        // report should still stay capped.
        for i in 0..<200 {
            DebugRecorder.record(.picker, "open", ["outcome": "axBounds", "iter": "\(i)"])
        }
        let out = DebugReport.markdown()
        #expect(out.utf8.count < DebugReport.maxSizeBytes, "report is \(out.utf8.count) bytes")
    }

    @Test func noAbsoluteDatesInPrefsSection() {
        DebugRecorder.reset()
        let out = DebugReport.markdown()
        // Isolate the prefs section.
        let prefsRange = out.range(of: "## Prefs")
        let nextSection = out.range(of: "## System")
        #expect(prefsRange != nil)
        #expect(nextSection != nil)
        guard let start = prefsRange?.upperBound, let end = nextSection?.lowerBound else { return }
        let prefs = String(out[start..<end])
        // YYYY-MM-DD anywhere in the prefs block fails.
        let regex = try! NSRegularExpression(pattern: #"\d{4}-\d{2}-\d{2}"#)
        let range = NSRange(prefs.startIndex..., in: prefs)
        #expect(regex.firstMatch(in: prefs, range: range) == nil, "prefs leaks an absolute date")
    }

    @Test func activityLogClampsLongMetadataValues() {
        DebugRecorder.reset()
        let huge = String(repeating: "X", count: 1024)
        DebugRecorder.record(.picker, "open", ["leak": huge])
        let out = DebugReport.markdown()
        // The recorder clamps to 32 chars on input; the report includes
        // metadata verbatim from there. Assert no run of >32 Xs survives.
        let bigRun = String(repeating: "X", count: 33)
        #expect(!out.contains(bigRun))
    }
}
