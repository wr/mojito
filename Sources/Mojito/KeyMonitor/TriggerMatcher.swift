import Foundation

/// Pure trigger-string lookups over a `TriggerConfig`. The state machine owns
/// the capture lifecycle (opening buffer, query, close progress) and calls
/// these to decide *which* mode a delimiter run opens and *how long* its
/// open/close strings are. No AppKit, no mutable lifecycle state — trivially
/// testable.
///
/// Open strings are short (1–4 chars) and few (≤4 modes), so plain prefix
/// scans beat a trie and keep the per-keystroke cost negligible. Ties on an
/// identical open string resolve by `TriggerConfig.all` order
/// (emoji → symbols → gif → quickAccess), matching legacy precedence; the
/// validator surfaces such collisions to the user.
struct TriggerMatcher: Equatable {
    let config: TriggerConfig
    private let openers: [(mode: TriggerMode, open: [Character])]

    init(config: TriggerConfig) {
        self.config = config
        self.openers = config.active.map { ($0.mode, Array($0.open)) }
    }

    static func == (lhs: TriggerMatcher, rhs: TriggerMatcher) -> Bool {
        lhs.config == rhs.config
    }

    /// The mode whose open string exactly equals `buffer`, by precedence.
    func terminalMode(for buffer: [Character]) -> TriggerMode? {
        openers.first { $0.open == buffer }?.mode
    }

    /// Some opener's open string strictly extends `buffer` — i.e. typing more
    /// delimiter chars could still form a longer trigger. Drives progressive
    /// upgrade (`:` → `::` → `:::`).
    func canExtend(_ buffer: [Character]) -> Bool {
        openers.contains { $0.open.count > buffer.count && hasPrefix($0.open, buffer) }
    }

    /// `buffer` is a viable start of some trigger (a prefix of, or equal to,
    /// an open string). Gates entry into the opening phase from idle.
    func isViablePrefix(_ buffer: [Character]) -> Bool {
        openers.contains { $0.open.count >= buffer.count && hasPrefix($0.open, buffer) }
    }

    /// The close string for a mode that finishes by typing a delimiter. For
    /// the bracketing modes (`.emoji` / `.symbols`) it's mirrored from the open
    /// (`:foo:`, `::foo::`); `.gif` / `.quickAccess` open a sticky UI and have
    /// no close. Nil if the mode is inactive or its open is blank.
    func close(for mode: TriggerMode) -> [Character]? {
        switch mode {
        case .emoji, .symbols:
            let open = config.trigger(for: mode).open
            return open.isEmpty ? nil : Array(open)
        case .gif, .quickAccess:
            return nil
        }
    }

    /// Whether `:` is a prefix of any active trigger. Colon-emoticons (`:)`,
    /// `:D`) are detected via the emoji-capture path, which only exists while
    /// a `:` can open a capture; if the user removes `:` from every trigger,
    /// colon-emoticons can't fire (the validator notes this).
    var colonStartsATrigger: Bool {
        openers.contains { $0.open.first == ":" }
    }

    private func hasPrefix(_ string: [Character], _ prefix: [Character]) -> Bool {
        prefix.count <= string.count && Array(string.prefix(prefix.count)) == prefix
    }
}
