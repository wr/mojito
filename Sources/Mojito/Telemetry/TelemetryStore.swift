import Foundation

/// Accumulates the anonymous daily-aggregate deltas that `TelemetryUploader`
/// batches once a day. Every counter here stays local until an upload
/// succeeds, at which point `clearPending()` resets it.
///
/// These are plain statics that touch `UserDefaults` (thread-safe), so they're
/// safe to call straight from the keystroke/insert path. Nothing recorded here
/// is an identifier, a timestamp, or free text — just counts. The recording
/// calls short-circuit when telemetry is disabled, so a user who opted out
/// never even builds a local pending set.
enum TelemetryStore {
    private static var defaults: UserDefaults { .standard }

    /// Per-emoji daily counts are capped so one prolific user (or a stuck key)
    /// can't skew the public ranking. Anti-skew, not an identification control.
    static let perEmojiDailyCap = 100

    /// Mirrors the uploader's gate: opt-out, default on.
    static var isEnabled: Bool {
        (defaults.object(forKey: PrefsKey.telemetryEnabled) as? Bool) ?? true
    }

    // MARK: - Recording (called from the insert path)

    static func recordEmoji(hexcode: String) {
        guard isEnabled else { return }
        var map = (defaults.dictionary(forKey: PrefsKey.telemetryPendingEmoji) as? [String: Int]) ?? [:]
        let current = map[hexcode] ?? 0
        if current < perEmojiDailyCap { map[hexcode] = current + 1 }
        defaults.set(map, forKey: PrefsKey.telemetryPendingEmoji)
        bump(PrefsKey.telemetryPendingEmojiTotal)
    }

    static func recordSymbol()   { guard isEnabled else { return }; bump(PrefsKey.telemetryPendingSymbol) }
    static func recordGif()      { guard isEnabled else { return }; bump(PrefsKey.telemetryPendingGif) }
    static func recordEmoticon() { guard isEnabled else { return }; bump(PrefsKey.telemetryPendingEmoticon) }
    static func recordEggDiscovery() { guard isEnabled else { return }; bump(PrefsKey.telemetryPendingEggs) }

    private static func bump(_ key: String) {
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    // MARK: - Draining (called by the uploader)

    struct Pending {
        var emoji: [String: Int]
        var emojiTotal: Int
        var symbol: Int
        var gif: Int
        var emoticon: Int
        var eggs: Int
    }

    static func snapshotPending() -> Pending {
        Pending(
            emoji: (defaults.dictionary(forKey: PrefsKey.telemetryPendingEmoji) as? [String: Int]) ?? [:],
            emojiTotal: defaults.integer(forKey: PrefsKey.telemetryPendingEmojiTotal),
            symbol: defaults.integer(forKey: PrefsKey.telemetryPendingSymbol),
            gif: defaults.integer(forKey: PrefsKey.telemetryPendingGif),
            emoticon: defaults.integer(forKey: PrefsKey.telemetryPendingEmoticon),
            eggs: defaults.integer(forKey: PrefsKey.telemetryPendingEggs)
        )
    }

    /// Resets the deltas after a successful upload. Writes zeros/empties
    /// (rather than `removeObject`) so the dev build's release-domain
    /// fallback can't resurrect a stale pending set.
    static func clearPending() {
        defaults.set([String: Int](), forKey: PrefsKey.telemetryPendingEmoji)
        defaults.set(0, forKey: PrefsKey.telemetryPendingEmojiTotal)
        defaults.set(0, forKey: PrefsKey.telemetryPendingSymbol)
        defaults.set(0, forKey: PrefsKey.telemetryPendingGif)
        defaults.set(0, forKey: PrefsKey.telemetryPendingEmoticon)
        defaults.set(0, forKey: PrefsKey.telemetryPendingEggs)
    }
}
