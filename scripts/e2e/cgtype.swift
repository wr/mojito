// Synthetic keystroke helper for the E2E harness.
//
// Must post at the HID level (`.cghidEventTap`): Mojito's key monitor is a
// `.cgSessionEventTap`, and events synthesized by AppleScript "System Events
// keystroke" do NOT traverse it — they never reach Mojito's engine, so they
// can't reproduce a tap-path bug. HID-posted CGEvents do. Requires the invoking
// process to hold Accessibility permission.
//
// Usage:
//   cgtype type "some text"        Type Unicode text (one char per key event).
//   cgtype hotkey command t        Post a modified keystroke (mod: command|shift|option|control).
//   cgtype key 53                  Post a raw virtual keycode (53 = escape).

import CoreGraphics
import Foundation

let src = CGEventSource(stateID: .hidSystemState)

// Only the letters the harness needs for hotkeys.
let keymap: [Character: CGKeyCode] = ["t": 17, "w": 13, "n": 45, "l": 37, "a": 0]

// Track failed event creation so a caller (the harness) can tell that a keystroke
// was silently dropped rather than assume it typed — a no-op here is exactly how
// an E2E run would end up testing nothing.
var failures = 0

func post(_ event: CGEvent?) {
    guard let event else { failures += 1; return }
    event.post(tap: .cghidEventTap)
    usleep(12_000)   // ~12ms between events: fast typing, but not a burst the OS coalesces
}

func typeText(_ text: String) {
    for ch in text {
        let units = Array(String(ch).utf16)
        for isDown in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: isDown)
            units.withUnsafeBufferPointer {
                e?.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
            }
            post(e)   // nil is counted as a failure
        }
    }
}

func hotkey(mod: CGEventFlags, key: CGKeyCode) {
    for isDown in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: isDown)
        e?.flags = isDown ? mod : []
        post(e)
    }
}

func rawKey(_ code: CGKeyCode) {
    for isDown in [true, false] {
        post(CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: isDown))
    }
}

let args = CommandLine.arguments
func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8)); exit(2)
}

switch args.count >= 2 ? args[1] : "" {
case "type":
    guard args.count >= 3 else { die("cgtype type <text>") }
    typeText(args[2])
case "hotkey":
    guard args.count >= 4, let key = keymap[Character(args[3].lowercased())] else {
        die("cgtype hotkey <command|shift|option|control> <letter>")
    }
    let mod: CGEventFlags = ["command": .maskCommand, "shift": .maskShift,
                             "option": .maskAlternate, "control": .maskControl][args[2]] ?? []
    hotkey(mod: mod, key: key)
case "key":
    guard args.count >= 3, let code = UInt16(args[2]) else { die("cgtype key <keycode>") }
    rawKey(CGKeyCode(code))
default:
    die("usage: cgtype type <text> | hotkey <mod> <letter> | key <code>")
}

// Non-zero if any event couldn't be created — lets the harness treat a silent
// keystroke drop as a hard failure instead of a passing no-op.
exit(failures > 0 ? 1 : 0)
