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

    @Test func reportFitsUnderCap() {
        DebugRecorder.reset()
        for i in 0..<300 {
            DebugRecorder.record(.picker, "open", ["outcome": "axBounds", "iter": "\(i)"])
        }
        let out = DebugReport.markdown()
        #expect(out.utf8.count < DebugReport.maxSizeBytes, "report is \(out.utf8.count) bytes")
    }

    @Test func includesNewSections() {
        DebugRecorder.reset()
        let out = DebugReport.markdown()
        for section in ["## Mojito", "## Build", "## Prefs", "## System", "## Database", "## Updater", "## Last picker context", "## Activity log", "## Now"] {
            #expect(out.contains(section), "missing section \(section)")
        }
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

    @Test func prefsShowsEmoticonTotal() {
        DebugRecorder.reset()
        let out = DebugReport.markdown()
        #expect(out.contains("totals.emoticonInserted:"))
    }

    @Test func focusChurnDoesNotEvictActionEvents() {
        DebugRecorder.reset()
        // Action events recorded *before* a long burst of app-switching.
        // The old flat last-100 window dropped these; the split rings keep
        // them since focus changes can no longer crowd the action history.
        DebugRecorder.record(.emoticon, "convert", ["consumesTerminator": "true"])
        DebugRecorder.record(.insert, "replace", ["del": "3", "len": "1"])
        for i in 0..<100 {
            DebugRecorder.record(.focus, "app", ["bundleID": "com.example.app\(i % 3)"])
        }
        let out = DebugReport.markdown()
        #expect(out.contains("emoticon.convert"), "action events evicted by focus churn")
        #expect(out.contains("insert.replace"))
        // Focus lines are capped so they can't swamp the log.
        let focusLines = out.components(separatedBy: "focus.app").count - 1
        #expect(focusLines <= 15, "focus lines not capped: \(focusLines)")
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
