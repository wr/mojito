import CryptoKit
import Foundation

/// Achievement layer that fires when a normal emoji insertion happens
/// to land on a specific calendar date or wall-clock window. The emoji
/// still inserts as usual; `EasterEggTracker.record` deduplicates the
/// banner per-discovery the same way every other egg does.
///
/// Shortcodes are stored as SHA-256 hashes for consistency with
/// `EggIndex` — the underlying strings are public emojibase shortcodes
/// already in `emoji.json`, so this is a convention, not real concealment.
enum SeasonalGates {

    /// Returns the egg that should fire for this insertion, if any.
    /// Pure — no side effects. The `fire` wrapper does the recording.
    static func evaluate(
        for emoji: Emoji,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> EasterEgg? {
        let comps = calendar.dateComponents([.month, .day, .hour], from: now)
        var hashed: Set<String>?

        for gate in gates where gate.matches(comps) {
            if hashed == nil {
                hashed = Set(emoji.shortcodes.map { hash($0.lowercased()) })
            }
            if !gate.shortcodeHashes.isDisjoint(with: hashed!) {
                return gate.egg
            }
        }
        return nil
    }

    @MainActor
    static func fire(
        for emoji: Emoji,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        if let egg = evaluate(for: emoji, now: now, calendar: calendar) {
            EasterEggTracker.record(egg)
        }
    }

    // MARK: - Gates

    private struct Gate {
        let matches: (DateComponents) -> Bool
        let shortcodeHashes: Set<String>
        let egg: EasterEgg
    }

    private static let gates: [Gate] = [
        Gate(
            matches: { c in
                guard let h = c.hour else { return false }
                return h >= 21 || h < 4
            },
            shortcodeHashes: [
                "9e78b43ea00edcac8299e0cc8df7f6f913078171335f733a21d5d911b6999132",
            ],
            egg: .k28
        ),
        Gate(
            matches: { c in c.month == 3 && c.day == 14 },
            shortcodeHashes: [
                "558211ed72b2d6967037419dff6f1e7cfd002d178c8fdeeb1239760d4e4c4059",
            ],
            egg: .k32
        ),
        Gate(
            matches: { c in c.month == 12 && c.day == 25 },
            shortcodeHashes: [
                "b6dc9083da372fed2119ace11ae9ba8713f7e30827e854371eb5d2335aec664b",
                "15c0c70a484000fa1032471ecebbe6d598effc62de5003b71d9e480245b44e2f",
            ],
            egg: .k33
        ),
        Gate(
            matches: { c in c.month == 10 && c.day == 31 },
            shortcodeHashes: [
                "0a3c1d2e2ca22a7dced065095d470d8640d092e65a46951583cb5ce6b4a043d5",
                "ca5bcec12f716f44d9745d349cc80422f0d14cbab09329caf533bef7c2d952eb",
                "ead6ef03d61ee60c533d6d450c50a1e559a8a37f6b796a4094cd0dac6b744428",
            ],
            egg: .k34
        ),
    ]

    private static func hash(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
