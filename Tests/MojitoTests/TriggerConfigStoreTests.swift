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
        // The tolerant `init(from:)` drops unknown keys, so a pre-redesign blob
        // that still carries `close` decodes cleanly into the open-only model.
        let legacy = """
        {"emoji":{"mode":"emoji","open":":","close":":","enabled":true},
         "symbols":{"mode":"symbols","open":"::","close":":","enabled":false},
         "gif":{"mode":"gif","open":":::","enabled":true},
         "quickAccess":{"mode":"quickAccess","open":":?","enabled":true}}
        """
        let decoded = try JSONDecoder().decode(TriggerConfig.self, from: Data(legacy.utf8))
        #expect(decoded == .default)
    }

    @Test func blobMissingSymbolsFollowEmojiDefaultsTrue() throws {
        // A blob written before `symbolsFollowEmoji` existed must decode with it
        // defaulting true (and adding fields must never nuke the rest).
        let old = """
        {"emoji":{"mode":"emoji","open":":","enabled":true},
         "symbols":{"mode":"symbols","open":"::","enabled":true},
         "gif":{"mode":"gif","open":":::","enabled":true},
         "quickAccess":{"mode":"quickAccess","open":":?","enabled":true}}
        """
        let decoded = try JSONDecoder().decode(TriggerConfig.self, from: Data(old.utf8))
        #expect(decoded.symbolsFollowEmoji == true)
        #expect(decoded.symbols.enabled == true)
        #expect(decoded.emoji == TriggerConfig.default.emoji)
        #expect(decoded.gif == TriggerConfig.default.gif)
    }

    @Test func blobMissingEverythingDecodesToDefault() throws {
        // An empty object falls back to defaults for every field.
        let decoded = try JSONDecoder().decode(TriggerConfig.self, from: Data("{}".utf8))
        #expect(decoded == .default)
    }

    @Test func symbolsFollowEmojiDefaultsTrue() {
        #expect(TriggerConfig.default.symbolsFollowEmoji == true)
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

    @Test func migrationMapsSymbolsEnableOntoTrigger() {
        // Legacy symbolsEnabled gates the symbols trigger.
        let on = freshSuite()
        on.set(true, forKey: PrefsKey.symbolsEnabled)
        #expect(TriggerConfigStore.load(defaults: on).symbols.enabled == true)

        let off = freshSuite()
        off.set(false, forKey: PrefsKey.symbolsEnabled)
        #expect(TriggerConfigStore.load(defaults: off).symbols.enabled == false)
    }

    @Test func migrationMapsTwoLegacySymbolModes() {
        // enabled + requireDoubleColon → scoped (`::`, follow=false).
        let scoped = freshSuite()
        scoped.set(true, forKey: PrefsKey.symbolsEnabled)
        scoped.set(true, forKey: PrefsKey.symbolsRequireDoubleColon)
        let scopedCfg = TriggerConfigStore.load(defaults: scoped)
        #expect(scopedCfg.symbols.enabled == true)
        #expect(scopedCfg.symbolsFollowEmoji == false)
        #expect(scopedCfg.symbols.open == "::")

        // enabled + !requireDoubleColon → blended (follow=true), matching the
        // old "symbols mixed into normal results" behavior.
        let blended = freshSuite()
        blended.set(true, forKey: PrefsKey.symbolsEnabled)
        blended.set(false, forKey: PrefsKey.symbolsRequireDoubleColon)
        let blendedCfg = TriggerConfigStore.load(defaults: blended)
        #expect(blendedCfg.symbols.enabled == true)
        #expect(blendedCfg.symbolsFollowEmoji == true)

        // !enabled → off regardless of requireDoubleColon.
        let offSuite = freshSuite()
        offSuite.set(false, forKey: PrefsKey.symbolsEnabled)
        offSuite.set(true, forKey: PrefsKey.symbolsRequireDoubleColon)
        #expect(TriggerConfigStore.load(defaults: offSuite).symbols.enabled == false)
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

    @Test func normalizeAppendsQuestionToNonFollowQuickAccessOpen() {
        var config = TriggerConfig.default
        config.quickAccessFollowEmoji = false
        config.quickAccess.open = "#"
        config.normalize()
        #expect(config.quickAccess.open == "#?")
        // Idempotent — an open that already ends in `?` is left alone.
        config.normalize()
        #expect(config.quickAccess.open == "#?")
    }
}
