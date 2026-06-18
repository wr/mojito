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
        config.symbols.enabled = true
        config.gif.open = ";;;"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TriggerConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test func decodingLegacyBlobWithCloseKeyIgnoresIt() throws {
        // Synthesized Codable drops unknown keys, so a pre-redesign blob that
        // still carries `close` decodes cleanly into the open-only model.
        let legacy = """
        {"emoji":{"mode":"emoji","open":":","close":":","enabled":true},
         "symbols":{"mode":"symbols","open":"::","close":":","enabled":false},
         "gif":{"mode":"gif","open":":::","enabled":true},
         "quickAccess":{"mode":"quickAccess","open":":?","enabled":true}}
        """
        let decoded = try JSONDecoder().decode(TriggerConfig.self, from: Data(legacy.utf8))
        #expect(decoded == .default)
    }

    // MARK: save / load

    @Test func saveThenLoadReturnsSameConfig() {
        let suite = freshSuite()
        var config = TriggerConfig.default
        config.symbols.enabled = true
        config.normalize()  // quickAccess.open is derived; load/save re-derive it
        TriggerConfigStore.save(config, defaults: suite)
        #expect(TriggerConfigStore.load(defaults: suite) == config)
    }

    @Test func saveNormalizesQuickAccessOpenToFollowEmoji() {
        let suite = freshSuite()
        var config = TriggerConfig.default
        config.emoji.open = "::"
        // quickAccess.open left stale on purpose — save must re-derive it.
        config.quickAccess.open = ":?"
        TriggerConfigStore.save(config, defaults: suite)
        #expect(TriggerConfigStore.load(defaults: suite).quickAccess.open == "::?")
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
        #expect(config.emoji == Trigger(mode: .emoji, open: ":", enabled: true))
        #expect(config.symbols == Trigger(mode: .symbols, open: "::", enabled: false))
        #expect(config.gif == Trigger(mode: .gif, open: ":::", enabled: true))
        #expect(config.quickAccess == Trigger(mode: .quickAccess, open: ":?", enabled: true))
    }

    @Test func symbolsTriggerDefaultsOff() {
        #expect(TriggerConfig.default.symbols.enabled == false)
    }

    @Test func migrationMapsSymbolsTriggerFromLegacyEnableAlone() {
        // The old requireDoubleColon distinction is gone — legacy symbolsEnabled
        // maps straight onto the symbols trigger.
        let on = freshSuite()
        on.set(true, forKey: PrefsKey.symbolsEnabled)
        #expect(TriggerConfigStore.load(defaults: on).symbols.enabled == true)

        let off = freshSuite()
        off.set(false, forKey: PrefsKey.symbolsEnabled)
        #expect(TriggerConfigStore.load(defaults: off).symbols.enabled == false)
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

    // MARK: quickAccess normalization

    @Test func normalizeSetsQuickAccessOpenToEmojiOpenPlusQuestion() {
        var config = TriggerConfig.default
        #expect(config.quickAccess.open == ":?")
        config.emoji.open = "::"
        config.normalize()
        #expect(config.quickAccess.open == "::?")
        // Tracks further emoji changes.
        config.emoji.open = ";"
        config.normalize()
        #expect(config.quickAccess.open == ";?")
    }
}
