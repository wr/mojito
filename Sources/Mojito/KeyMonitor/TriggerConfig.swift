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
    /// When symbols is enabled and this is true, symbols aren't a separate
    /// trigger — they blend into the emoji results (the emoji trigger searches
    /// both corpora). When false, symbols are a scoped trigger via their own
    /// open (`::symbol::`). Defaults true.
    var symbolsFollowEmoji: Bool = true
    /// When true, the Quick Access open follows the emoji trigger (`:` → `:?`).
    /// When false, `quickAccess.open` is the user's own (preset or custom)
    /// trigger. Defaults true.
    var quickAccessFollowEmoji: Bool = true

    init(emoji: Trigger, symbols: Trigger, gif: Trigger, quickAccess: Trigger,
         symbolsFollowEmoji: Bool = true, quickAccessFollowEmoji: Bool = true) {
        self.emoji = emoji
        self.symbols = symbols
        self.gif = gif
        self.quickAccess = quickAccess
        self.symbolsFollowEmoji = symbolsFollowEmoji
        self.quickAccessFollowEmoji = quickAccessFollowEmoji
    }

    /// Tolerant decode: a blob written by an older build is missing newer keys
    /// (e.g. `symbolsFollowEmoji`). Decode every field with `decodeIfPresent`
    /// + sensible defaults so adding a field never nukes a saved config.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TriggerConfig.default
        emoji       = try c.decodeIfPresent(Trigger.self, forKey: .emoji)       ?? d.emoji
        symbols     = try c.decodeIfPresent(Trigger.self, forKey: .symbols)     ?? d.symbols
        gif         = try c.decodeIfPresent(Trigger.self, forKey: .gif)         ?? d.gif
        quickAccess = try c.decodeIfPresent(Trigger.self, forKey: .quickAccess) ?? d.quickAccess
        symbolsFollowEmoji = try c.decodeIfPresent(Bool.self, forKey: .symbolsFollowEmoji) ?? true
        quickAccessFollowEmoji = try c.decodeIfPresent(Bool.self, forKey: .quickAccessFollowEmoji) ?? true
    }

    static let `default` = TriggerConfig(
        emoji:       Trigger(mode: .emoji,       open: ":",   enabled: true),
        symbols:     Trigger(mode: .symbols,     open: "::",  enabled: false),
        gif:         Trigger(mode: .gif,         open: ":::", enabled: true),
        quickAccess: Trigger(mode: .quickAccess, open: ":?",  enabled: true),
        symbolsFollowEmoji: true,
        quickAccessFollowEmoji: true
    )

    /// All four, in the canonical precedence order used to break open-string
    /// ties (emoji → symbols → gif → quickAccess), matching legacy behavior.
    var all: [Trigger] { [emoji, symbols, gif, quickAccess] }

    /// Triggers that can actually fire — enabled with a non-empty open string.
    /// When `symbolsFollowEmoji`, symbols isn't a separate opener (it blends
    /// into emoji results), so it's excluded.
    var active: [Trigger] {
        all.filter { t in
            guard t.enabled, !t.open.isEmpty else { return false }
            if t.mode == .symbols, symbolsFollowEmoji { return false }
            return true
        }
    }

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
        // Quick Access follows the emoji trigger unless given its own open.
        if quickAccessFollowEmoji {
            quickAccess.open = emoji.open + "?"
        }
        // When symbols blend into emoji, the symbols open is unused as an
        // opener — keep it tidy by mirroring the emoji open so no stale value
        // lingers.
        if symbolsFollowEmoji {
            symbols.open = emoji.open
        }
    }
}
