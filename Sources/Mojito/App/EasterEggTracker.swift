import Foundation

/// Discoverable effects. Persisted ids are opaque (`k01`…) so neither the
/// binary nor the plist reveals which effects exist or their triggers.
/// User-facing strings have to render somewhere — but titles only leak
/// after discovery, and hints never quote the trigger word.
enum EasterEgg: String, CaseIterable, Identifiable {
    case k01
    case k03
    case k04
    case k05
    case k06
    case k07
    case k08
    case k09
    case k10
    case k11
    case k12
    case k13
    case k14
    case k15
    case k16
    case k17
    case k31
    case k19
    case k99
    case k20
    case k21
    case k22
    case k23
    case k24
    case k25
    case k27
    case k28
    case k29
    case k30
    case k32
    case k33
    case k34
    case k35

    var id: String { rawValue }

    /// Shown once the egg has been discovered.
    var title: String {
        switch self {
        case .k01: return "Emoji rain"
        case .k03: return "Moof!"
        case .k04: return "Confetti shower"
        case .k05: return "Pride wave"
        case .k06: return "Sosumi"
        case .k07: return "Floppy disk"
        case .k08: return "Dial-up"
        case .k09: return "Wilhelm scream"
        case .k10: return "Snowfall"
        case .k11: return "The Matrix"
        case .k12: return "Fireworks"
        case .k13: return "Trogdor!"
        case .k14: return "The Hatch"
        case .k15: return "Warp Drive"
        case .k16: return "Flying Toasters"
        case .k17: return "Bouncing DVD"
        case .k31: return "Perfect Bounce"
        case .k19: return "Blue Screen"
        case .k99: return "Konami Code"
        case .k20: return "Snake"
        case .k21: return "Global Thermonuclear War"
        case .k22: return "My leg!"
        case .k23: return "Ta-da!"
        case .k24: return "Bliss"
        case .k25: return "Solitaire Win"
        case .k27: return "Rickroll"
        case .k28: return "Night Owl"
        case .k29: return "CRT Power Off"
        case .k30: return "Celery Man"
        case .k32: return "Pi Day"
        case .k33: return "Merry Mojito"
        case .k34: return "Spooky Season"
        case .k35: return "Train Game"
        }
    }

    /// Shown next to a discovered egg in About — spells out the trigger.
    /// Backticked keywords decode from `EggStrings` so they're not
    /// plaintext spoilers in the source.
    var detail: String {
        switch self {
        case .k01: return "`\(EggStrings.k01)` — the house special."
        case .k03: return "`\(EggStrings.k03)` — Clarus the dogcow."
        case .k04: return "`\(EggStrings.k04)` — small victories."
        case .k05: return "`\(EggStrings.k05)` — every June, all year."
        case .k06: return "`\(EggStrings.k06)` — System 7's last word."
        case .k07: return "`\(EggStrings.k07)` — the sound of saving."
        case .k08: return "`\(EggStrings.k08)` — the handshake."
        case .k09: return "`\(EggStrings.k09)` — Hollywood's loudest hand-me-down."
        case .k10: return "`\(EggStrings.k10)` — a quiet snowfall."
        case .k11: return "`\(EggStrings.k11)` — wake up, Neo."
        case .k12: return "`\(EggStrings.k12)` — Roman candles, indoors."
        case .k13: return "`\(EggStrings.k13)` — burninate."
        case .k14: return "`\(EggStrings.k14)` — 4 8 15 16 23 42."
        case .k15: return "`\(EggStrings.k15)` — punch it."
        case .k16: return "`\(EggStrings.k16)` — bread on the wing."
        case .k17: return "`\(EggStrings.k17)` — please let it hit the corner."
        case .k31: return "the corner. Finally."
        case .k19: return "`\(EggStrings.k19)` — press any key to continue."
        case .k99: return "Type `:` then ↑↑↓↓←→←→BA."
        case .k20: return "`\(EggStrings.k20)` — eat. grow. wrap."
        case .k21: return "`\(EggStrings.k21)` — shall we play a game?"
        case .k22: return "`\(EggStrings.k22)` — yelled by a fry cook in Bikini Bottom."
        case .k23: return "`\(EggStrings.k23)` — that little victory chime."
        case .k24: return "`\(EggStrings.k24)` — to begin, click your user name."
        case .k25: return "`\(EggStrings.k25)` — the cards cascade once more."
        case .k27: return "`\(EggStrings.k27)` — you should know better."
        case .k28: return "`\(EggStrings.k28)` — only after dark."
        case .k29: return "`\(EggStrings.k29)` — *thunk*. Lights out."
        case .k30: return "`\(EggStrings.k30)` — good morning, Paul."
        case .k32: return "`\(EggStrings.k32)` — 3.14, once a year."
        case .k33: return "`\(EggStrings.k33)` — ho ho ho."
        case .k34: return "`\(EggStrings.k34)` — trick or treat."
        case .k35: return "`\(EggStrings.k35)` — MY train goes from here... to here?"
        }
    }

