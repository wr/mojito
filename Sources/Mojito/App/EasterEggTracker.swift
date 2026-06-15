import Foundation

/// Discoverable effects. Persisted ids are opaque (`k01`…) so neither the
/// binary nor the plist reveals which effects exist or their triggers.
/// User-facing strings have to render somewhere — but titles only leak
/// after discovery, and hints never quote the trigger word.
enum EasterEgg: String, CaseIterable, Identifiable {
    case k01
    case k02
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
    case k36
    case k37
    case k38
    case k39
    case k40
    case k41
    case k42
    case k43
    case k44
    case k45
    case k46
    case k47
    case k48
    case k49
    case k50
    case k51
    case k52
    case k53

    var id: String { rawValue }

    /// Shown once the egg has been discovered.
    var title: String {
        switch self {
        case .k01: return "Emoji rain"
        case .k02: return "Luck of the Draw"
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
        case .k36: return "First emoji"
        case .k37: return "100 emoji"
        case .k38: return "1,000 emoji"
        case .k39: return "10,000 emoji"
        case .k40: return "100,000 emoji"
        case .k41: return "1,000,000 emoji"
        case .k42: return "First symbol"
        case .k43: return "First GIF"
        case .k44: return "100 GIFs"
        case .k45: return "1,000 GIFs"
        case .k46: return "10,000 GIFs"
        case .k47: return "100,000 GIFs"
        case .k48: return "1,000,000 GIFs"
        case .k49: return "Wordle"
        case .k50: return "Disk Optimizer"
        case .k51: return "Last Call"
        case .k52: return "One more round..."
        case .k53: return "Joyless"
        }
    }

    /// Picker label to show once the egg is discovered.
    /// Decoded at runtime only on demand; non-picker eggs return `"???"` so callers
    /// have a safe fallback even if they look one up.
    var pickerLabel: String {
        switch self {
        case .k01: return String(EggStrings.k01.dropFirst().dropLast())
        case .k02: return String(EggStrings.k02.dropFirst().dropLast())
        case .k03: return String(EggStrings.k03.dropFirst().dropLast())
        case .k04: return EggStrings.k04Label
        case .k05: return EggStrings.k05Label
        case .k06: return String(EggStrings.k06.dropFirst().dropLast())
        case .k07: return String(EggStrings.k07.dropFirst().dropLast())
        case .k08: return String(EggStrings.k08.dropFirst().dropLast())
        case .k09: return String(EggStrings.k09.dropFirst().dropLast())
        case .k10: return String(EggStrings.k10.dropFirst().dropLast())
        case .k11: return String(EggStrings.k11.dropFirst().dropLast())
        case .k12: return String(EggStrings.k12.dropFirst().dropLast())
        case .k13: return String(EggStrings.k13.dropFirst().dropLast())
        case .k14: return String(EggStrings.k14.dropFirst().dropLast())
        case .k15: return String(EggStrings.k15.dropFirst().dropLast())
        case .k16: return String(EggStrings.k16.dropFirst().dropLast())
        case .k17: return String(EggStrings.k17.dropFirst().dropLast())
        case .k19: return String(EggStrings.k19.dropFirst().dropLast())
        case .k20: return String(EggStrings.k20.dropFirst().dropLast())
        case .k21: return String(EggStrings.k21.dropFirst().dropLast())
        case .k22: return String(EggStrings.k22.dropFirst().dropLast())
        case .k23: return String(EggStrings.k23.dropFirst().dropLast())
        case .k24: return String(EggStrings.k24.dropFirst().dropLast())
        case .k25: return String(EggStrings.k25.dropFirst().dropLast())
        case .k27: return String(EggStrings.k27.dropFirst().dropLast())
        case .k29: return String(EggStrings.k29.dropFirst().dropLast())
        case .k30: return String(EggStrings.k30.dropFirst().dropLast())
        case .k35: return String(EggStrings.k35.dropFirst().dropLast())
        case .k49: return String(EggStrings.k49.dropFirst().dropLast())
        case .k50: return String(EggStrings.k50.dropFirst().dropLast())
        default:   return "???"
        }
    }

