import Foundation
import Testing
@testable import Mojito

/// Round-trip persistence and one-time legacy migration of `TriggerConfig`.
struct TriggerConfigStoreTests {

    private func freshSuite() -> UserDefaults {
        UserDefaults(suiteName: "mojito.tests.triggers.\(UUID().uuidString)")!
    }

    // MARK: Codable round-trip

    @Test func defaultIsStableThroughCodable() throws {
        let data = try JSONEncoder().encode(TriggerConfig.default)
        let decoded = try JSONDecoder().decode(TriggerConfig.self, from: data)
        #expect(decoded == .default)
    }

    @Test func customConfigRoundTrips() throws {
        var config = TriggerConfig.default
        config.emoji.open = ";"
        config.emoji.close = ";"
        config.symbols.enabled = true
        config.gif.open = ";;;"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TriggerConfig.self, from: data)
        #expect(decoded == config)
    }

    // MARK: save / load

    @Test func saveThenLoadReturnsSameConfig() {
        let suite = freshSuite()
        var config = TriggerConfig.default
        config.symbols.enabled = true
        config.quickAccess.open = ":!"
        TriggerConfigStore.save(config, defaults: suite)
        #expect(TriggerConfigStore.load(defaults: suite) == config)
    }

    @Test func loadPersistsMigratedConfigSoSecondLoadDecodes() {
        let suite = freshSuite()
        #expect(suite.data(forKey: PrefsKey.triggers) == nil)
        _ = TriggerConfigStore.load(defaults: suite)
        // Migration wrote the blob; the second load decodes it (no re-migrate).
        #expect(suite.data(forKey: PrefsKey.triggers) != nil)
        let again = TriggerConfigStore.load(defaults: suite)
        #expect(again == TriggerConfigStore.load(defaults: suite))
    }

    // MARK: migration from legacy prefs

    @Test func migrationOnEmptyDefaultsMatchesHistoricalDefault() {
        let suite = freshSuite()
        let config = TriggerConfigStore.load(defaults: suite)
        // No legacy prefs set → symbols trigger off, everything else default.
        #expect(config.emoji == Trigger(mode: .emoji, open: ":", close: ":", enabled: true))
        #expect(config.symbols == Trigger(mode: .symbols, open: "::", close: ":", enabled: false))
        #expect(config.gif == Trigger(mode: .gif, open: ":::", close: nil, enabled: true))
        #expect(config.quickAccess == Trigger(mode: .quickAccess, open: ":?", close: nil, enabled: true))
    }

    @Test func migrationEnablesSymbolsTriggerOnlyWhenBothLegacyPrefsSet() {
        // symbolsEnabled on but requireDoubleColon off → symbols trigger off.
        let a = freshSuite()
        a.set(true, forKey: PrefsKey.symbolsEnabled)
        a.set(false, forKey: PrefsKey.symbolsRequireDoubleColon)
        #expect(TriggerConfigStore.load(defaults: a).symbols.enabled == false)

        // Both on → symbols trigger on.
        let b = freshSuite()
        b.set(true, forKey: PrefsKey.symbolsEnabled)
        b.set(true, forKey: PrefsKey.symbolsRequireDoubleColon)
        #expect(TriggerConfigStore.load(defaults: b).symbols.enabled == true)

        // requireDoubleColon on but symbolsEnabled off → still off.
        let c = freshSuite()
        c.set(false, forKey: PrefsKey.symbolsEnabled)
        c.set(true, forKey: PrefsKey.symbolsRequireDoubleColon)
        #expect(TriggerConfigStore.load(defaults: c).symbols.enabled == false)
    }

    @Test func migrationMapsGifAndQuickAccessEnableFromLegacyPrefs() {
        let suite = freshSuite()
        suite.set(false, forKey: PrefsKey.gifSearchEnabled)
        suite.set(false, forKey: PrefsKey.quickAccessEnabled)
        let config = TriggerConfigStore.load(defaults: suite)
        #expect(config.gif.enabled == false)
        #expect(config.quickAccess.enabled == false)
    }

    @Test func existingBlobWinsOverLegacyPrefs() {
        let suite = freshSuite()
        // A persisted config with symbols enabled…
        var stored = TriggerConfig.default
        stored.symbols.enabled = true
        TriggerConfigStore.save(stored, defaults: suite)
        // …even though the legacy prefs would migrate to symbols off.
        suite.set(false, forKey: PrefsKey.symbolsEnabled)
        #expect(TriggerConfigStore.load(defaults: suite).symbols.enabled == true)
    }
}
