import AppKit
import Foundation
import os

/// Categories that surface in the debug report. Keep the set small —
/// bug categories tend to cluster, and a tight enum makes the report
/// easy to skim.
enum DebugCategory: String {
    case engine
    case picker
    case insert
    case emoticon
    case gif
    case keyMonitor
    case permissions
    case focus
}

struct DebugEvent {
    let timestamp: Date
    let category: DebugCategory
    let kind: String
    let metadata: [String: String]
}

/// In-memory, app-lifetime ring buffer. Never persisted. Backs the
/// "Activity log" section of `DebugReport`. Sites call `record(_:_:_:)`
/// at meaningful state transitions — picker open, insert, permission
/// flip, etc.
///
/// Anonymization is enforced on the way *in*: kind is clamped to 24
/// ASCII chars and each metadata value to 32. Callers can't accidentally
/// leak free-form text (queries, URLs, emoji content) into the buffer.
@MainActor
enum DebugRecorder {
    private static let capacity = 200
    /// Focus changes live in their own small ring so a burst of app
    /// switching can't evict the action events that actually explain a bug —
    /// app-switch churn easily dominates a flat buffer.
    private static let focusCapacity = 40
    private static let kindMaxLen = 24
    private static let valueMaxLen = 32
    private static var buffer: [DebugEvent] = []
    private static var focusBuffer: [DebugEvent] = []

    /// E2E introspection. The in-app report is UI-only, so when the app is
    /// launched with `MOJITO_E2E_LOG=1` every recorded event is also emitted to
    /// the unified log (subsystem `ee.wells.Mojito`, category `e2e`) where an
    /// external harness can read the activity stream headlessly — e.g. asserting
    /// zero `keyMonitor tapLost reason=timeout` while driving a browser
    /// (`scripts/e2e/`). Off by default: production never constructs the logger,
    /// so there's no cost or behavior change. Recorded values are already
    /// anonymized (ASCII-clamped, no user text), so logging them `%{public}` —
    /// required to read them back with `log show` — leaks nothing.
    private static let e2eLog: Logger? =
        ProcessInfo.processInfo.environment["MOJITO_E2E_LOG"] == "1"
            ? Logger(subsystem: "ee.wells.Mojito", category: "e2e")
            : nil

    static func record(
        _ category: DebugCategory,
        _ kind: String,
        _ metadata: [String: String] = [:]
    ) {
        var meta = metadata
        // Stamp which app was frontmost so every action line answers
        // "where did this happen" on its own — no cross-referencing the
        // focus.app lines. focus.app already names the app via `bundleID`,
        // so leave it (and any explicit `app`) untouched.
        if meta["app"] == nil, meta["bundleID"] == nil,
           let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            meta["app"] = front
        }
        let event = DebugEvent(
            timestamp: Date(),
            category: category,
            kind: clamp(kind, max: kindMaxLen),
            metadata: meta.mapValues { clamp($0, max: valueMaxLen) }
        )
        if category == .focus {
            focusBuffer.append(event)
            if focusBuffer.count > focusCapacity {
                focusBuffer.removeFirst(focusBuffer.count - focusCapacity)
            }
        } else {
            buffer.append(event)
            if buffer.count > capacity {
                buffer.removeFirst(buffer.count - capacity)
            }
        }

        if let e2eLog {
            let meta = event.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            // Machine-readable shape for the harness: "category kind k=v k=v".
            e2eLog.log("\(event.category.rawValue, privacy: .public) \(event.kind, privacy: .public) \(meta, privacy: .public)")
        }
    }

    /// Action events (everything but focus changes). Newest-last; callers
    /// (DebugReport) take the tail.
    static func snapshot() -> [DebugEvent] { buffer }

    /// Focus-change events, kept separate so they get a small fixed budget
    /// in the report instead of swamping the action history.
    static func focusSnapshot() -> [DebugEvent] { focusBuffer }

    static func reset() {
        buffer.removeAll()
        focusBuffer.removeAll()
    }

    /// Drops non-printable ASCII and caps length. Keeps the buffer free
    /// of multibyte payloads that could smuggle out user text.
    private static func clamp(_ s: String, max: Int) -> String {
        let filtered = s.unicodeScalars.lazy
            .filter { (0x20...0x7E).contains($0.value) }
            .prefix(max)
        return String(String.UnicodeScalarView(filtered))
    }
}
