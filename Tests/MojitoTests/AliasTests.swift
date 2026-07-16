import Testing
import Foundation
@testable import Mojito

/// Custom shortcut (alias) storage + validation.
@MainActor
struct AliasStoreTests {
    private func makeStore() -> AliasStore {
        let suite = UserDefaults(suiteName: "mojito.tests.alias.\(UUID().uuidString)")!
        return AliasStore(defaults: suite)
    }

    @Test func startsEmpty() {
        #expect(makeStore().aliases.isEmpty)
    }

    @Test func addNormalizesAndStores() {
        let store = makeStore()
        #expect(store.add(alias: "  Check  ", hexcode: "2705") == .added)
        #expect(store.aliases.count == 1)
        #expect(store.aliases[0].alias == "check")   // trimmed + lowercased
        #expect(store.aliases[0].hexcode == "2705")
        #expect(store.contains(alias: "CHECK"))
    }

    @Test func rejectsInvalidAliases() {
        let store = makeStore()
        #expect(store.add(alias: "", hexcode: "2705") == .invalid)
        #expect(store.add(alias: "   ", hexcode: "2705") == .invalid)
        #expect(store.add(alias: "a b", hexcode: "2705") == .invalid)   // whitespace
        #expect(store.add(alias: "a:b", hexcode: "2705") == .invalid)   // colon
        #expect(store.add(alias: String(repeating: "x", count: 41), hexcode: "2705") == .invalid)
        #expect(store.add(alias: "ok", hexcode: "") == .invalid)        // no target
        #expect(store.aliases.isEmpty)
    }

    @Test func repointingUpdatesInPlace() {
        let store = makeStore()
        store.add(alias: "check", hexcode: "2705")
        #expect(store.add(alias: "check", hexcode: "2714") == .updated)
        #expect(store.aliases.count == 1)
        #expect(store.aliases[0].hexcode == "2714")
        // Re-adding the identical mapping is a no-op update, not a duplicate.
        #expect(store.add(alias: "check", hexcode: "2714") == .updated)
        #expect(store.aliases.count == 1)
    }

    @Test func removeAndRemoveAll() {
        let store = makeStore()
        store.add(alias: "check", hexcode: "2705")
        store.add(alias: "tick", hexcode: "2705")
        store.remove(alias: "CHECK")
        #expect(store.aliases.map(\.alias) == ["tick"])
        store.removeAll()
        #expect(store.aliases.isEmpty)
    }

    @Test func persistsAcrossInstances() {
        let suiteName = "mojito.tests.alias.persist.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let first = AliasStore(defaults: suite)
        first.add(alias: "check", hexcode: "2705")
        let second = AliasStore(defaults: suite)
        #expect(second.aliases.count == 1)
        #expect(second.aliases[0].alias == "check")
        #expect(second.aliases[0].hexcode == "2705")
    }

    @Test func sanitizeDropsInvalidAndDuplicate() {
        let cleaned = AliasStore.sanitize([
            CustomAlias(alias: "Check", hexcode: "2705"),
            CustomAlias(alias: "check", hexcode: "2714"),   // dupe (first wins)
            CustomAlias(alias: "bad:one", hexcode: "1F600"), // invalid
            CustomAlias(alias: "ok", hexcode: ""),           // no target
        ])
        #expect(cleaned.map(\.alias) == ["check"])
        #expect(cleaned[0].hexcode == "2705")
    }
}

/// Merging aliases into the emoji index + ranking. Uses the pure
/// builders so it needs no bundle or shared singleton.
struct AliasIndexTests {
    private static let check = Emoji(hexcode: "E_CHECK", character: "✅", label: "white check mark",
                                     shortcodes: ["white_check_mark"], tags: [], group: 0, order: 1)
    private static let flag = Emoji(hexcode: "E_FLAG", character: "🏁", label: "chequered flag",
                                    shortcodes: ["checkered_flag"], tags: [], group: 0, order: 2)
    private static let heavy = Emoji(hexcode: "E_HEAVY", character: "✔️", label: "heavy check mark",
                                     shortcodes: ["heavy_check_mark"], tags: [], group: 0, order: 3)
    private static let corpus = [check, flag, heavy]

