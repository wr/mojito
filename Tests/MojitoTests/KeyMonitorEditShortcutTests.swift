import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import Mojito

/// `KeyMonitor.isEditShortcut` / `.isCmdZ` — which modifier combos count as
/// rewriting the field or undoing. Pure classification; no event tap involved.
struct KeyMonitorEditShortcutTests {
    private func isEdit(_ keyCode: Int, _ flags: CGEventFlags, letter: Character? = nil) -> Bool {
        KeyMonitor.isEditShortcut(keyCode: keyCode, flags: flags, commandLetter: letter)
    }

    @Test func modifiedDeleteIsAnEditShortcut() {
        #expect(isEdit(kVK_Delete, .maskCommand))
        #expect(isEdit(kVK_Delete, .maskAlternate))
        #expect(isEdit(kVK_Delete, .maskControl))
        #expect(isEdit(kVK_ForwardDelete, .maskAlternate))
    }

    @Test func plainAndShiftedDeleteAreNot() {
        // These reach the state machine as `.backspace` — one char at a time.
        #expect(!isEdit(kVK_Delete, []))
        #expect(!isEdit(kVK_Delete, .maskShift))
    }

    @Test func selectAllCutAndPasteAreEditShortcuts() {
        #expect(isEdit(kVK_ANSI_A, .maskCommand, letter: "a"))
        #expect(isEdit(kVK_ANSI_X, .maskCommand, letter: "x"))
        #expect(isEdit(kVK_ANSI_V, .maskCommand, letter: "v"))
        #expect(isEdit(kVK_ANSI_V, [.maskCommand, .maskShift, .maskAlternate], letter: "v"))
    }

    @Test func lettersWithoutCommandAreNot() {
        // Option+A types `å`; plain letters are name chars.
        #expect(!isEdit(kVK_ANSI_A, .maskAlternate, letter: "a"))
        #expect(!isEdit(kVK_ANSI_A, .maskControl, letter: "a"))
        #expect(!isEdit(kVK_ANSI_A, [], letter: "a"))
    }

    @Test func otherCommandCombosAreNot() {
        // Copy, undo, and app switching leave the typed query where it is.
        #expect(!isEdit(kVK_ANSI_C, .maskCommand, letter: "c"))
        #expect(!isEdit(kVK_ANSI_Z, .maskCommand, letter: "z"))
        #expect(!isEdit(kVK_Tab, .maskCommand))
    }

    @Test func modifiedArrowsAreEditShortcutsButPlainArrowsAreNot() {
        #expect(isEdit(kVK_LeftArrow, .maskCommand))
        #expect(isEdit(kVK_RightArrow, .maskAlternate))
        #expect(isEdit(kVK_UpArrow, .maskCommand))
        #expect(!isEdit(kVK_LeftArrow, []))
        #expect(!isEdit(kVK_DownArrow, .maskShift))
    }

    @Test func lettersAreMatchedByWhatTheLayoutTypesNotByKeyPosition() {
        // AZERTY: the key in the US Q position types A.
        #expect(isEdit(kVK_ANSI_Q, .maskCommand, letter: "a"))
        #expect(!isEdit(kVK_ANSI_A, .maskCommand, letter: "q"))
        // Dvorak: the US V position types K, so Cmd+K isn't a paste.
        #expect(!isEdit(kVK_ANSI_V, .maskCommand, letter: "k"))
        #expect(isEdit(kVK_ANSI_Period, .maskCommand, letter: "v"))
    }

    @Test func cmdZIsMatchedByLetterWithNoOtherModifiers() {
        #expect(KeyMonitor.isCmdZ(flags: .maskCommand, commandLetter: "z"))
        #expect(!KeyMonitor.isCmdZ(flags: .maskCommand, commandLetter: "w"))
        #expect(!KeyMonitor.isCmdZ(flags: [.maskCommand, .maskShift], commandLetter: "z"))
        #expect(!KeyMonitor.isCmdZ(flags: [.maskCommand, .maskAlternate], commandLetter: "z"))
        #expect(!KeyMonitor.isCmdZ(flags: [], commandLetter: "z"))
    }
}

/// `CommandKeyLayout.letter` against the keyboard layouts macOS ships, read
/// straight from their layout data — nothing is enabled or switched.
struct CommandKeyLayoutTests {
    private func letter(_ layoutID: String, _ keyCode: Int) throws -> Character? {
        let filter = [kTISPropertyInputSourceID as String: layoutID] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        let source = try #require(sources?.first, "\(layoutID) not installed")
        let data = try #require(CommandKeyLayout.layoutData(for: source))
        return CommandKeyLayout.letter(forKeyCode: keyCode, layoutData: data)
    }

    @Test func usLettersSitWhereTheKeyCodesSay() throws {
        #expect(try letter("com.apple.keylayout.US", kVK_ANSI_A) == "a")
        #expect(try letter("com.apple.keylayout.US", kVK_ANSI_Z) == "z")
    }

    @Test func azertyMovesAAndZ() throws {
        #expect(try letter("com.apple.keylayout.French", kVK_ANSI_Q) == "a")
        #expect(try letter("com.apple.keylayout.French", kVK_ANSI_A) == "q")
        #expect(try letter("com.apple.keylayout.French", kVK_ANSI_W) == "z")
    }

    @Test func qwertzMovesZ() throws {
        #expect(try letter("com.apple.keylayout.German", kVK_ANSI_Y) == "z")
        #expect(try letter("com.apple.keylayout.German", kVK_ANSI_Z) == "y")
    }

    @Test func dvorakMovesXAndV() throws {
        #expect(try letter("com.apple.keylayout.Dvorak", kVK_ANSI_B) == "x")
        #expect(try letter("com.apple.keylayout.Dvorak", kVK_ANSI_Period) == "v")
        #expect(try letter("com.apple.keylayout.Dvorak", kVK_ANSI_V) == "k")
    }

    @Test func dvorakQwertyCommandUsesQwertyWhileCmdIsHeld() throws {
        #expect(try letter("com.apple.keylayout.DVORAK-QWERTYCMD", kVK_ANSI_V) == "v")
        #expect(try letter("com.apple.keylayout.DVORAK-QWERTYCMD", kVK_ANSI_X) == "x")
    }

    @Test func nonLatinLayoutsGiveLatinLettersWithCmd() throws {
        #expect(try letter("com.apple.keylayout.Russian", kVK_ANSI_A) == "a")
        #expect(try letter("com.apple.keylayout.Greek", kVK_ANSI_Z) == "z")
    }
}
