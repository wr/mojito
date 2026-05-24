import Foundation

/// Stack of teardown closures from full-screen effects. Esc pops the top;
/// `anyKey: true` effects (BSOD) dismiss on any keystroke.
@MainActor
enum EffectDismisser {
    private struct Entry {
        let token: Int
        let dismiss: () -> Void
        let anyKey: Bool
        /// Guard against the engine's post-trigger synth-backspaces
        /// dismissing the effect on the same frame it appears.
        let anyKeyArmedAt: Date
    }
    private static var stack: [Entry] = []
    private static var nextToken: Int = 0

    /// Returns a cancel token; invoke after dismiss to remove the entry.
    @discardableResult
    static func register(anyKey: Bool = false, _ dismiss: @escaping () -> Void) -> () -> Void {
        let token = nextToken
        nextToken += 1
        // 350ms covers the engine's post-trigger synth-backspaces.
        let armedAt = Date().addingTimeInterval(anyKey ? 0.35 : 0)
        stack.append(Entry(token: token, dismiss: dismiss, anyKey: anyKey, anyKeyArmedAt: armedAt))
        return {
            stack.removeAll { $0.token == token }
        }
    }

    @discardableResult
    static func dismissTop() -> Bool {
        guard let last = stack.popLast() else { return false }
        last.dismiss()
        return true
    }

    /// Top entry opted into any-key dismissal AND its arm delay has elapsed.
    static func topWantsAnyKey() -> Bool {
        guard let top = stack.last, top.anyKey else { return false }
        return Date() >= top.anyKeyArmedAt
    }

    static func reset() {
        stack.removeAll()
    }
}
