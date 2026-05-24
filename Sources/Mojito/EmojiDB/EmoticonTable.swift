import Foundation

/// Maps the suffix after `:` to an emoji.
///
/// Two key flavors:
///  - Pure-punctuation (`:)`, `:|`): empty query, terminator IS the
///    emoticon's tail and gets consumed.
///  - Letter (`:D`, `:-D`): query is the name-char run, terminator is
///    just a delimiter and stays in the text.
///
/// Match strategy: `query + terminator` first, then `query` alone.
enum EmoticonTable {
    private static let map: [String: String] = [
        // Pure punctuation — terminator is the tail.
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

        // `'` is a name char so it lands in the query, not the terminator.
        "'(":  "😢",
        "')":  "😂",

        // Dash variants (`:-)`, `:-D`, …).
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
    /// True if terminator was the emoticon's tail (the `)` in `:)`),
    /// false if it was just a delimiter.
    let consumesTerminator: Bool
}
