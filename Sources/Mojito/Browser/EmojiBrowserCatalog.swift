import Foundation

/// Shared constants + category model for the full-library browser window.
enum EmojiBrowser {
    /// Sentinel hexcode for the "Browse all emojis…" row injected at the
    /// bottom of the bare-`:` picker. Routed on (opens the browser), never
    /// inserted as text — same opaque-id trick the pinned rows use.
    static let sentinelHexcode = "BROWSE"

    /// The synthetic row the picker renders as "Browse all emojis…".
    static var browseRow: ScoredEmoji {
        let emoji = Emoji(
            hexcode: sentinelHexcode,
            character: "🔎",
            label: "Browse all emojis",
            shortcodes: ["browse all emojis"],
            tags: [],
            group: -1,
            order: Int.max
        )
        return ScoredEmoji(emoji: emoji, matchedShortcode: "browse all emojis")
    }
}

/// Sections shown down the browser grid. The first two are dynamic (driven
/// by usage + favorites); the rest map onto emojibase group numbers.
/// emojibase groups: 0 Smileys, 1 People, 2 Component (skipped), 3 Animals,
/// 4 Food, 5 Travel, 6 Activities, 7 Objects, 8 Symbols, 9 Flags.
enum EmojiCategory: String, CaseIterable, Identifiable {
    case frequentlyUsed
    case quickAccess
    case smileysPeople
    case animalsNature
    case foodDrink
    case travelPlaces
    case activities
    case objects
    case symbols
    case flags
    /// Mojito's typographic symbols (★ ⌘ ⌥ …), from `SymbolsDatabase` —
    /// not an emojibase group.
    case specialCharacters

    var id: String { rawValue }

    /// emojibase group numbers this category spans. Empty for the dynamic
    /// (usage / favorites) and symbols sections.
    var groups: [Int] {
        switch self {
        case .frequentlyUsed, .quickAccess, .specialCharacters: return []
        case .smileysPeople: return [0, 1]
        case .animalsNature: return [3]
        case .foodDrink:     return [4]
        case .travelPlaces:  return [5]
        case .activities:    return [6]
        case .objects:       return [7]
        case .symbols:       return [8]
        case .flags:         return [9]
        }
    }

    var isDynamic: Bool { groups.isEmpty }

    var title: String {
        switch self {
        case .frequentlyUsed:    return String(localized: "Frequently Used")
        case .quickAccess:       return String(localized: "Quick Access")
        case .smileysPeople:     return String(localized: "Smileys & People")
        case .animalsNature:     return String(localized: "Animals & Nature")
        case .foodDrink:         return String(localized: "Food & Drink")
        case .travelPlaces:      return String(localized: "Travel & Places")
        case .activities:        return String(localized: "Activities")
        case .objects:           return String(localized: "Objects")
        case .symbols:           return String(localized: "Symbols")
        case .flags:             return String(localized: "Flags")
        case .specialCharacters: return String(localized: "Special Characters")
        }
    }

    /// SF Symbol shown in the bottom category tab bar.
    var tabSymbol: String {
        switch self {
        case .frequentlyUsed:    return "clock"
        case .quickAccess:       return "star.fill"
        case .smileysPeople:     return "face.smiling"
        case .animalsNature:     return "leaf"
        case .foodDrink:         return "fork.knife"
        case .travelPlaces:      return "airplane"
        case .activities:        return "basketball"
        case .objects:           return "lightbulb"
        case .symbols:           return "number"
        case .flags:             return "flag"
        case .specialCharacters: return "command"
        }
    }
}
