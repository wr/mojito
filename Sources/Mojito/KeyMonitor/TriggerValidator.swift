import Foundation

/// A single problem (or hint) found with one trigger. The Settings panel
/// renders the icon by `severity` and shows `message` inline.
struct TriggerDiagnostic: Equatable {
    enum Severity { case error, warning, note }
    let severity: Severity
    let message: String
}

/// Pure analysis of a `TriggerConfig`, powering the inline `(!)` markers in
/// Settings ▸ Triggers. Returns at most one diagnostic per mode (the most
/// severe), so the UI never stacks badges on a single row. No AppKit — fully
/// unit-testable.
enum TriggerValidator {
    static func diagnostics(for rawConfig: TriggerConfig) -> [TriggerMode: TriggerDiagnostic] {
        // Quick Access's open is derived from the emoji open, so collisions /
        // shadows must be checked against the resolved value.
        var config = rawConfig
        config.normalize()
        var result: [TriggerMode: TriggerDiagnostic] = [:]

        // emoji is always live (no enable toggle); the rest must be enabled
        // with a non-empty open to be in play. An empty-open *non-emoji*
        // trigger is just "disabled", not an error. Symbols set to follow emoji
        // isn't a standalone opener (it blends into emoji results, and its open
        // mirrors emoji's after normalize), so it can't collide — drop it.
        let candidates: [Trigger] = config.all.filter { t in
            if t.mode == .symbols, config.symbolsFollowEmoji { return false }
            return t.mode == .emoji || (t.enabled && !t.open.isEmpty)
        }
        // Triggers that can actually fire and contribute collisions/shadows.
        let active = candidates.filter { !$0.open.isEmpty }

        // --- error: emoji needs a trigger ---
        if config.emoji.open.isEmpty {
            result[.emoji] = TriggerDiagnostic(
                severity: .error,
                message: String(localized: "Emoji needs a trigger"))
        }

        // --- error: two enabled triggers share an identical open ---
        for t in active where result[t.mode] == nil {
            if let other = active.first(where: { $0.mode != t.mode && $0.open == t.open }) {
                result[t.mode] = TriggerDiagnostic(
                    severity: .error,
                    message: String(localized: "Same as \(displayName(other.mode)) — pick distinct triggers"))
            }
        }

        // --- error: shadowed by a no-query trigger that fires first ---
        // gif / quickAccess open a sticky UI the moment their open is typed,
        // so any longer trigger whose open starts with that prefix is
        // unreachable.
        let blockingPrefixes: [(open: String, mode: TriggerMode)] = active
            .filter { $0.mode == .gif || $0.mode == .quickAccess }
            .map { ($0.open, $0.mode) }
        for t in active where result[t.mode] == nil {
            if let prefix = blockingPrefixes.first(where: { $0.mode != t.mode
                && t.open != $0.open
                && t.open.hasPrefix($0.open) }) {
                result[t.mode] = TriggerDiagnostic(
                    severity: .error,
                    message: String(localized: "‘\(prefix.open)’ fires first, so this never triggers"))
            }
        }

        // --- warning: risky letters / digits / whitespace ---
        for t in active where result[t.mode] == nil {
            if t.open.contains(where: \.isWhitespace) {
                result[t.mode] = TriggerDiagnostic(
                    severity: .warning,
                    message: String(localized: "Spaces in a trigger are error-prone"))
            } else if t.open.contains(where: { $0.isLetter || $0.isNumber }) {
                result[t.mode] = TriggerDiagnostic(
                    severity: .warning,
                    message: String(localized: "Letters can fire inside words like ‘gift’ — punctuation is safer"))
            }
        }

        // --- note: colon emoticons need a `:`-prefixed trigger ---
        // `:)` / `:D` ride the emoji-capture path, which only exists while a
        // `:` can open a capture. If nothing active starts with `:`, surface
        // it on the emoji row (unless that row already has a louder problem).
        let anyColonTrigger = active.contains { $0.open.first == ":" }
        if !anyColonTrigger, result[.emoji] == nil {
            result[.emoji] = TriggerDiagnostic(
                severity: .note,
                message: String(localized: "Colon emoticons (:) :D) won’t fire without a `:` trigger"))
        }

        return result
    }

    private static func displayName(_ mode: TriggerMode) -> String {
        switch mode {
        case .emoji:       return String(localized: "Emoji")
        case .symbols:     return String(localized: "Symbols")
        case .gif:         return String(localized: "GIF")
        case .quickAccess: return String(localized: "Quick access")
        }
    }
}