    /// Subtle nudge shown next to an *undiscovered* egg. Oblique by design.
    var hint: String {
        switch self {
        case .k01: return "Rum, mint, lime, soda."
        case .k03: return "Clarus the dogcow goes..."
        case .k04: return "Celebrate a little victory."
        case .k05: return "Castro Street, 1978."
        case .k06: return "Apple v. Apple"
        case .k07: return "Don't copy."
        case .k08: return "1000 hours free!"
        case .k09: return "A painful film trope."
        case .k10: return "There's a chill in the air..."
        case .k11: return "Wake up."
        case .k12: return "The Fourth, indoors."
        case .k13: return "Consummate V's, and a beefy arm."
        case .k14: return "108 minutes."
        case .k15: return "Engage."
        case .k16: return "After dark, with wings."
        case .k17: return "It has to hit the corner eventually."
        case .k31: return "Some things require patience."
        case .k19: return "A Windows inevitability."
        case .k99: return "Up, up..."
        case .k20: return "AAA mobile gaming circa 1997."
        case .k21: return "How about a nice game of chess?"
        case .k22: return "Ow!"
        case .k23: return "Welcome to 3.1!"
        case .k24: return "Bliss."
        case .k25: return "You're all alone on this one."
        case .k27: return "We're no strangers."
        case .k28: return "Up past your bedtime?"
        case .k29: return "The tube."
        case .k30: return "I've got a BETA sequence I've been working on..."
        case .k32: return "March 14, the day of..."
        case .k33: return "December's main event."
        case .k34: return "October 31st only."
        case .k35: return "MY train..."
        }
    }

    var emojiGlyph: String? {
        switch self {
        case .k01: return "🎁"
        case .k03: return nil
        case .k04: return "🎊"
        case .k05: return "🏳️‍🌈"
        case .k06: return "🔔"
        case .k07: return "💾"
        case .k08: return "📞"
        case .k09: return "🎬"
        case .k10: return "❄️"
        case .k11: return "🟢"
        case .k12: return "🎆"
        case .k13: return "🐉"
        case .k14: return "🏝️"
        case .k15: return "🛸"
        case .k16: return "🍞"
        case .k17: return "💿"
        case .k31: return "🎯"
        case .k19: return "🟦"
        case .k99: return "🕹️"
        case .k20: return "🐍"
        case .k21: return "☢️"
        case .k22: return "🦵"
        case .k23: return "🎉"
        case .k24: return "🪟"
        case .k25: return "🃏"
        case .k27: return "🎤"
        case .k28: return "🌙"
        case .k29: return "📺"
        case .k30: return "🥬"
        case .k32: return "🥧"
        case .k33: return "🎄"
        case .k34: return "🎃"
        case .k35: return "🚋"
        }
    }
}

/// Persists the set of discovered effects.
@MainActor
enum EasterEggTracker {
    /// One-time migration on first read: pre-obfuscation builds stored
    /// plain raw values; we hash those against `EggIndex` and rewrite to
    /// opaque ids. Legacy strings live only inside
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

    /// Idempotent — re-triggers don't re-notify.
    static func record(_ egg: EasterEgg) {
        guard cache.insert(egg.rawValue).inserted else { return }
        UserDefaults.standard.set(Array(cache), forKey: PrefsKey.easterEggsDiscovered)
        NotificationCenter.default.post(name: .easterEggDiscovered, object: nil)
        // In-app banner is the only discovery signal for now. The system
        // UNUserNotification path (DiscoveryNotifier) is suppressed — it
        // doubled up with the in-app banner and required a permission grant.
        AchievementBanner.show(egg)
        DiscoveryFanfare.play()
    }

    static func isDiscovered(_ egg: EasterEgg) -> Bool {
        cache.contains(egg.rawValue)
    }

    static var discoveredCount: Int { cache.count }
    static var totalCount: Int { EasterEgg.allCases.count }

    /// Writes an empty array (not `removeObject`) so the dev build's
    /// release-domain fallback can't resurrect the set. See `clearUsageStats`.
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
