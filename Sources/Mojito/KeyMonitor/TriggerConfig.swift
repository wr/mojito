import Foundation

/// The four fixed trigger modes. Users can't add modes — only retune the
/// strings that fire each one.
enum TriggerMode: String, CaseIterable, Codable, Equatable {
    case emoji          // `:query:` → emoji picker / exact match
    case symbols        // `::query:` → experimental symbol corpus
    case gif            // `:::query` → Giphy picker
    case quickAccess    // `:?` → favorites pill
}

/// One mode's trigger strings. `close` is meaningful only for `.emoji` /
/// `.symbols` (the modes you finish by typing a delimiter); `.gif` /
/// `.quickAccess` open a sticky UI and have no typed close.
struct Trigger: Equatable, Codable {
    let mode: TriggerMode
    var open: String
    var close: String?
    var enabled: Bool
}

/// The active trigger set. `default` reproduces Mojito's historical hardcoded
/// triggers exactly, so an untouched install behaves identically.
struct TriggerConfig: Equatable, Codable {
    var emoji: Trigger
    var symbols: Trigger
    var gif: Trigger
    var quickAccess: Trigger

    static let `default` = TriggerConfig(
        emoji:       Trigger(mode: .emoji,       open: ":",   close: ":", enabled: true),
        symbols:     Trigger(mode: .symbols,     open: "::",  close: ":", enabled: false),
        gif:         Trigger(mode: .gif,         open: ":::", close: nil, enabled: true),
        quickAccess: Trigger(mode: .quickAccess, open: ":?",  close: nil, enabled: true)
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
}
