import AppKit
import Carbon.HIToolbox

/// Which letter a key types with Cmd held under the current keyboard layout —
/// the letter apps match their Cmd shortcuts against. Key codes are physical
/// positions, so on AZERTY the key labelled A arrives as `kVK_ANSI_Q`.
/// Non-Latin layouts (Russian, Greek, Hebrew, …) carry a Latin Cmd map in their
/// own layout data, so they resolve here too.
@MainActor
final class CommandKeyLayout: NSObject {
    static let shared = CommandKeyLayout()

    private var layoutData: Data?

    private override init() {
        super.init()
        reload()
        // Reload here, not in the tap callback, so a Cmd keypress never pays
        // for a TIS lookup. `.deliverImmediately` because AppKit otherwise
        // holds distributed notifications while the app is inactive, which
        // for a menu-bar app is nearly always.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func inputSourceChanged() {
        reload()
    }

    /// Lowercased letter for `keyCode` with Cmd held, or nil when the current
    /// input source exposes no layout data.
    func letter(forKeyCode keyCode: Int) -> Character? {
        guard let layoutData else { return nil }
        return Self.letter(forKeyCode: keyCode, layoutData: layoutData)
    }

    private func reload() {
        let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        layoutData = source.flatMap(Self.layoutData(for:))
        let id = source
            .flatMap { TISGetInputSourceProperty($0, kTISPropertyInputSourceID) }
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
        DebugRecorder.record(.keyMonitor, "commandLayout", [
            "id": id ?? "none", "hasData": "\(layoutData != nil)",
        ])
    }

    nonisolated static func layoutData(for source: TISInputSource) -> Data? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    }

    nonisolated static func letter(forKeyCode keyCode: Int, layoutData: Data) -> Character? {
        layoutData.withUnsafeBytes { bytes -> Character? in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDown),
                UInt32((cmdKey >> 8) & 0xFF), UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length).lowercased().first
        }
    }
}
