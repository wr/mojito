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
    case perfectBounce   = "k31"
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
        case .perfectBounce:   return "Perfect Bounce"
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
        }
    }

    /// Detail shown next to a discovered egg in the About panel. Spells
    /// out the trigger now that the user has found it. Trigger keywords
    /// are decoded from `EggStrings` at runtime so they don't appear as
    /// plaintext in the source — every reference between backticks below
    /// would otherwise be a free spoiler for anyone reading the repo.
    var detail: String {
        switch self {
        case .mojito:          return "`\(EggStrings.mojito)` — the house special."
        case .moof:            return "`\(EggStrings.moof)` — Clarus the dogcow."
        case .confetti:        return "`\(EggStrings.confetti)` — small victories."
        case .pride:           return "`\(EggStrings.pride)` — every June, all year."
        case .sosumi:          return "`\(EggStrings.sosumi)` — System 7's last word."
        case .floppy:          return "`\(EggStrings.floppy)` — the sound of saving."
        case .dialup:          return "`\(EggStrings.dialup)` — the handshake."
        case .wilhelm:         return "`\(EggStrings.wilhelm)` — Hollywood's loudest hand-me-down."
        case .snow:            return "`\(EggStrings.snow)` — a quiet snowfall."
        case .matrix:          return "`\(EggStrings.matrix)` — wake up, Neo."
        case .fireworks:       return "`\(EggStrings.fireworks)` — Roman candles, indoors."
        case .trogdor:         return "`\(EggStrings.trogdor)` — burninate."
        case .lost:            return "`\(EggStrings.lost)` — 4 8 15 16 23 42."
        case .toasters:        return "`\(EggStrings.toasters)` — bread on the wing."
        case .dvd:             return "`\(EggStrings.dvd)` — please let it hit the corner."
        case .perfectBounce:   return "the corner. Finally."
        case .bsod:            return "`\(EggStrings.bsod)` — press any key to continue."
        case .konami:          return "Type `:` then ↑↑↓↓←→←→BA."
        case .snake:           return "`\(EggStrings.snake)` — eat. grow. wrap."
        case .thermonuclear:   return "`\(EggStrings.thermonuclear)` — shall we play a game?"
        case .myleg:           return "`\(EggStrings.myleg)` — yelled by a fry cook in Bikini Bottom."
        case .tada:            return "`\(EggStrings.tada)` — that little victory chime."
        case .xp:              return "`\(EggStrings.xp)` — welcome back, Wells."
        case .solitaire:       return "`\(EggStrings.solitaire)` — the cards cascade once more."
        case .rickroll:        return "`\(EggStrings.rickroll)` — you should know better."
        case .crt:             return "`\(EggStrings.crt)` — *thunk*. Lights out."
        case .celery:          return "`\(EggStrings.celery)` — good morning, Paul."
        }
    }

    /// Subtle nudge shown next to an *undiscovered* egg. Oblique by design.
    var hint: String {
        switch self {
        case .mojito:          return "Rum, mint, lime, soda."
        case .moof:            return "Clarus the dogcow goes..."
        case .confetti:        return "Celebrate a little victory."
        case .pride:           return "Castro Street, 1978."
        case .sosumi:          return "Apple v. Apple"
        case .floppy:          return "Don't copy."
        case .dialup:          return "1000 hours free!"
        case .wilhelm:         return "A painful film trope."
        case .snow:            return "It won't be long before we'll all be there."
        case .matrix:          return "Wake up."
        case .fireworks:       return "The Fourth, indoors."
        case .trogdor:         return "Consummate V's, and a beefy arm."
        case .lost:            return "108 minutes."
        case .toasters:        return "After dark, with wings."
        case .dvd:             return "It has to hit the corner eventually."
        case .perfectBounce:   return "Some things require patience."
        case .bsod:            return "A Windows inevitability."
        case .konami:          return "Up, up..."
        case .snake:           return "AAA mobile gaming circa 1997."
        case .thermonuclear:   return "How about a nice game of chess?"
        case .myleg:           return "Ow!"
        case .tada:            return "Welcome to 3.1!"
        case .xp:              return "Bliss."
        case .solitaire:       return "You're all alone on this one."
        case .rickroll:        return "We're no strangers."
        case .crt:             return "The tube."
        case .celery:          return "I've got a BETA sequence I've been working on..."
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
        case .perfectBounce:   return "🎯"
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

    /// Wipes both the discovered-set and Perfect Bounce counter. Writes an
    /// empty array (not `removeObject`) for the same reason `clearUsageStats`
    /// does — the dev build registers the release domain as a fallback layer,
    /// so a removed key would resurrect from there.
    static func reset() {
        cache.removeAll()
        UserDefaults.standard.set([String](), forKey: PrefsKey.easterEggsDiscovered)
        UserDefaults.standard.removeObject(forKey: PrefsKey.perfectBounceCount)
        NotificationCenter.default.post(name: .easterEggDiscovered, object: nil)
    }
}

extension Notification.Name {
    static let easterEggDiscovered = Notification.Name("mojito.easterEggDiscovered")
}
