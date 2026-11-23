import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import Mojito

/// `KeyMonitor.isEditShortcut` — which modifier combos count as rewriting the
/// field. Pure classification; no event tap involved.
struct KeyMonitorEditShortcutTests {
    private func isEdit(_ keyCode: Int, _ flags: CGEventFlags) -> Bool {
        KeyMonitor.isEditShortcut(keyCode: keyCode, flags: flags)
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
        #expect(isEdit(kVK_ANSI_A, .maskCommand))
        #expect(isEdit(kVK_ANSI_X, .maskCommand))
        #expect(isEdit(kVK_ANSI_V, .maskCommand))
        #expect(isEdit(kVK_ANSI_V, [.maskCommand, .maskShift, .maskAlternate]))
    }

    @Test func lettersWithoutCommandAreNot() {
        // Option+A types `å`; plain letters are name chars.
        #expect(!isEdit(kVK_ANSI_A, .maskAlternate))
        #expect(!isEdit(kVK_ANSI_A, .maskControl))
        #expect(!isEdit(kVK_ANSI_A, []))
    }

    @Test func otherCommandCombosAreNot() {
        // Copy, undo, and app switching leave the typed query where it is.
        #expect(!isEdit(kVK_ANSI_C, .maskCommand))
        #expect(!isEdit(kVK_ANSI_Z, .maskCommand))
        #expect(!isEdit(kVK_Tab, .maskCommand))
    }

    @Test func modifiedArrowsAreEditShortcutsButPlainArrowsAreNot() {
        #expect(isEdit(kVK_LeftArrow, .maskCommand))
        #expect(isEdit(kVK_RightArrow, .maskAlternate))
        #expect(isEdit(kVK_UpArrow, .maskCommand))
        #expect(!isEdit(kVK_LeftArrow, []))
        #expect(!isEdit(kVK_DownArrow, .maskShift))
    }
}