    /// Shown next to a discovered egg in About — spells out the trigger.
    /// Backticked keywords decode from `EggStrings` so they're not
    /// plaintext spoilers in the source.
    var detail: String {
        switch self {
        case .k01: return "`\(EggStrings.k01)` — the house special."
        case .k02: return "`\(EggStrings.k02)` — leave it to chance."
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
        case .k36: return "Your very first autocomplete. Welcome aboard."
        case .k37: return "100 emoji autocompleted. Getting the hang of this."
        case .k38: return "1,000 emoji autocompleted. Showing real commitment."
        case .k39: return "10,000 emoji autocompleted. This is your life now."
        case .k40: return "100,000 emoji autocompleted. Are you okay?"
        case .k41: return "1,000,000 emoji autocompleted. Beyond reason."
        case .k42: return "Inserted a symbol via `::name:`."
        case .k43: return "Inserted your first GIF via `:::`."
        case .k44: return "100 GIFs inserted. Reactions only."
        case .k45: return "1,000 GIFs inserted. The thread is mostly GIFs now."
        case .k46: return "10,000 GIFs inserted. Words are obsolete."
        case .k47: return "100,000 GIFs inserted. Truly unhinged."
        case .k48: return "1,000,000 GIFs inserted. A new form of communication."
        case .k49: return "`\(EggStrings.k49)` — six guesses, one word."
        case .k50: return "`\(EggStrings.k50)` — tidying clusters, one seek at a time."
        case .k51: return "Solve the word, then survive the bonus round."
        case .k52: return "Manually clicked Check for Updates."
        case .k53: return "You turned easter eggs off. The irony is noted."
        }
    }

    /// Subtle nudge shown next to an *undiscovered* egg. Oblique by design.
    var hint: String {
        switch self {
        case .k01: return "Rum, mint, lime, soda."
        case .k02: return "Can't decide? Let fate pick."
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
        case .k36: return "Every journey begins with a single keystroke."
        case .k37: return "Keep typing."
        case .k38: return "A thousand of anything is a lot."
        case .k39: return "Five digits' worth."
        case .k40: return "Six digits' worth."
        case .k41: return "Seven digits' worth."
        case .k42: return "There's more than emoji in here."
        case .k43: return "Three colons in a row."
        case .k44: return "Reactions, reactions, reactions."
        case .k45: return "The thread is mostly GIFs now."
        case .k46: return "Words are obsolete."
        case .k47: return "Truly unhinged."
        case .k48: return "A new form of communication."
        case .k49: return "Green, yellow, gray — six tries."
        case .k50: return "Those little colored blocks, all out of order."
        case .k51: return "Solve it to see what comes next."
        case .k52: return "Ask for a fresh mojito?"
        case .k53: return "Sometimes you just want them gone."
        }
    }

    var emojiGlyph: String? {
        switch self {
        case .k01: return "🎁"
        case .k02: return "🎲"
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
        case .k36: return "🎉"
        case .k37: return "💯"
        case .k38: return "🏆"
        case .k39: return "🚀"
        case .k40: return "🌟"
        case .k41: return "👑"
        case .k42: return "⌘"
        case .k43: return "🎞️"
        case .k44: return "🎬"
        case .k45: return "📽️"
        case .k46: return "🍿"
        case .k47: return "🎥"
        case .k48: return "🏅"
        case .k49: return "🟩"
        case .k50: return "💽"
        case .k51: return "🍹"
        case .k52: return "🍸"
        case .k53: return "🫥"
        }
    }

    /// Chained eggs are hidden in Settings until their prereq is found,
    /// so the list grows as the user works through the tier.
    var prerequisite: EasterEgg? {
        switch self {
        case .k37: return .k36
        case .k38: return .k37
        case .k39: return .k38
        case .k40: return .k39
        case .k41: return .k40
        case .k44: return .k43
        case .k45: return .k44
        case .k46: return .k45
        case .k47: return .k46
        case .k48: return .k47
        case .k51: return .k49
        default:   return nil
        }
    }

    var discoveryEffect: DiscoveryEffect {
        switch self {
        case .k37, .k38, .k39, .k40, .k41,
             .k44, .k45, .k46, .k47, .k48:
            return .confettiSilent
        case .k53:
            return .silent
        default:
            return .standard
        }
    }
}

/// What plays when an egg is first discovered.
enum DiscoveryEffect {
    /// Keyword-triggered eggs and first-tier achievements: banner + fanfare.
    case standard
    /// Count-milestone achievements: banner + confetti shower, no fanfare.
    case confettiSilent
    /// Adds nothing to the unconditional banner — no fanfare, no confetti.
    /// For the egg you get by turning eggs off, where a celebration would
    /// rather miss the point.
    case silent
}

