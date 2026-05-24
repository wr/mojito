import Foundation

/// `default` = no modifier (Unicode emoji's default yellow rendering).
enum SkinTone: String, CaseIterable, Identifiable {
    case `default`
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    var id: String { rawValue }

    /// Unicode tone modifier codepoint, empty for `default`.
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

    /// Splayed fingers show more skin than 👋, so the tone gradient
    /// reads more clearly.
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

    static var current: SkinTone {
        let raw = UserDefaults.standard.string(forKey: PrefsKey.skinTone) ?? SkinTone.default.rawValue
        return SkinTone(rawValue: raw) ?? .default
    }

    /// Insert the modifier AFTER the first scalar. Correct for both
    /// single-scalar (👋 → 👋🏿) and ZWJ sequences (🧔‍♀️ → 🧔🏿‍♀️).
    /// Appending at the end gives wrong renderings like 🧔‍♀️🏿.
    func apply(to character: String) -> String {
        guard self != .default else { return character }
        var scalars = Array(character.unicodeScalars)
        guard !scalars.isEmpty else { return character }
        let modifierScalars = Array(modifier.unicodeScalars)
        scalars.insert(contentsOf: modifierScalars, at: 1)
        return String(String.UnicodeScalarView(scalars))
    }
}
