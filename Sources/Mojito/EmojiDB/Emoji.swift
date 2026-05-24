import Foundation

struct Emoji: Decodable, Identifiable, Hashable {
    let hexcode: String
    let character: String
    let label: String
    let shortcodes: [String]
    let tags: [String]
    let group: Int
    let order: Int
    /// True if the emoji has skin-tone variants. Set from emojibase's
    /// `skins` array at DB-build time. Sentinel/easter-egg entries default
    /// to false.
    let supportsSkinTone: Bool

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
        supportsSkinTone: Bool = false
    ) {
        self.hexcode = hexcode
        self.character = character
        self.label = label
        self.shortcodes = shortcodes
        self.tags = tags
        self.group = group
        self.order = order
        self.supportsSkinTone = supportsSkinTone
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
    }

    private enum CodingKeys: String, CodingKey {
        case hexcode          = "h"
        case character        = "e"
        case label            = "n"
        case shortcodes       = "s"
        case tags             = "t"
        case group            = "g"
        case order            = "o"
        case supportsSkinTone = "k"
    }
}
