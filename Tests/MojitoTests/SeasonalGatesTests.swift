import Foundation
import Testing
@testable import Mojito

/// Date/time-gated egg routing. Tests the pure `evaluate` seam — no
/// banner / fanfare / UserDefaults side effects.
struct SeasonalGatesTests {

    // MARK: helpers

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        let comps = DateComponents(
            timeZone: cal.timeZone,
            year: y, month: m, day: d, hour: h, minute: min
        )
        return cal.date(from: comps)!
    }

    private static func emoji(_ shortcodes: [String]) -> Emoji {
        Emoji(
            hexcode: "0000",
            character: "?",
            label: "test",
            shortcodes: shortcodes,
            tags: [],
            group: 0,
            order: 0
        )
    }

    // MARK: pi day (March 14)

    @Test func piDayFiresAtMidnightStart() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["pie"]),
            now: Self.date(2026, 3, 14, 0, 0),
            calendar: Self.cal
        )
        #expect(result == .k32)
    }

    @Test func piDayDoesNotFireOnMarch13EndOfDay() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["pie"]),
            now: Self.date(2026, 3, 13, 23, 59),
            calendar: Self.cal
        )
        #expect(result == nil)
    }

    @Test func piDayDoesNotFireOnMarch15() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["pie"]),
            now: Self.date(2026, 3, 15, 0, 1),
            calendar: Self.cal
        )
        #expect(result == nil)
    }

    @Test func piDayIgnoresUnrelatedShortcode() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["cake"]),
            now: Self.date(2026, 3, 14, 12, 0),
            calendar: Self.cal
        )
        #expect(result == nil)
    }

    // MARK: christmas (December 25)

    @Test func christmasFiresForSantaShortcode() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["santa"]),
            now: Self.date(2026, 12, 25, 9, 0),
            calendar: Self.cal
        )
        #expect(result == .k33)
    }

    @Test func christmasFiresForTreeShortcode() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["christmas_tree"]),
            now: Self.date(2026, 12, 25, 18, 30),
            calendar: Self.cal
        )
        #expect(result == .k33)
    }

    @Test func christmasDoesNotFireOnDec24() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["santa"]),
            now: Self.date(2026, 12, 24, 23, 59),
            calendar: Self.cal
        )
        #expect(result == nil)
    }

    @Test func christmasDoesNotFireOnDec26() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["christmas_tree"]),
            now: Self.date(2026, 12, 26, 0, 1),
            calendar: Self.cal
        )
        #expect(result == nil)
    }

    // MARK: halloween (October 31)

    @Test func halloweenFiresForJackOLantern() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["jack_o_lantern"]),
            now: Self.date(2026, 10, 31, 19, 0),
            calendar: Self.cal
        )
        #expect(result == .k34)
    }

    @Test func halloweenFiresForBat() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["bat"]),
            now: Self.date(2026, 10, 31, 12, 0),
            calendar: Self.cal
        )
        #expect(result == .k34)
    }

    @Test func halloweenFiresForGhost() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["ghost"]),
            now: Self.date(2026, 10, 31, 8, 0),
            calendar: Self.cal
        )
        #expect(result == .k34)
    }

    @Test func halloweenDoesNotFireOnNov1() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["jack_o_lantern"]),
            now: Self.date(2026, 11, 1, 0, 1),
            calendar: Self.cal
        )
        #expect(result == nil)
    }

    @Test func halloweenIgnoresUnrelatedSpookyShortcode() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["skull"]),
            now: Self.date(2026, 10, 31, 21, 0),
            calendar: Self.cal
        )
        #expect(result == nil)
    }

    // MARK: night gate (21:00–03:59)

    @Test func nightFiresAt21OnAnyDate() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["moon"]),
            now: Self.date(2026, 6, 15, 21, 0),
            calendar: Self.cal
        )
        #expect(result == .k28)
    }

    @Test func nightFiresAt0359() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["moon"]),
            now: Self.date(2026, 6, 15, 3, 59),
            calendar: Self.cal
        )
        #expect(result == .k28)
    }

    @Test func nightDoesNotFireAt0400() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["moon"]),
            now: Self.date(2026, 6, 15, 4, 0),
            calendar: Self.cal
        )
        #expect(result == nil)
    }

    @Test func nightDoesNotFireAt2059() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["moon"]),
            now: Self.date(2026, 6, 15, 20, 59),
            calendar: Self.cal
        )
        #expect(result == nil)
    }

    @Test func nightDoesNotFireOnCrescentMoonShortcode() {
        // Strict-match by user spec: only the "moon" shortcode counts,
        // not other lunar phases. Documented as a one-line extension if wanted.
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["crescent_moon"]),
            now: Self.date(2026, 6, 15, 23, 0),
            calendar: Self.cal
        )
        #expect(result == nil)
    }

    // MARK: multi-shortcode emoji + date precedence

    @Test func multiShortcodeMatchesIfAnyShortcodeIsGated() {
        // Emojibase canonical for 🌔 carries both "moon" and "waxing_gibbous_moon".
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["moon", "waxing_gibbous_moon"]),
            now: Self.date(2026, 6, 15, 22, 30),
            calendar: Self.cal
        )
        #expect(result == .k28)
    }

    @Test func unrelatedEmojiOnGatedDayDoesNotFire() {
        let result = SeasonalGates.evaluate(
            for: Self.emoji(["smile"]),
            now: Self.date(2026, 12, 25, 12, 0),
            calendar: Self.cal
        )
        #expect(result == nil)
    }
}
