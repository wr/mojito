import Foundation

/// Ambient emoticons — no leading `:` required.
///
/// Keys are full literal sequences typed between terminators, so case
/// variants (`XD` / `xD`) need separate entries. Unlike `EmoticonTable`
/// (which keys on the suffix after `:`), the terminator never enters the key.
enum AmbientEmoticonTable {
    private static let map: [String: String] = [
        "<3":   "❤️",
        "</3":  "💔",
        "XD":   "😆",
        "xD":   "😆",
        ">:)":  "😈",
        ">:(":  "👿",
        "B)":   "😎",
        "O_o":  "😳",
        "o_O":  "😳",
        "->":   "→",
        "<-":   "←",
        "<->":  "↔",
        "=>":   "⇒",
        "<=>":  "⇔",
    ]

    static func emoji(for word: String) -> String? {
        map[word]
    }

    /// Fire the moment a non-alphanumeric-led entry completes (`<3`,
    /// `>:)` etc.). Letter-led entries (`XD`, `B)`) wait for a terminator
    /// so they don't eat into prose (`XDog`, `Bobby`).
    static func shouldFireImmediately(_ word: String) -> Bool {
        guard let first = word.first else { return false }
        if first.isLetter || first.isNumber { return false }
        return map[word] != nil
    }

    /// True if some map key is strictly longer than `prefix` and starts
    /// with it — used by the state machine to defer firing a complete
    /// shorter match (`<-`) when a longer one (`<->`) might still arrive.
    static func hasLongerMatch(for prefix: String) -> Bool {
        guard !prefix.isEmpty else { return false }
        for key in map.keys where key.count > prefix.count && key.hasPrefix(prefix) {
            return true
        }
        return false
    }

    /// First-char prefixes that may legitimately continue with `:` (so
    /// `>:)` doesn't get hijacked by colon-capture).
    static let colonContinuationPrefixes: Set<String> = [">"]
}
