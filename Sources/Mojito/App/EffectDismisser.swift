import Foundation

/// Stack of "dismiss me" closures registered by full-screen effects.
///
/// Each effect's `start()` registers its teardown closure here and keeps
/// the returned cancel token; when the effect tears itself down (timer or
/// click), it calls the token so its entry is removed. The Engine
/// intercepts Esc keystrokes globally and pops the most recently
/// registered effect, so the user can always bail out of whatever is
/// onscreen with a single Esc.
@MainActor
enum EffectDismisser {
    /// Identifier issued on registration; passed back to `unregister(_:)`
    /// when the effect tears itself down for non-Esc reasons.
    /// `anyKey` means the effect wants ANY key (not just Esc) to dismiss
    /// it — used by BSOD so the iconic "Press any key to continue" prompt
    /// is honest. `anyKeyArmedAt` is a wall-clock guard: synthetic delete
    /// keystrokes from inserting nothing for the BSOD effect re-enter the
    /// tap and would otherwise dismiss the BSOD the same frame it shows.
    private struct Entry {
        let token: Int
        let dismiss: () -> Void
        let anyKey: Bool
        let anyKeyArmedAt: Date
    }
    private static var stack: [Entry] = []
    private static var nextToken: Int = 0

    /// Register a teardown closure. Returns the cancel-token callback;
    /// invoke it after dismiss to remove the entry from the stack.
    @discardableResult
    static func register(anyKey: Bool = false, _ dismiss: @escaping () -> Void) -> () -> Void {
        let token = nextToken
        nextToken += 1
        // 350ms arm delay covers the synthetic delete keystrokes the
        // engine fires right after the trigger.
        let armedAt = Date().addingTimeInterval(anyKey ? 0.35 : 0)
        stack.append(Entry(token: token, dismiss: dismiss, anyKey: anyKey, anyKeyArmedAt: armedAt))
        return {
            stack.removeAll { $0.token == token }
        }
    }

    /// Esc handler. Pops and invokes the top entry; returns true if there
    /// was something to dismiss, false otherwise.
    @discardableResult
    static func dismissTop() -> Bool {
        guard let last = stack.popLast() else { return false }
        last.dismiss()
        return true
    }

    /// True if the top entry opted into any-key dismissal AND its arm
    /// delay has elapsed. Engine uses this to consume a key event and
    /// pop the stack when a BSOD-style effect is showing.
    static func topWantsAnyKey() -> Bool {
        guard let top = stack.last, top.anyKey else { return false }
        return Date() >= top.anyKeyArmedAt
    }

    /// Clear everything — used on app shutdown / tap loss.
    static func reset() {
        stack.removeAll()
    }
}
