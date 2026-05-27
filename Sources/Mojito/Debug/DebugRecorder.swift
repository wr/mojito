import Foundation

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
    private static let kindMaxLen = 24
    private static let valueMaxLen = 32
    private static var buffer: [DebugEvent] = []

    static func record(
        _ category: DebugCategory,
        _ kind: String,
        _ metadata: [String: String] = [:]
    ) {
        let event = DebugEvent(
            timestamp: Date(),
            category: category,
            kind: clamp(kind, max: kindMaxLen),
            metadata: metadata.mapValues { clamp($0, max: valueMaxLen) }
        )
        buffer.append(event)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }

    /// Newest-last; callers (DebugReport) take the tail.
    static func snapshot() -> [DebugEvent] { buffer }

    static func reset() { buffer.removeAll() }

    /// Drops non-printable ASCII and caps length. Keeps the buffer free
    /// of multibyte payloads that could smuggle out user text.
    private static func clamp(_ s: String, max: Int) -> String {
        let filtered = s.unicodeScalars.lazy
            .filter { (0x20...0x7E).contains($0.value) }
            .prefix(max)
        return String(String.UnicodeScalarView(filtered))
    }
}
