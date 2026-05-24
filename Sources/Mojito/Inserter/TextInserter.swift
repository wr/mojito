import AppKit
import CoreGraphics

/// Replaces `charactersToDelete` characters before the caret with `string` in the
/// frontmost app, by posting synthetic key events.
@MainActor
enum TextInserter {
    static func replace(charactersToDelete: Int, with string: String) {
        // 1. Send N backspaces to delete the typed `:query[:]`.
        for _ in 0..<charactersToDelete {
            postKey(virtualKey: 0x33, flags: [])  // kVK_Delete
        }

        // 2. Insert the unicode string. Splitting per emoji avoids edge cases in
        //    apps that quietly drop combined ZWJ sequences in a single event.
        let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        let upEvent   = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)

        let utf16 = Array(string.utf16)
        utf16.withUnsafeBufferPointer { buf in
            downEvent?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            upEvent?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
    }

    /// Just deletes — used by the easter-egg path where we erase the typed
    /// `:mojito` from the focused app without putting any emoji back.
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
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
