import Foundation

struct Emoji: Decodable, Identifiable, Hashable {
    let hexcode: String
    let character: String
    let label: String
    let shortcodes: [String]
    let tags: [String]
    let group: Int
    let order: Int
    /// From emojibase's `skins` array. Sentinel/egg entries default to false.
    let supportsSkinTone: Bool
    /// CLDR-derived locale shortcodes, keyed by language code (`fr`/`de`/`es`).
    /// Each list mixes diacritic-preserving (`cœur_rouge`) and ASCII-
    /// transliterated (`coeur_rouge`) flavors so typing either form matches.
    /// Empty dict for emoji without locale data.
    let localizedShortcodes: [String: [String]]

    var id: String { hexcode }
    var primaryShortcode: String { shortcodes.first ?? label }

    init(
        hexcode: String,
        character: String,
        label: String,
        shortcodes: [String],
        tags: [String],
        group: Int,
        order: Int,
        supportsSkinTone: Bool = false,
        localizedShortcodes: [String: [String]] = [:]
    ) {
        self.hexcode = hexcode
        self.character = character
        self.label = label
        self.shortcodes = shortcodes
        self.tags = tags
        self.group = group
        self.order = order
        self.supportsSkinTone = supportsSkinTone
        self.localizedShortcodes = localizedShortcodes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hexcode    = try c.decode(String.self, forKey: .hexcode)
        self.character  = try c.decode(String.self, forKey: .character)
        self.label      = try c.decode(String.self, forKey: .label)
        self.shortcodes = try c.decode([String].self, forKey: .shortcodes)
        self.tags       = try c.decode([String].self, forKey: .tags)
        self.group      = try c.decode(Int.self,    forKey: .group)
        self.order      = try c.decode(Int.self,    forKey: .order)
        self.supportsSkinTone = (try? c.decode(Bool.self, forKey: .supportsSkinTone)) ?? false
        self.localizedShortcodes = (try? c.decode([String: [String]].self, forKey: .localizedShortcodes)) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case hexcode             = "h"
        case character           = "e"
        case label               = "n"
        case shortcodes          = "s"
        case tags                = "t"
        case group               = "g"
        case order               = "o"
        case supportsSkinTone    = "k"
        case localizedShortcodes = "l"
    }
}
