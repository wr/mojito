import Foundation

/// Word-keyed emoticon table for *ambient* detection — no leading `:` required.
///
/// `TriggerStateMachine` accumulates an `idleWord` from each printable
/// keystroke in `.idle` and consults this table whenever a terminator char
/// (space, tab, newline, sentence punctuation) lands. The terminator itself
/// is never part of the lookup key; only the run of chars between
/// terminators (or between start-of-input and the first terminator) is
/// matched.
///
/// Compared to `EmoticonTable` (which is keyed by the suffix after `:`),
/// this one carries the full literal sequence the user typed, so
/// case-sensitive variants like `XD` vs `xD` need explicit entries.
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
    ]

    /// Returns the emoji for a candidate word, or nil if no entry matches.
    static func emoji(for word: String) -> String? {
        map[word]
    }

    /// True if the word should fire the moment it completes, without waiting
    /// for a terminator. Restricted to emoticons whose leading character is
    /// non-alphanumeric (`<3`, `</3`, `>:)`, `>:(`), so letter-led ones like
    /// `XD` or `B)` still require a terminator and don't eat into normal
    /// prose (`XDog`, `Bobby`).
    static func shouldFireImmediately(_ word: String) -> Bool {
        guard let first = word.first else { return false }
        if first.isLetter || first.isNumber { return false }
        return map[word] != nil
    }

    /// All distinct first-character prefixes of ambient emoticons that contain a `:`
    /// somewhere after the first char (currently just `>`). The state machine uses
    /// this to decide whether a `:` typed in idle should continue building an ambient
    /// word instead of starting colon-capture.
    static let colonContinuationPrefixes: Set<String> = [">"]
}
