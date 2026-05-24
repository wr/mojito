import Foundation

/// Pre-lowercased + pre-charified at DB load — the fuzzy scorer never
/// reallocates per search.
struct EmojiHaystack {
    let display: String
    let chars: [Character]
}

/// `FuzzyMatcher` iterates these directly so the per-keystroke loop never allocates.
struct IndexedEmoji {
    let emoji: Emoji
    let haystacks: [EmojiHaystack]
}

@MainActor
final class EmojiDatabase: ObservableObject {
    static let shared = EmojiDatabase()

    private(set) var all: [Emoji] = []
    private(set) var indexed: [IndexedEmoji] = []
    private(set) var byShortcode: [String: Emoji] = [:]
    private(set) var byHexcode: [String: Emoji] = [:]

    private init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json", subdirectory: "Emoji")
            ?? Bundle.main.url(forResource: "emoji", withExtension: "json") else {
            assertionFailure("emoji.json missing from bundle — did the resource get included?")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Emoji].self, from: data)
            self.all = decoded
            var index: [String: Emoji] = [:]
            index.reserveCapacity(decoded.count * 2)
            var byHex: [String: Emoji] = [:]
            byHex.reserveCapacity(decoded.count)
            var indexedBuf: [IndexedEmoji] = []
            indexedBuf.reserveCapacity(decoded.count)
            for emoji in decoded {
                byHex[emoji.hexcode] = emoji
                for shortcode in emoji.shortcodes {
                    index[shortcode.lowercased()] = emoji
                }
                var haystacks: [EmojiHaystack] = []
                haystacks.reserveCapacity(emoji.shortcodes.count + 1)
                for shortcode in emoji.shortcodes {
                    haystacks.append(EmojiHaystack(
                        display: shortcode,
                        chars: Array(shortcode.lowercased())
                    ))
                }
                let labelKey = emoji.label.replacingOccurrences(of: " ", with: "_")
                haystacks.append(EmojiHaystack(
                    display: labelKey,
                    chars: Array(labelKey.lowercased())
                ))
                indexedBuf.append(IndexedEmoji(emoji: emoji, haystacks: haystacks))
            }
            self.byShortcode = index
            self.byHexcode = byHex
            self.indexed = indexedBuf
        } catch {
            assertionFailure("Failed to load emoji.json: \(error)")
        }
    }

    func exact(_ shortcode: String) -> Emoji? {
        byShortcode[shortcode.lowercased()]
    }
}
