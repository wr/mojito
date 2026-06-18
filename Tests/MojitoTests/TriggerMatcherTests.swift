import Testing
@testable import Mojito

/// Pure lookup behavior of `TriggerMatcher` over a `TriggerConfig`. The
/// capture lifecycle that consumes these lookups is exercised in
/// `TriggerStateMachineTests`.
struct TriggerMatcherTests {

    private func chars(_ s: String) -> [Character] { Array(s) }

    // MARK: default config (`:` `::` `:::` `:?`, symbols off by default)

    @Test func defaultColonOpensEmojiAndCanExtend() {
        let m = TriggerMatcher(config: .default)
        #expect(m.terminalMode(for: chars(":")) == .emoji)
        // `:` can grow into `:::` / `:?` (symbols is off by default).
        #expect(m.canExtend(chars(":")) == true)
        #expect(m.isViablePrefix(chars(":")) == true)
    }

    @Test func defaultTripleColonIsGifAndTerminal() {
        let m = TriggerMatcher(config: .default)
        #expect(m.terminalMode(for: chars(":::")) == .gif)
        #expect(m.canExtend(chars(":::")) == false)
    }

    @Test func defaultQuickAccessOpenIsTwoChars() {
        let m = TriggerMatcher(config: .default)
        #expect(m.terminalMode(for: chars(":?")) == .quickAccess)
        #expect(m.canExtend(chars(":?")) == false)
    }

    @Test func defaultNonDelimiterIsNotViable() {
        let m = TriggerMatcher(config: .default)
        #expect(m.isViablePrefix(chars(":f")) == false)
        #expect(m.terminalMode(for: chars(":f")) == nil)
    }

    @Test func defaultEmojiCloseIsSingleColon() {
        let m = TriggerMatcher(config: .default)
        #expect(m.close(for: .emoji) == chars(":"))
        #expect(m.close(for: .gif) == nil)         // gif has no typed close
        #expect(m.close(for: .quickAccess) == nil)
    }

    @Test func defaultSymbolsDisabledSoNotTerminal() {
        // Symbols is disabled by default → `::` resolves to nothing terminal,
        // but is still a viable prefix on the way to `:::`.
        let m = TriggerMatcher(config: .default)
        #expect(m.terminalMode(for: chars("::")) == nil)
        #expect(m.canExtend(chars("::")) == true)   // `:::`
    }

    @Test func defaultColonStartsATrigger() {
        #expect(TriggerMatcher(config: .default).colonStartsATrigger == true)
    }

    // MARK: symmetric `::emoji::` (the #71 case)

    @Test func symmetricDoubleColonOpenAndClose() {
        var cfg = TriggerConfig.default
        // Emoji open `::`; close mirrors the open → `::`.
        cfg.emoji = Trigger(mode: .emoji, open: "::", enabled: true)
        cfg.symbols = Trigger(mode: .symbols, open: "::", enabled: false)
        let m = TriggerMatcher(config: cfg)
        #expect(m.terminalMode(for: chars("::")) == .emoji)
        #expect(m.close(for: .emoji) == chars("::"))
        // A lone `:` is only a prefix now — never terminal.
        #expect(m.terminalMode(for: chars(":")) == nil)
        #expect(m.isViablePrefix(chars(":")) == true)
    }

    // MARK: custom / non-nested triggers

    @Test func nonNestedTriggersResolveIndependently() {
        var cfg = TriggerConfig.default
        cfg.gif = Trigger(mode: .gif, open: ";", enabled: true)
        let m = TriggerMatcher(config: cfg)
        #expect(m.terminalMode(for: chars(";")) == .gif)
        #expect(m.canExtend(chars(";")) == false)
        // `:` is unaffected.
        #expect(m.terminalMode(for: chars(":")) == .emoji)
    }

    @Test func disabledTriggerIsInert() {
        var cfg = TriggerConfig.default
        cfg.gif = Trigger(mode: .gif, open: ":::", enabled: false)
        let m = TriggerMatcher(config: cfg)
        #expect(m.terminalMode(for: chars(":::")) == nil)
        // With symbols off and gif off, `::` no longer extends anywhere.
        #expect(m.canExtend(chars("::")) == false)
    }

    @Test func blankOpenIsExcluded() {
        var cfg = TriggerConfig.default
        cfg.symbols = Trigger(mode: .symbols, open: "", enabled: true)
        let m = TriggerMatcher(config: cfg)
        // Empty open never participates even when enabled.
        #expect(m.isViablePrefix([]) == false || m.terminalMode(for: []) == nil)
        #expect(m.terminalMode(for: chars("")) == nil)
    }

    @Test func collisionResolvesByPrecedence() {
        // Two modes share an open string → emoji wins (earlier in `all`).
        var cfg = TriggerConfig.default
        cfg.emoji = Trigger(mode: .emoji, open: "##", enabled: true)
        cfg.symbols = Trigger(mode: .symbols, open: "##", enabled: true)
        let m = TriggerMatcher(config: cfg)
        #expect(m.terminalMode(for: chars("##")) == .emoji)
    }

    @Test func customColonlessConfigReportsNoColonTrigger() {
        var cfg = TriggerConfig.default
        cfg.emoji = Trigger(mode: .emoji, open: ";", enabled: true)
        cfg.gif = Trigger(mode: .gif, open: ";;;", enabled: true)
        cfg.quickAccess = Trigger(mode: .quickAccess, open: ";?", enabled: true)
        // symbols disabled by default; nothing starts with `:`.
        let m = TriggerMatcher(config: cfg)
        #expect(m.colonStartsATrigger == false)
    }
}
