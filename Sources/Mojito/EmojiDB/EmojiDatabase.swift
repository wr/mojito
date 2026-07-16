import Foundation

/// Pre-lowercased + pre-charified at DB load — the fuzzy scorer never
/// reallocates per search.
struct EmojiHaystack {
    let display: String
    let chars: [Character]
    /// Emojibase keyword (e.g. "meditation" on 🧘). Scored with a penalty and
    /// never eligible for the prefix tier, so real shortcodes always win.
    let isTag: Bool
    /// A user-defined alias (see `AliasStore`). Scored with a bonus so the
    /// aliased emoji outranks built-ins for the alias term.
    let isAlias: Bool

    init(display: String, chars: [Character], isTag: Bool = false, isAlias: Bool = false) {
        self.display = display
        self.chars = chars
        self.isTag = isTag
        self.isAlias = isAlias
    }
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

    /// Resolved once at load and reused when custom aliases change, so a re-merge
    /// doesn't re-scan `Locale.preferredLanguages`.
    private var activeLocales: [String] = []
    private var aliasObserver: NSObjectProtocol?

    private init() {
        load()
        // Re-merge whenever the user edits their custom shortcuts. The index
        // arrays aren't @Published, but the live-typing path reads `indexed`
        // imperatively each keystroke, so a rebuild takes effect immediately.
        aliasObserver = NotificationCenter.default.addObserver(
            forName: AliasStore.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAliases(AliasStore.shared.aliases) }
        }
    }

    deinit {
        if let aliasObserver { NotificationCenter.default.removeObserver(aliasObserver) }
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

    /// emojibase group id for "component" (skin-tone + hair modifiers) — kept
    /// out of the corpus entirely; see `load()`.
    static let componentGroup = 2

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
            // emojibase group 2 is "component": bare skin-tone (🏻–🏿) and hair
            // (🦰🦱🦳🦲) modifiers that only combine with another emoji, never
            // stand alone. The browser already skips this group; drop it here so
            // it can't surface as a standalone search hit either.
            let decoded = try JSONDecoder().decode([Emoji].self, from: data)
                .filter { $0.group != Self.componentGroup }
            self.all = decoded
            self.activeLocales = activeAdditionalLocales()
            applyAliases(AliasStore.shared.aliases)
        } catch {
            assertionFailure("Failed to load emoji.json: \(error)")
        }
    }

    /// Rebuild the search index from the baked corpus plus the given custom
    /// aliases. Cheap enough to re-run on every alias edit (no JSON re-decode).
    func applyAliases(_ aliases: [CustomAlias]) {
        let result = Self.buildIndex(emojis: all, aliases: aliases, activeLocales: activeLocales)
        self.byShortcode = result.byShortcode
        self.byHexcode = result.byHexcode
        self.indexed = result.indexed
        objectWillChange.send()
    }

    struct IndexResult {
        let byShortcode: [String: Emoji]
        let byHexcode: [String: Emoji]
        let indexed: [IndexedEmoji]
    }

    /// Pure corpus → index build. Custom aliases are layered on last: an alias
    /// adds a searchable+typable haystack (flagged `isAlias`) to its target and
    /// overrides `byShortcode` for that spelling, so the user's mapping wins over
    /// any built-in with the same name. Aliases pointing at an unknown hexcode
    /// are ignored.
    nonisolated static func buildIndex(
        emojis: [Emoji],
        aliases: [CustomAlias],
        activeLocales: [String]
    ) -> IndexResult {
        // Group aliases by target so each emoji's haystacks are built in one pass.
        var aliasesByHex: [String: [String]] = [:]
        for entry in aliases {
            aliasesByHex[entry.hexcode, default: []].append(entry.alias.lowercased())
        }

        var index: [String: Emoji] = [:]
        index.reserveCapacity(emojis.count * 2)
        var byHex: [String: Emoji] = [:]
        byHex.reserveCapacity(emojis.count)
        var indexedBuf: [IndexedEmoji] = []
        indexedBuf.reserveCapacity(emojis.count)

        for emoji in emojis {
            byHex[emoji.hexcode] = emoji
            for shortcode in emoji.shortcodes {
                index[shortcode.lowercased()] = emoji
            }
            let aliasList = aliasesByHex[emoji.hexcode] ?? []
            var haystacks: [EmojiHaystack] = []
            haystacks.reserveCapacity(emoji.shortcodes.count + 1 + emoji.tags.count + activeLocales.count * 2 + aliasList.count)
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
            // Emojibase keywords (`meditation`, `happy`, …). Searchable but
            // not exact-typable — kept out of `index` so `:happy:` doesn't
            // resolve to an arbitrary one of the dozens that share the tag.
            for tag in emoji.tags {
                haystacks.append(EmojiHaystack(
                    display: tag,
                    chars: Array(tag.lowercased()),
                    isTag: true
                ))
            }
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
            for alias in aliasList {
                haystacks.append(EmojiHaystack(display: alias, chars: Array(alias), isAlias: true))
            }
            indexedBuf.append(IndexedEmoji(emoji: emoji, haystacks: haystacks))
        }

        // Alias overrides applied last so a user alias beats any built-in or
        // locale shortcode sharing the same spelling.
        for entry in aliases {
            guard let target = byHex[entry.hexcode] else { continue }
            index[entry.alias.lowercased()] = target
        }

        // Symbol-targeted aliases (⌘, →, π …). Symbols aren't in the emoji
        // corpus, so resolve them against `SymbolsDatabase` and add each as a
        // first-class indexed row — typable + searchable by its alias term even
        // when the Symbols feature is off. Touching `SymbolsDatabase.byHexcode`
        // kicks off a slow CoreText sweep, so only reach for it when a symbol
        // alias actually exists.
        let symbolAliases = aliases.filter { $0.hexcode.hasPrefix("SYM_") && byHex[$0.hexcode] == nil }
        if !symbolAliases.isEmpty {
            var order: [String] = []
            var bySymHex: [String: [String]] = [:]
            for entry in symbolAliases {
                if bySymHex[entry.hexcode] == nil { order.append(entry.hexcode) }
                bySymHex[entry.hexcode, default: []].append(entry.alias.lowercased())
            }
            for hex in order {
                guard let symbol = SymbolsDatabase.byHexcode[hex] else { continue }
                byHex[hex] = symbol
                var haystacks: [EmojiHaystack] = []
                haystacks.reserveCapacity(bySymHex[hex]?.count ?? 0)
                for alias in bySymHex[hex] ?? [] {
                    haystacks.append(EmojiHaystack(display: alias, chars: Array(alias), isAlias: true))
                    index[alias] = symbol
                }
                indexedBuf.append(IndexedEmoji(emoji: symbol, haystacks: haystacks))
            }
        }

        return IndexResult(byShortcode: index, byHexcode: byHex, indexed: indexedBuf)
    }

    func exact(_ shortcode: String) -> Emoji? {
        byShortcode[shortcode.lowercased()]
    }
}
