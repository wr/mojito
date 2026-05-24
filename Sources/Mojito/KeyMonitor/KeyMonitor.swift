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
        // Engine's `MainActor.assumeIsolated` callback dispatch is only safe
        // if the tap installs on the main run loop.
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
            // CFRunLoopRemoveSource alone leaks the underlying Mach port.
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
        // Skip our own synthetic events — otherwise synth-backspaces from
        // an emoticon replacement re-trigger the undo path and turn
        // `:)` into `::)`.
        if event.getIntegerValueField(.eventSourceUserData) == TextInserter.synthMarker {
            return Unmanaged.passUnretained(event)
        }
        // The system auto-disables the tap if it takes too long.
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

        // Cmd+Z (no other modifiers) routes through so the engine can
        // offer emoticon-undo. Other modifier combos must not trigger or
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
        case kVK_LeftArrow:  return .arrowLeft
        case kVK_RightArrow: return .arrowRight
        default: break
        }

        var length: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0, let scalar = Unicode.Scalar(chars[0]) else { return nil }
        let char = Character(scalar)

        if char == ":" { return .colon }
        if isNameChar(char) { return .nameChar(char) }
        return .cancelChar(char)
    }

    private func isNameChar(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber { return true }
        // `'` lets `:'(` / `:')` capture with body `'` and terminator `(`/`)`.
        return c == "_" || c == "-" || c == "+" || c == "'"
    }
}
