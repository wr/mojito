import Foundation

/// User-selectable skin tone for emoji that support tone modifiers.
/// `default` = no modifier (Unicode emoji's default yellow rendering).
enum SkinTone: String, CaseIterable, Identifiable {
    case `default`
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    var id: String { rawValue }

    /// The Unicode tone modifier codepoint, or empty for `default`.
    /// Appending this to a tone-supporting emoji yields the toned variant.
    var modifier: String {
        switch self {
        case .default:     return ""
        case .light:       return "\u{1F3FB}"
        case .mediumLight: return "\u{1F3FC}"
        case .medium:      return "\u{1F3FD}"
        case .mediumDark:  return "\u{1F3FE}"
        case .dark:        return "\u{1F3FF}"
        }
    }

    /// Vulcan salute (🖖) at this tone — used as the picker swatch. Reads
    /// the tone gradient more clearly than 👋 since the splayed fingers
    /// show more skin.
    var swatchEmoji: String {
        "🖖" + modifier
    }

    var displayName: String {
        switch self {
        case .default:     return "Default"
        case .light:       return "Light"
        case .mediumLight: return "Medium-light"
        case .medium:      return "Medium"
        case .mediumDark:  return "Medium-dark"
        case .dark:        return "Dark"
        }
    }

    /// Read the user's current selection from UserDefaults.
    static var current: SkinTone {
        let raw = UserDefaults.standard.string(forKey: PrefsKey.skinTone) ?? SkinTone.default.rawValue
        return SkinTone(rawValue: raw) ?? .default
    }

    /// Apply this tone to an emoji's character. The modifier is inserted
    /// AFTER the first scalar — which is correct for both single-scalar
    /// emojis (👋 → 👋🏿) and ZWJ sequences (🧔‍♀️ → 🧔🏿‍♀️). Appending the
    /// modifier at the end of a ZWJ sequence produces visually wrong
    /// renderings like 🧔‍♀️🏿.
    func apply(to character: String) -> String {
        guard self != .default else { return character }
        var scalars = Array(character.unicodeScalars)
        guard !scalars.isEmpty else { return character }
        let modifierScalars = Array(modifier.unicodeScalars)
        scalars.insert(contentsOf: modifierScalars, at: 1)
        return String(String.UnicodeScalarView(scalars))
    }
}
