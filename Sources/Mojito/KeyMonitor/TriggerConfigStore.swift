import Foundation

/// Persistence for the user-editable `TriggerConfig`. Stores the config as
/// JSON under `PrefsKey.triggers`. On installs that predate the feature the
/// key is absent, so the first `load()` migrates the legacy per-feature prefs
/// into a config and persists it once — after that the JSON blob is canonical
/// and the legacy `symbolsRequireDoubleColon` / `quickAccessEnabled` keys are
/// read only during that one-time migration.
enum TriggerConfigStore {
    static func load(defaults: UserDefaults = .standard) -> TriggerConfig {
        if let data = defaults.data(forKey: PrefsKey.triggers),
           var config = try? JSONDecoder().decode(TriggerConfig.self, from: data) {
            // quickAccess.open follows the emoji open; re-derive on load so a
            // hand-edited or stale blob can't drift.
            config.normalize()
            return config
        }
        let migrated = migrate(from: defaults)
        save(migrated, defaults: defaults)
        return migrated
    }

    static func save(_ config: TriggerConfig, defaults: UserDefaults = .standard) {
        var config = config
        config.normalize()
        guard let data = try? JSONEncoder().encode(config) else { return }
        // Writing posts UserDefaults.didChangeNotification, which the Engine
        // observes → refreshPreferences() picks up the new config live.
        defaults.set(data, forKey: PrefsKey.triggers)
    }

    /// Reproduces the historical hardcoded triggers from the legacy prefs, so
    /// an existing install keeps behaving identically after the upgrade.
    private static func migrate(from defaults: UserDefaults) -> TriggerConfig {
        // Legacy symbols had two modes: `symbolsEnabled` gated the feature, and
        // `symbolsRequireDoubleColon` chose between a scoped `::` trigger and
        // blending symbols into the normal `:foo:` results. Map both onto the
        // new symbols trigger + `symbolsFollowEmoji`:
        //   enabled + requireDoubleColon → scoped (`::`, follow=false)
        //   enabled + !requireDoubleColon → blended (follow=true)
        //   !enabled → off
        let symbolsEnabled = defaults.object(forKey: PrefsKey.symbolsEnabled) as? Bool ?? true
        let requireDoubleColon = defaults.object(forKey: PrefsKey.symbolsRequireDoubleColon) as? Bool ?? false
        let symbolsFollowEmoji = symbolsEnabled && !requireDoubleColon
        let gifEnabled = defaults.object(forKey: PrefsKey.gifSearchEnabled) as? Bool ?? true
        let qaEnabled = defaults.object(forKey: PrefsKey.quickAccessEnabled) as? Bool ?? true

        var config = TriggerConfig(
            emoji:       Trigger(mode: .emoji,       open: ":",   enabled: true),
            symbols:     Trigger(mode: .symbols,     open: "::",  enabled: symbolsEnabled),
            gif:         Trigger(mode: .gif,         open: ":::", enabled: gifEnabled),
            quickAccess: Trigger(mode: .quickAccess, open: ":?",  enabled: qaEnabled),
            symbolsFollowEmoji: symbolsFollowEmoji
        )
        config.normalize()
        return config
    }
}
