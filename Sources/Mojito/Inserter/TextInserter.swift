import AppKit
import CoreGraphics

/// Replaces `charactersToDelete` characters before the caret with `string` in the
/// frontmost app, by posting synthetic key events.
@MainActor
enum TextInserter {
    /// Stamped on every event we post so `KeyMonitor` can drop them at
    /// the tap. Without this, synth-backspaces round-trip through the
    /// undo path and turn `:)` into `::)`.
    static let synthMarker: Int64 = 0x4D4F4A49544F  // ASCII "MOJITO"

    static func replace(charactersToDelete: Int, with string: String) {
        var posted = true
        for _ in 0..<charactersToDelete {
            posted = postKey(virtualKey: 0x33, flags: []) && posted  // kVK_Delete
        }

        if let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
           let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            let utf16 = Array(string.utf16)
            utf16.withUnsafeBufferPointer { buf in
                downEvent.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                upEvent.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            downEvent.setIntegerValueField(.eventSourceUserData, value: synthMarker)
            upEvent.setIntegerValueField(.eventSourceUserData, value: synthMarker)
            downEvent.post(tap: .cghidEventTap)
            upEvent.post(tap: .cghidEventTap)
        } else {
            posted = false
        }
        // Grapheme count (not contents) — enough to see the path ran and
        // with what shape, while staying clear of the no-user-text rule.
        DebugRecorder.record(.insert, "replace", [
            "del": "\(charactersToDelete)",
            "len": "\(string.count)",
            "posted": "\(posted)",
        ])
    }

    /// Easter-egg path: erase the typed `:keyword` without replacement.
    static func deleteBackward(_ count: Int) {
        var posted = true
        for _ in 0..<count {
            posted = postKey(virtualKey: 0x33, flags: []) && posted  // kVK_Delete
        }
        DebugRecorder.record(.insert, "delete", ["count": "\(count)", "posted": "\(posted)"])
    }

    /// Synth ⌘V into the focused app — used by the GIF picker to paste the
    /// selected GIF inline after writing it to the clipboard. Works in any
    /// text field that accepts the standard "paste" action.
    static func pasteFromClipboard() {
        let posted = postKey(virtualKey: 0x09, flags: .maskCommand)  // kVK_ANSI_V
        DebugRecorder.record(.insert, "paste", ["posted": "\(posted)"])
    }

    /// Returns false if either CGEvent couldn't be created — the clearest
    /// observable failure of the synthetic-event path (it can't tell us
    /// whether a created event was actually delivered).
    @discardableResult
    private static func postKey(virtualKey: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) else {
            return false
        }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: synthMarker)
        up.setIntegerValueField(.eventSourceUserData, value: synthMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
