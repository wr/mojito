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
        for _ in 0..<charactersToDelete {
            postKey(virtualKey: 0x33, flags: [])  // kVK_Delete
        }

        let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        let upEvent   = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)

        let utf16 = Array(string.utf16)
        utf16.withUnsafeBufferPointer { buf in
            downEvent?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            upEvent?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        downEvent?.setIntegerValueField(.eventSourceUserData, value: synthMarker)
        upEvent?.setIntegerValueField(.eventSourceUserData, value: synthMarker)
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
    }

    /// Easter-egg path: erase the typed `:keyword` without replacement.
    static func deleteBackward(_ count: Int) {
        for _ in 0..<count {
            postKey(virtualKey: 0x33, flags: [])  // kVK_Delete
        }
    }

    private static func postKey(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.setIntegerValueField(.eventSourceUserData, value: synthMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: synthMarker)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
