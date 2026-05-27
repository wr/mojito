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

    /// Maps system locale codes (`Locale.preferredLanguages`) to emojibase
    /// locale codes (the keys baked into `emoji.json["l"]`). English is
    /// always available via the primary shortcodes — we only add
    /// *additional* haystacks for the user's other preferred languages.
    ///
    /// `ar`, `fa`, `he` aren't here because emojibase doesn't ship CLDR
    /// shortcodes for them yet; they'd need a raw-CLDR pipeline.
    static let systemToEmojibaseLocale: [String: String] = [
        "de":      "de",
        "en-GB":   "en-gb",
        "es":      "es",
        "es-419":  "es",
        "fr":      "fr",
        "hi":      "hi",
        "it":      "it",
        "ja":      "ja",
        "ko":      "ko",
        "nl":      "nl",
        "pl":      "pl",
        "pt":      "pt",
        "pt-BR":   "pt",
        "pt-PT":   "pt",
        "ru":      "ru",
        "zh-Hans": "zh",
        "zh-Hant": "zh-hant",
    ]
    /// Cap how many locales we mix in per session — every extra locale is
    /// ~2× more haystacks per emoji, and the per-keystroke scoring loop is
    /// O(haystacks). 2 + English is a comfortable budget.
    static let maxAdditionalLocales = 2

    private func activeAdditionalLocales() -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for raw in Locale.preferredLanguages {
            // Try the full system code first (`zh-Hans`, `en-GB`), then the
            // bare language tag (`fr`, `de`) — covers both forms macOS
            // emits depending on whether the user picked a regional variant.
            let candidates: [String] = {
                if let dash = raw.firstIndex(of: "-") {
                    return [raw, String(raw[..<dash])]
                }
                return [raw]
            }()
            for candidate in candidates {
                guard let mapped = Self.systemToEmojibaseLocale[candidate],
                      !seen.contains(mapped) else { continue }
                seen.insert(mapped)
                out.append(mapped)
                break
            }
            if out.count >= Self.maxAdditionalLocales { break }
        }
        return out
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
            let activeLocales = activeAdditionalLocales()
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
                haystacks.reserveCapacity(emoji.shortcodes.count + 1 + activeLocales.count * 2)
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
                for locale in activeLocales {
                    guard let localCodes = emoji.localizedShortcodes[locale] else { continue }
                    for code in localCodes {
                        let lowered = code.lowercased()
                        haystacks.append(EmojiHaystack(display: code, chars: Array(lowered)))
                        // First-seen wins so English primaries keep priority
                        // when shortcodes collide across locales.
                        if index[lowered] == nil {
                            index[lowered] = emoji
                        }
                    }
                }
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
