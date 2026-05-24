import Foundation

/// Discoverable effects. Persisted-set ids are opaque (`k01` … `k21`) so
/// neither the binary nor the on-disk plist reveals which effects exist or
/// what their trigger keywords are. The user-facing strings (title /
/// detail / hint) still live as plain text — they have to render somewhere
/// — but only after the effect is discovered does the title leak to the
/// user, and the hints intentionally never quote the trigger word.
enum EasterEgg: String, CaseIterable, Identifiable {
    case mojito          = "k01"
    case moof            = "k03"
    case confetti        = "k04"
    case pride           = "k05"
    case sosumi          = "k06"
    case floppy          = "k07"
    case dialup          = "k08"
    case wilhelm         = "k09"
    case snow            = "k10"
    case matrix          = "k11"
    case fireworks       = "k12"
    case trogdor         = "k13"
    case lost            = "k14"
    case toasters        = "k16"
    case dvd             = "k17"
    case bsod            = "k19"
    case konami          = "k99"
    case snake           = "k20"
    case thermonuclear   = "k21"
    case myleg           = "k22"
    case tada            = "k23"
    case xp              = "k24"
    case solitaire       = "k25"
    case rickroll        = "k27"
    case crt             = "k29"
    case celery          = "k30"
    case perfectBounce   = "k31"

    var id: String { rawValue }

    /// User-facing name shown once the egg has been discovered.
    var title: String {
        switch self {
        case .mojito:          return "Emoji rain"
        case .moof:            return "Moof!"
        case .confetti:        return "Confetti shower"
        case .pride:           return "Pride wave"
        case .sosumi:          return "Sosumi"
        case .floppy:          return "Floppy disk"
        case .dialup:          return "Dial-up"
        case .wilhelm:         return "Wilhelm scream"
        case .snow:            return "Snowfall"
        case .matrix:          return "The Matrix"
        case .fireworks:       return "Fireworks"
        case .trogdor:         return "Trogdor!"
        case .lost:            return "The Hatch"
        case .toasters:        return "Flying Toasters"
        case .dvd:             return "Bouncing DVD"
        case .bsod:            return "Blue Screen"
        case .konami:          return "Konami Code"
        case .snake:           return "Snake"
        case .thermonuclear:   return "Global Thermonuclear War"
        case .myleg:           return "My leg!"
        case .tada:            return "Ta-da!"
        case .xp:              return "Bliss"
        case .solitaire:       return "Solitaire Win"
        case .rickroll:        return "Rickroll"
        case .crt:             return "CRT Power Off"
        case .celery:          return "Celery Man"
        case .perfectBounce:   return "Perfect Bounce"
        }
    }

    /// Detail shown next to a discovered egg in the About panel. Spells
    /// out the trigger now that the user has found it.
    var detail: String {
        switch self {
        case .mojito:          return "`:mojito:` — a downpour of emoji."
        case .moof:            return "`:moof:` — Clarus the dogcow."
        case .confetti:        return "`:confetti:` — celebrate."
        case .pride:           return "`:pride:` — raise the flag."
        case .sosumi:          return "`:sosumi:` — System 7's last word."
        case .floppy:          return "`:floppy:` — the sound of saving."
        case .dialup:          return "`:dialup:` — log on."
        case .wilhelm:         return "`:wilhelm:` — the scream."
        case .snow:            return "`:snow:` — a quiet snowfall."
        case .matrix:          return "`:matrix:` — wake up, Neo."
        case .fireworks:       return "`:fireworks:` — light the sky."
        case .trogdor:         return "`:trogdor:` — burninate."
        case .lost:            return "`:lost:` — the numbers are bad."
        case .toasters:        return "`:toasters:` — they're back."
        case .dvd:             return "`:dvd2:` — please let it hit the corner."
        case .bsod:            return "`:bsod:` — kernel panic."
        case .konami:          return "Type `:` then ↑↑↓↓←→←→BA."
        case .snake:           return "`:snakegame:` — eat. grow. wrap."
        case .thermonuclear:   return "`:globalthermonuclearwar:` — shall we play a game?"
        case .myleg:           return "`:myleg:` — yelled by a fry cook in Bikini Bottom."
        case .tada:            return "`:tada:` — that little victory chime."
        case .xp:              return "`:xp:` — welcome back, Wells."
        case .solitaire:       return "`:solitaire:` — the cards cascade once more."
        case .rickroll:        return "`:rickroll:` — you should know better."
        case .crt:             return "`:crt:` — *thunk*. Lights out."
        case .celery:          return "`:celery:` — good morning, Paul."
        case .perfectBounce:   return "Hit the corner."
        }
    }

