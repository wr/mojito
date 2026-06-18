import Testing
@testable import Mojito

/// Pure-logic checks for `TriggerValidator`. One diagnostic per mode, most
/// severe wins; disabled non-emoji triggers are ignored.
struct TriggerValidatorTests {

    @Test func cleanDefaultHasNoDiagnostics() {
        let diags = TriggerValidator.diagnostics(for: .default)
        #expect(diags.isEmpty)
    }

    @Test func emptyEmojiOpenIsError() {
        var config = TriggerConfig.default
        config.emoji.open = ""
        let diags = TriggerValidator.diagnostics(for: config)
        #expect(diags[.emoji]?.severity == .error)
    }

    @Test func collisionFlagsBothEnabledTriggers() {
        var config = TriggerConfig.default
        // Make symbols collide with the DERIVED quickAccess open (`:?`).
        config.symbols.enabled = true
        config.symbols.open = ":?"
        // quickAccess open follows emoji (`:` → `:?`), enabled.
        let diags = TriggerValidator.diagnostics(for: config)
        #expect(diags[.symbols]?.severity == .error)
        #expect(diags[.quickAccess]?.severity == .error)
    }

    @Test func disabledTriggerDoesNotCollide() {
        var config = TriggerConfig.default
        // symbols shares quickAccess open but is disabled → no collision.
        config.symbols.enabled = false
        config.symbols.open = ":?"
        let diags = TriggerValidator.diagnostics(for: config)
        #expect(diags[.symbols] == nil)
        #expect(diags[.quickAccess] == nil)
    }

    @Test func shadowedByNoQueryTriggerIsError() {
        // gif `;` (no-query) shadows emoji `;x` — `;` fires first.
        var config = TriggerConfig.default
        config.gif.open = ";"
        config.emoji.open = ";x"
        // Avoid the symbols extension muddying things.
        config.symbols.enabled = false
        let diags = TriggerValidator.diagnostics(for: config)
        #expect(diags[.emoji]?.severity == .error)
    }

    @Test func gifPrefixShadowsLongerTrigger() {
        // gif `;` (no-query) shadows symbols `;;`.
        var config = TriggerConfig.default
        config.gif.open = ";"
        config.symbols.enabled = true
        config.symbols.open = ";;"
        let diags = TriggerValidator.diagnostics(for: config)
        #expect(diags[.symbols]?.severity == .error)
    }

    @Test func letterTriggerIsWarning() {
        var config = TriggerConfig.default
        config.gif.open = "gif"
        let diags = TriggerValidator.diagnostics(for: config)
        #expect(diags[.gif]?.severity == .warning)
    }

    @Test func whitespaceTriggerIsWarning() {
        var config = TriggerConfig.default
        config.gif.open = ": "
        let diags = TriggerValidator.diagnostics(for: config)
        #expect(diags[.gif]?.severity == .warning)
    }

    @Test func colonEmoticonNoteWhenNothingUsesColon() {
        // Move emoji off `:` (quickAccess derives to `;?`) and ensure nothing
        // else uses `:`.
        var config = TriggerConfig.default
        config.emoji.open = ";"
        config.symbols.enabled = false
        config.gif.open = ";;;"
        let diags = TriggerValidator.diagnostics(for: config)
        #expect(diags[.emoji]?.severity == .note)
    }

    @Test func noColonNoteWhenSomethingStillUsesColon() {
        // emoji on `;` but gif still on `:::` → colon path alive.
        var config = TriggerConfig.default
        config.emoji.open = ";"
        config.symbols.enabled = false
        // gif stays ":::"
        let diags = TriggerValidator.diagnostics(for: config)
        #expect(diags[.emoji] == nil)
    }

    @Test func errorOutranksColonNoteOnEmoji() {
        // Empty emoji open (error) should win over the colon-emoticon note.
        var config = TriggerConfig.default
        config.emoji.open = ""
        config.symbols.enabled = false
        config.gif.open = ";;;"
        let diags = TriggerValidator.diagnostics(for: config)
        #expect(diags[.emoji]?.severity == .error)
    }
}
