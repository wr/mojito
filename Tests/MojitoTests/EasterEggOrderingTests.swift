import Foundation
import Testing
@testable import Mojito

/// Ordering + grouping logic for the Settings easter-egg list. Exercises the
/// pure seams (`isChildKeyword` / `reorderChildKeywords`) only — no discovery
/// state, banners, or UserDefaults side effects.
@MainActor
struct EasterEggOrderingTests {

    // MARK: isChildKeyword

    @Test func childWhenPrereqIsAnotherKeyword() {
        // Prerequisite is a keyword egg → renders as an indented sub-row.
        #expect(EasterEggTracker.isChildKeyword(.k51))
    }

    @Test func notChildWhenPrereqIsAchievement() {
        // Prerequisite is a milestone achievement, not a keyword egg.
        #expect(!EasterEggTracker.isChildKeyword(.k37))
    }

    @Test func notChildWhenNoPrereq() {
        #expect(!EasterEggTracker.isChildKeyword(.k49))
        #expect(!EasterEggTracker.isChildKeyword(.k01))
    }

    // MARK: reorderChildKeywords

    @Test func liftsChildBeneathItsParent() {
        // Parent and child separated by an unrelated keyword egg.
        let input: [EasterEgg] = [.k49, .k50, .k51]
        #expect(EasterEggTracker.reorderChildKeywords(input) == [.k49, .k51, .k50])
    }

    @Test func leavesAlreadyAdjacentChildUntouched() {
        let input: [EasterEgg] = [.k49, .k51, .k50]
        #expect(EasterEggTracker.reorderChildKeywords(input) == input)
    }

    @Test func ignoresAchievementGatedEggs() {
        // An egg gated behind a milestone achievement must not be reordered.
        let input: [EasterEgg] = [.k36, .k42, .k37]
        #expect(EasterEggTracker.reorderChildKeywords(input) == input)
    }

    @Test func noOpWhenNoChildKeywords() {
        let input: [EasterEgg] = [.k01, .k02, .k03]
        #expect(EasterEggTracker.reorderChildKeywords(input) == input)
    }
}
