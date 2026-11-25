import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Receives key events from the global tap and translates them into TriggerInputs.
@MainActor
protocol KeyMonitorDelegate: AnyObject {
    /// Returns true if the event should be consumed (not delivered to the focused app).
    func keyMonitor(_ monitor: KeyMonitor, didReceive input: TriggerInput) -> Bool
    func keyMonitorDidLoseTap(_ monitor: KeyMonitor)
    /// A lone Globe/Fn key was tapped (pressed and released with no other key
    /// in between). Not consumed — fn is just a modifier here, and consuming
    /// the key-up doesn't suppress the system panel anyway (macOS resolves
    /// Globe below the session tap), so suppression is handled by the
    /// AppleFnUsageType takeover instead.
    func keyMonitorDidTapGlobeKey(_ monitor: KeyMonitor)
}

@MainActor
final class KeyMonitor {
    weak var delegate: KeyMonitorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    /// Called once per `start()`, on the first real key the tap delivers.
    var onFirstKey: (() -> Void)?
    private var sawKey = false

    /// Lone Globe/Fn-tap detection: fn-down then fn-up within the threshold
    /// with no key pressed in between. `nil` timestamp = no press in flight.
    private var fnDownTimestamp: CGEventTimestamp?
    private var fnTapInterrupted = false
    private static let globeTapMaxDuration: CGEventTimestamp = 300_000_000  // ns

    func start() -> Bool {
        // Engine's `MainActor.assumeIsolated` callback dispatch is only safe
        // if the tap installs on the main run loop.
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isRunning else { return true }
        _ = CommandKeyLayout.shared  // load the layout before the first keypress

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
        self.sawKey = false
        DebugRecorder.record(.keyMonitor, "tapStart")
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
        DebugRecorder.record(.keyMonitor, "tapStop")
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
            DebugRecorder.record(.keyMonitor, "tapLost", ["reason": type == .tapDisabledByTimeout ? "timeout" : "userInput"])
            delegate?.keyMonitorDidLoseTap(self)
            return Unmanaged.passUnretained(event)
        }
        if !sawKey, type == .keyDown {
            sawKey = true
            onFirstKey?()
        }
        if type == .flagsChanged {
            handleFlagsChanged(event)
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        // A real keypress during an fn hold means it wasn't a lone Globe tap.
        if fnDownTimestamp != nil { fnTapInterrupted = true }

        let input = translate(event: event)
        guard let input else { return Unmanaged.passUnretained(event) }

        let consumed = delegate?.keyMonitor(self, didReceive: input) ?? false
        return consumed ? nil : Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == kVK_Function else {
            // A different modifier toggled mid-press — not a lone Globe tap.
            if fnDownTimestamp != nil { fnTapInterrupted = true }
            return
        }
        if event.flags.contains(.maskSecondaryFn) {
            fnDownTimestamp = event.timestamp
            fnTapInterrupted = false
        } else {
            defer { fnDownTimestamp = nil }
            guard let down = fnDownTimestamp, !fnTapInterrupted,
                  event.timestamp >= down,
                  event.timestamp - down < Self.globeTapMaxDuration else { return }
            delegate?.keyMonitorDidTapGlobeKey(self)
        }
    }

    private func translate(event: CGEvent) -> TriggerInput? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let commandLetter = flags.contains(.maskCommand) ? Self.commandLetter(keyCode: keyCode) : nil

        // Modifier combos that rewrite the field or move the caret end a
        // capture — the tracked `:query` is no longer what's in the field.
        if Self.isEditShortcut(keyCode: keyCode, flags: flags, commandLetter: commandLetter) {
            return .editShortcut
        }

        // Cmd+Z routes through so the engine can offer emoticon-undo. Other
        // modifier combos must not trigger or interrupt capture.
        if flags.contains(.maskCommand) {
            return Self.isCmdZ(flags: flags, commandLetter: commandLetter) ? .cmdZ : nil
        }
        if flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return nil
        }

        switch keyCode {
        case kVK_Escape:        return .escape
        case kVK_Return, kVK_ANSI_KeypadEnter: return .returnKey(shift: flags.contains(.maskShift))
        case kVK_Tab:           return .tabKey(shift: flags.contains(.maskShift))
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

    /// True for a Cmd / Option / Control combo that deletes or replaces text,
    /// or jumps the caret: a modified Delete or arrow key, or Cmd+A / X / V.
    /// These pass through to the focused app like every other modifier combo,
    /// but the state machine must hear about them — after Cmd+A then Delete
    /// (or Cmd+Delete, Option+Delete) the typed `:query` is gone, and a capture
    /// left open would swallow the next `:` as its closing delimiter.
    /// Delete and the arrows are matched by key code (they don't move between
    /// layouts); letters by `commandLetter`, since they do.
    nonisolated static func isEditShortcut(keyCode: Int, flags: CGEventFlags, commandLetter: Character?) -> Bool {
        let command = flags.contains(.maskCommand)
        guard command || flags.contains(.maskAlternate) || flags.contains(.maskControl) else {
            return false
        }
        switch keyCode {
        case kVK_Delete, kVK_ForwardDelete,
             kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            return true
        default:
            guard command, let commandLetter else { return false }
            return commandLetter == "a" || commandLetter == "x" || commandLetter == "v"
        }
    }

    /// Cmd+Z with no other modifiers.
    nonisolated static func isCmdZ(flags: CGEventFlags, commandLetter: Character?) -> Bool {
        commandLetter == "z"
            && flags.contains(.maskCommand)
            && !flags.contains(.maskControl)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskShift)
    }

    /// The letter a key types with Cmd held under the current layout. Falls
    /// back to the US position when the input source has no layout data.
    private static func commandLetter(keyCode: Int) -> Character? {
        CommandKeyLayout.shared.letter(forKeyCode: keyCode) ?? usCommandLetters[keyCode]
    }

    private static let usCommandLetters: [Int: Character] = [
        kVK_ANSI_A: "a", kVK_ANSI_X: "x", kVK_ANSI_V: "v", kVK_ANSI_Z: "z",
    ]

    private func isNameChar(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber { return true }
        // `'` lets `:'(` / `:')` capture with body `'` and terminator `(`/`)`.
        return c == "_" || c == "-" || c == "+" || c == "'"
    }
}
