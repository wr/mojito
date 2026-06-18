import Foundation

/// The four fixed trigger modes. Users can't add modes — only retune the
/// strings that fire each one.
enum TriggerMode: String, CaseIterable, Codable, Equatable {
    case emoji          // `:query:` → emoji picker / exact match
    case symbols        // `::query::` → experimental symbol corpus
    case gif            // `:::query` → Giphy picker
    case quickAccess    // `:?` → favorites pill (open derived from emoji)
}

/// One mode's open string. The close string for the bracketing modes
/// (`.emoji` / `.symbols`) is mirrored from the open — there's no separate
/// close field — and `.gif` / `.quickAccess` open a sticky UI with no close.
struct Trigger: Equatable, Codable {
    let mode: TriggerMode
    var open: String
    var enabled: Bool
}

/// The active trigger set. `default` reproduces Mojito's historical hardcoded
/// triggers, so an untouched install behaves identically.
struct TriggerConfig: Equatable, Codable {
    var emoji: Trigger
    var symbols: Trigger
    var gif: Trigger
    var quickAccess: Trigger

    static let `default` = TriggerConfig(
        emoji:       Trigger(mode: .emoji,       open: ":",   enabled: true),
        symbols:     Trigger(mode: .symbols,     open: "::",  enabled: false),
        gif:         Trigger(mode: .gif,         open: ":::", enabled: true),
        quickAccess: Trigger(mode: .quickAccess, open: ":?",  enabled: true)
    )

    /// All four, in the canonical precedence order used to break open-string
    /// ties (emoji → symbols → gif → quickAccess), matching legacy behavior.
    var all: [Trigger] { [emoji, symbols, gif, quickAccess] }

    /// Triggers that can actually fire — enabled with a non-empty open string.
    var active: [Trigger] { all.filter { $0.enabled && !$0.open.isEmpty } }

    func trigger(for mode: TriggerMode) -> Trigger {
        switch mode {
        case .emoji:       return emoji
        case .symbols:     return symbols
        case .gif:         return gif
        case .quickAccess: return quickAccess
        }
    }

    mutating func set(_ trigger: Trigger) {
        switch trigger.mode {
        case .emoji:       emoji = trigger
        case .symbols:     symbols = trigger
        case .gif:         gif = trigger
        case .quickAccess: quickAccess = trigger
        }
    }

    /// Quick Access isn't independently editable — its open follows the emoji
    /// trigger (`:` → `:?`, `::` → `::?`). Call after any edit, and on load /
    /// before save, so the persisted config and live state machine stay
    /// consistent: the `?` stays the last char of the open, which is what the
    /// state machine's pill / escape-restore handling keys off.
    mutating func normalize() {
        quickAccess.open = emoji.open + "?"
    }
}