    private func build(_ aliases: [CustomAlias]) -> EmojiDatabase.IndexResult {
        EmojiDatabase.buildIndex(emojis: Self.corpus, aliases: aliases, activeLocales: [])
    }

    @Test func aliasResolvesAndOverrides() {
        let result = build([CustomAlias(alias: "check", hexcode: "E_CHECK")])
        // Typable exact match (`:check:`).
        #expect(result.byShortcode["check"]?.hexcode == "E_CHECK")
        // Built-in shortcodes are untouched.
        #expect(result.byShortcode["white_check_mark"]?.hexcode == "E_CHECK")
        #expect(result.byShortcode["checkered_flag"]?.hexcode == "E_FLAG")
    }

    @Test func aliasHaystackIsFlagged() {
        let result = build([CustomAlias(alias: "check", hexcode: "E_CHECK")])
        let checkRow = result.indexed.first { $0.emoji.hexcode == "E_CHECK" }
        let aliasHay = checkRow?.haystacks.first { $0.isAlias }
        #expect(aliasHay?.display == "check")
        // No other emoji picked up the alias haystack.
        #expect(result.indexed.filter { $0.haystacks.contains { $0.isAlias } }.count == 1)
    }

    @Test func aliasOverridesBuiltinSpelling() {
        // Alias "checkered_flag" (a real built-in for 🏁) re-pointed at ✅ wins.
        let result = build([CustomAlias(alias: "checkered_flag", hexcode: "E_CHECK")])
        #expect(result.byShortcode["checkered_flag"]?.hexcode == "E_CHECK")
    }

    @Test func aliasToUnknownEmojiIgnored() {
        let result = build([CustomAlias(alias: "nope", hexcode: "DOES_NOT_EXIST")])
        #expect(result.byShortcode["nope"] == nil)
        #expect(result.indexed.allSatisfy { !$0.haystacks.contains { $0.isAlias } })
    }

    @Test func aliasCanTargetSymbol() {
        // ⌘ lives in SymbolsDatabase (hexcode "SYM_cmd"), not the emoji corpus.
        let result = build([CustomAlias(alias: "apple", hexcode: "SYM_cmd")])
        #expect(result.byShortcode["apple"]?.character == "⌘")
        #expect(result.byHexcode["SYM_cmd"]?.character == "⌘")
        let row = result.indexed.first { $0.emoji.hexcode == "SYM_cmd" }
        #expect(row?.haystacks.contains { $0.isAlias && $0.display == "apple" } == true)
    }

    @Test func symbolAliasIsSearchable() {
        // A symbol alias becomes a first-class indexed row, so typing its term
        // surfaces the symbol even though it's not in the emoji corpus.
        let result = build([CustomAlias(alias: "apple", hexcode: "SYM_cmd")])
        #expect(rank("apple", result).first == "SYM_cmd")
    }

    private func rank(_ query: String, _ result: EmojiDatabase.IndexResult, usage: [String: Int] = [:]) -> [String] {
        FuzzyMatcher.rankedResults(
            needle: Array(query.lowercased()),
            pool: result.indexed,
            usage: usage,
            useFrequencyBoost: !usage.isEmpty,
            scanTags: query.count >= 2,
            limit: 12
        ).map(\.emoji.hexcode)
    }

    @Test func aliasedEmojiWinsItsTerm() {
        // Control: without an alias, only 🏁 (checkered_flag) prefix-matches "check".
        let control = rank("check", build([]))
        #expect(control.first == "E_FLAG")

        // With the alias, ✅ ranks first for "check".
        let aliased = rank("check", build([CustomAlias(alias: "check", hexcode: "E_CHECK")]))
        #expect(aliased.first == "E_CHECK")
    }

    @Test func aliasBeatsHeavilyUsedBuiltin() {
        // Even if 🏁 is maxed out on the frequency boost, the alias still wins.
        let result = build([CustomAlias(alias: "check", hexcode: "E_CHECK")])
        let ranked = rank("check", result, usage: ["E_FLAG": 100])
        #expect(ranked.first == "E_CHECK")
    }
}