    /// Subtle nudge shown next to an *undiscovered* egg. Oblique by design.
    var hint: String {
        switch self {
        case .mojito:          return "The drink the app is named after."
        case .moof:            return "He moos. He woofs. He's printed in the manual."
        case .confetti:        return "Party in a can."
        case .pride:           return "Six stripes."
        case .sosumi:          return "Apple v. Apple, settled in a sound."
        case .floppy:          return "1.44 MB of slow."
        case .dialup:          return "You've got mail."
        case .wilhelm:         return "The same scream, in every movie."
        case .snow:            return "Three feet, overnight."
        case .matrix:          return "Green rain."
        case .fireworks:       return "The Fourth, indoors."
        case .trogdor:         return "Consummate V's, and a beefy arm."
        case .lost:            return "Push the button. Every 108 minutes."
        case .toasters:        return "After dark, with wings."
        case .dvd:             return "It has to hit the corner eventually."
        case .bsod:            return "A non-fatal error."
        case .konami:          return "Up, up..."
        case .snake:           return "Nokia, circa 1997."
        case .thermonuclear:   return "How about a nice game of chess?"
        case .myleg:           return "Anchor falls. Predictable lament."
        case .tada:            return "Tiny brass fanfare, .wav format."
        case .xp:              return "A hill, a sky, a single account."
        case .solitaire:       return "Bouncing cards, victory."
        case .rickroll:        return "Never gonna, well, you know."
        case .crt:             return "Click. A dot. Gone."
        case .celery:          return "Computer, load up a sequence."
        case .perfectBounce:   return "Some things require patience."
        }
    }

    var emojiGlyph: String? {
        switch self {
        case .mojito:          return "🎁"
        case .moof:            return nil
        case .confetti:        return "🎊"
        case .pride:           return "🏳️‍🌈"
        case .sosumi:          return "🔔"
        case .floppy:          return "💾"
        case .dialup:          return "📞"
        case .wilhelm:         return "🎬"
        case .snow:            return "❄️"
        case .matrix:          return "🟢"
        case .fireworks:       return "🎆"
        case .trogdor:         return "🐉"
        case .lost:            return "🏝️"
        case .toasters:        return "🍞"
        case .dvd:             return "💿"
        case .bsod:            return "💙"
        case .konami:          return "🕹️"
        case .snake:           return "🐍"
        case .thermonuclear:   return "☢️"
        case .myleg:           return "🦵"
        case .tada:            return "🎉"
        case .xp:              return "🪟"
        case .solitaire:       return "🃏"
        case .rickroll:        return "🎤"
        case .crt:             return "📺"
        case .celery:          return "🥬"
        case .perfectBounce:   return "🎯"
        }
    }
}

/// Persists the set of effects the user has discovered.
@MainActor
enum EasterEggTracker {
    /// In-memory mirror of the persisted set. Loaded on first access via a
    /// one-time migration: pre-obfuscation builds stored plain-text raw
    /// values (e.g. `"mojito"`) and we hash those, look them up against
    /// `EggIndex`, and rewrite the persisted set as opaque ids. The legacy
    /// strings never appear in source — they exist only as hashes inside
    /// `EggIndex.migrateLegacyRawValue`.
    private static var cache: Set<String> = loadAndMigrate()

    private static func loadAndMigrate() -> Set<String> {
        let stored = (UserDefaults.standard.array(forKey: PrefsKey.easterEggsDiscovered) as? [String]) ?? []
        var converted: Set<String> = []
        var dirty = false
        let knownIDs: Set<String> = Set(EasterEgg.allCases.map(\.rawValue))
        for entry in stored {
            if knownIDs.contains(entry) {
                converted.insert(entry)
            } else if let migrated = EggIndex.migrateLegacyRawValue(entry) {
                converted.insert(migrated)
                dirty = true
            }
        }
        if dirty {
            UserDefaults.standard.set(Array(converted), forKey: PrefsKey.easterEggsDiscovered)
        }
        return converted
    }

    /// Record discovery. Idempotent — subsequent triggers of the same egg
    /// don't re-fire the notification or repost the change.
    static func record(_ egg: EasterEgg) {
        guard cache.insert(egg.rawValue).inserted else { return }
        UserDefaults.standard.set(Array(cache), forKey: PrefsKey.easterEggsDiscovered)
        NotificationCenter.default.post(name: .easterEggDiscovered, object: nil)
        DiscoveryNotifier.notify(egg)
    }

    static func isDiscovered(_ egg: EasterEgg) -> Bool {
        cache.contains(egg.rawValue)
    }

    static var discoveredCount: Int { cache.count }
    static var totalCount: Int { EasterEgg.allCases.count }
}

extension Notification.Name {
    static let easterEggDiscovered = Notification.Name("mojito.easterEggDiscovered")
}
