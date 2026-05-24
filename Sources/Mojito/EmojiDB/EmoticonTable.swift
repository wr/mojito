import Foundation

/// Maps text that follows the opening `:` to an emoji.
///
/// Two flavors of key:
///  - Pure-punctuation emoticons (`:)`, `:|`) — the cancel char IS the
///    full emoticon. Query is empty, terminator is the char itself.
///    The terminator is consumed (removed along with the `:`).
///  - Letter emoticons (`:D`, `:-D`) — query is the name-char run after `:`
///    (e.g. "D" or "-D"). The terminator (space/period/etc.) is just a
///    delimiter — it stays in the text after replacement.
///
/// Matching strategy: try `query + terminator` first (catches the pure-
/// punctuation form), then `query` alone.
enum EmoticonTable {
    private static let map: [String: String] = [
        // Pure punctuation — terminator is the emoticon's tail.
        ")":   "🙂",
        "(":   "🙁",
        "D":   "😃",
        "P":   "😛",
        "p":   "😛",
        "O":   "😮",
        "o":   "😮",
        "|":   "😐",
        "/":   "😕",
        "\\":  "😕",
        "3":   "😺",
        "*":   "😘",

        // Dash variants (`:-)`, `:-D`, …) — query is "-".
        "-)":  "🙂",
        "-(":  "🙁",
        "-D":  "😃",
        "-P":  "😛",
        "-p":  "😛",
        "-O":  "😮",
        "-o":  "😮",
        "-|":  "😐",
        "-/":  "😕",
        "-\\": "😕",
        "-*":  "😘",
    ]

    static func match(query: String, terminator: Character) -> EmoticonMatch? {
        let withTerm = query + String(terminator)
        if let emoji = map[withTerm] {
            return EmoticonMatch(emoji: emoji, consumesTerminator: true)
        }
        if !query.isEmpty, let emoji = map[query] {
            return EmoticonMatch(emoji: emoji, consumesTerminator: false)
        }
        return nil
    }
}

struct EmoticonMatch {
    let emoji: String
    /// True if the terminator was part of the emoticon (e.g. the `)` in `:)`).
    /// False if the terminator was just a delimiter that should stay in the
    /// text after replacement.
    let consumesTerminator: Bool
}
