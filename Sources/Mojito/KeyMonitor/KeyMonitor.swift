import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Receives key events from the global tap and translates them into TriggerInputs.
@MainActor
protocol KeyMonitorDelegate: AnyObject {
    /// Returns true if the event should be consumed (not delivered to the focused app).
    func keyMonitor(_ monitor: KeyMonitor, didReceive input: TriggerInput) -> Bool
    func keyMonitorDidLoseTap(_ monitor: KeyMonitor)
}

@MainActor
final class KeyMonitor {
    weak var delegate: KeyMonitorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    func start() -> Bool {
        // The CGEventTap callback dispatches via `MainActor.assumeIsolated`
        // in Engine. That's only safe if the tap is installed on the main
        // run loop — i.e. start() runs on the main thread. Guard the
        // invariant explicitly so a future caller can't introduce a subtle
        // crash by invoking us from a background queue.
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isRunning else { return true }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: context
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.isRunning = true
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Without invalidation the underlying Mach port leaks for the
            // process lifetime — `CFRunLoopRemoveSource` alone isn't enough.
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Skip events we posted ourselves (via TextInserter). Without this,
        // synthetic backspaces emitted during an emoticon replacement land
        // in this callback while `pendingEmoticonUndo` is set and trigger
        // the undo path immediately — turning `:)` into `::)`.
        if event.getIntegerValueField(.eventSourceUserData) == TextInserter.synthMarker {
            return Unmanaged.passUnretained(event)
        }
        // The tap can be auto-disabled by the system if it takes too long; re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            delegate?.keyMonitorDidLoseTap(self)
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let input = translate(event: event)
        guard let input else { return Unmanaged.passUnretained(event) }

        let consumed = delegate?.keyMonitor(self, didReceive: input) ?? false
        return consumed ? nil : Unmanaged.passUnretained(event)
    }

    private func translate(event: CGEvent) -> TriggerInput? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Cmd+Z (no other modifiers) gets routed through as a dedicated
        // input so the engine can offer emoticon-undo. Anything else with
        // modifiers (⌘Tab, ⌘C, …) is ignored — those mustn't trigger or
        // interrupt capture.
        if flags.contains(.maskCommand) {
            if keyCode == kVK_ANSI_Z
                && !flags.contains(.maskControl)
                && !flags.contains(.maskAlternate)
                && !flags.contains(.maskShift) {
                return .cmdZ
            }
            return nil
        }
        if flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return nil
        }

        switch keyCode {
        case kVK_Escape:        return .escape
        case kVK_Return, kVK_ANSI_KeypadEnter: return .returnKey
        case kVK_Tab:           return .tabKey
        case kVK_UpArrow:       return .arrowUp
        case kVK_DownArrow:     return .arrowDown
        case kVK_Delete, kVK_ForwardDelete: return .backspace
        case kVK_LeftArrow:
            // While the picker is open, swallow caret movement so the picker stays put. The
            // typed `:query` invariant survives because the focused app never sees the arrow.
            return .arrowLeft
        case kVK_RightArrow:
            return .arrowRight
        default: break
        }

        // Read the unicode character produced by the keystroke.
        var length: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0, let scalar = Unicode.Scalar(chars[0]) else { return nil }
        let char = Character(scalar)

        if char == ":" { return .colon }

        if isNameChar(char) { return .nameChar(char) }

        // Whitespace, punctuation, etc. cancel capture by passing through.
        // The character travels with the input so Engine can check it
        // against the emoticon table.
        return .cancelChar(char)
    }

    private func isNameChar(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber { return true }
        return c == "_" || c == "-" || c == "+"
    }
}