/// Persists the set of discovered effects.
@MainActor
enum EasterEggTracker {
    /// Master switch (default on). When off, `record` drops every egg except
    /// the one triggered by disabling them. Trigger and effect sites consult
    /// this too, so disabled means no egg fires at all.
    static var eggsEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefsKey.eggsEnabled) as? Bool ?? true
    }

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
        // Disabled eggs can't be discovered; the sole exception is the one triggered by disabling them.
        guard eggsEnabled || egg == .k53 else { return }
        guard cache.insert(egg.rawValue).inserted else { return }
        UserDefaults.standard.set(Array(cache), forKey: PrefsKey.easterEggsDiscovered)
        // Feed the public community counter for genuine discoveries only;
        // auto-unlocked achievements are excluded.
        if !achievementSet.contains(egg) { TelemetryStore.recordEggDiscovery() }
        NotificationCenter.default.post(name: .easterEggDiscovered, object: nil)
        // In-app banner is the only discovery signal for now. The system
        // UNUserNotification path (DiscoveryNotifier) is suppressed — it
        // doubled up with the in-app banner and required a permission grant.
        AchievementBanner.show(egg)
        switch egg.discoveryEffect {
        case .standard:
            DiscoveryFanfare.play()
        case .confettiSilent:
            ConfettiRain.start()
        case .silent:
            break
        }
    }

    static func isDiscovered(_ egg: EasterEgg) -> Bool {
        cache.contains(egg.rawValue)
    }

    static var discoveredCount: Int { visibleCases.filter { isDiscovered($0) }.count }
    static var totalCount: Int { visibleCases.count }

    private static let achievements: [EasterEgg] = [
        .k36, .k37, .k38, .k39, .k40, .k41,
        .k42,
        .k43, .k44, .k45, .k46, .k47, .k48,
        .k52,
    ]
    private static let achievementSet: Set<EasterEgg> = Set(achievements)

    /// Eggs to surface in Settings: every egg whose prerequisite is met
    /// (or has none). Hidden milestones materialize as the chain unlocks.
    ///
    /// Milestone achievements lead — they're the newest additions and the
    /// ones the user is most likely actively chasing. Keyword eggs follow
    /// in their original declaration order, except a keyword egg gated behind
    /// another keyword egg is lifted to sit directly beneath its parent.
    static var visibleCases: [EasterEgg] {
        let keywords = EasterEgg.allCases.filter { !achievementSet.contains($0) }
        let visible = (achievements + keywords).filter { egg in
            guard let prereq = egg.prerequisite else { return true }
            return isDiscovered(prereq)
        }
        return reorderChildKeywords(visible)
    }

    /// `true` when this egg's prerequisite is another keyword egg rather than
    /// a milestone achievement. Drives the Settings sub-row indentation.
    static func isChildKeyword(_ egg: EasterEgg) -> Bool {
        guard let prereq = egg.prerequisite else { return false }
        return !achievementSet.contains(prereq)
    }

    /// Lifts each keyword egg that's gated behind another keyword egg to sit
    /// immediately after its parent, so the pair reads as parent → child in
    /// the flat Settings list. Pure over the already-filtered input.
    static func reorderChildKeywords(_ eggs: [EasterEgg]) -> [EasterEgg] {
        var ordered = eggs
        for egg in eggs where isChildKeyword(egg) {
            guard let parent = egg.prerequisite,
                  let parentIdx = ordered.firstIndex(of: parent),
                  let childIdx = ordered.firstIndex(of: egg),
                  childIdx != parentIdx + 1 else { continue }
            ordered.remove(at: childIdx)
            let insertIdx = ordered.firstIndex(of: parent)! + 1
            ordered.insert(egg, at: insertIdx)
        }
        return ordered
    }

    /// Writes empty values (not `removeObject`) so the dev build's
    /// release-domain fallback can't resurrect the cleared state. See
    /// `clearUsageStats`.
    static func reset() {
        cache.removeAll()
        UserDefaults.standard.set([String](), forKey: PrefsKey.easterEggsDiscovered)
        UserDefaults.standard.removeObject(forKey: PrefsKey.perfectBounceCount)
        UserDefaults.standard.set(0, forKey: PrefsKey.totalEmojiInserted)
        UserDefaults.standard.set(0, forKey: PrefsKey.totalSymbolInserted)
        UserDefaults.standard.set(0, forKey: PrefsKey.totalGifInserted)
        NotificationCenter.default.post(name: .easterEggDiscovered, object: nil)
    }
}

extension Notification.Name {
    static let easterEggDiscovered = Notification.Name("mojito.easterEggDiscovered")
}
