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
    ]

    static func emoji(for word: String) -> String? {
        map[word]
    }

    /// The arrow family — the only ambient emoticons allowed to fire when
    /// typed flush against text (`Foo->Bar`), matched as a trailing suffix of
    /// the buffer. Everything else stays boundary-gated so it can't eat into
    /// prose. `=`-based forms (`=>`, `<=`) are deliberately excluded: they
    /// collide with code operators and comparisons. Derived as the keys built
    /// solely from arrow punctuation, so it tracks the map automatically.
    private static let arrowChars: Set<Character> = ["-", "<", ">"]
    static let arrowKeys: Set<String> = Set(map.keys.filter { $0.allSatisfy(arrowChars.contains) })

    /// Whether `word` is an arrow-family key — used to gate the whole arrow
    /// feature behind the "Convert text arrows" setting without touching the
    /// other ambient emoticons.
    static func isArrow(_ word: String) -> Bool { arrowKeys.contains(word) }

    /// The longest arrow key that is a suffix of `buffer`, if any. Lets the
    /// state machine pull `->` out of `Foo->` without a leading boundary.
    static func arrowSuffix(of buffer: String) -> String? {
        var best: String?
        for key in arrowKeys where buffer.hasSuffix(key) {
            if best == nil || key.count > best!.count { best = key }
        }
        return best
    }

    /// True if appending more chars to `arrow` could still reach a longer
    /// arrow key (`<-` → `<->`, `<=` → `<=>`) — used to defer firing the
    /// shorter match until the next keystroke decides.
    static func hasLongerArrow(extending arrow: String) -> Bool {
        for key in arrowKeys where key.count > arrow.count && key.hasPrefix(arrow) {
            return true
        }
        return false
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
