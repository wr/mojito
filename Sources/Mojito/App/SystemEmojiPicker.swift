import AppKit
import CoreGraphics
import KeyboardShortcuts

// MARK: - Private symbolic-hotkey bridge

// `CGSSetSymbolicHotKeyEnabled` / `CGSIsSymbolicHotKeyEnabled` are unsupported
// WindowServer exports (SkyLight on modern macOS, CoreGraphics on older). They
// need no entitlement in a Developer-ID, non-sandboxed build and notarization
// doesn't scan for them — but a future macOS could renumber or drop them, so we
// resolve them by name at runtime and treat absence as "feature unavailable"
// rather than linking the framework and risking an undefined-symbol crash.
private enum CGSHotkeyBridge {
    private typealias SetEnabledFn = @convention(c) (Int32, Bool) -> CGError
    private typealias IsEnabledFn = @convention(c) (Int32) -> Bool

    private static let setEnabledFn: SetEnabledFn? = resolve("CGSSetSymbolicHotKeyEnabled")
    private static let isEnabledFn: IsEnabledFn? = resolve("CGSIsSymbolicHotKeyEnabled")

    /// RTLD_DEFAULT searches every image already loaded into this process.
    /// SkyLight is loaded into every GUI app, so no explicit dlopen is needed.
    private static func resolve<T>(_ symbol: String) -> T? {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, symbol) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static func setEnabled(_ hotKey: Int32, _ enabled: Bool) -> Bool {
        guard let fn = setEnabledFn else { return false }
        return fn(hotKey, enabled) == .success
    }

    /// Defaults to `true` when the symbol is missing — matches the system
    /// default so a later restore re-enables rather than silently leaving off.
    static func isEnabled(_ hotKey: Int32) -> Bool {
        guard let fn = isEnabledFn else { return true }
        return fn(hotKey)
    }
}

private enum SystemSymbolicHotkey {
    /// `kCGSHotKeyToggleCharacterPallette` (sic) — the ⌃⌘Space Emoji & Symbols
    /// panel. Documented in the reverse-engineered CGSHotKeys.h but unverified
    /// on recent macOS, so a no-op disable is expected; our own ⌃⌘Space
    /// registration is what actually wins the chord.
    static let characterPalette: Int32 = 50

    static var characterPaletteEnabled: Bool { CGSHotkeyBridge.isEnabled(characterPalette) }

    @discardableResult
    static func setCharacterPalette(enabled: Bool) -> Bool {
        CGSHotkeyBridge.setEnabled(characterPalette, enabled)
    }
}

// MARK: - Coordinator

/// Owns the "Replace system emoji picker" feature, split into two independent
/// concerns: claiming ⌃⌘Space + suppressing the macOS panel (`replacesPanel`),
/// and taking over the Globe/Fn key (`globeEnabled`). The "Replace" button does
/// both; each is also separately toggleable.
@MainActor
final class SystemEmojiPickerReplacer {
    static let shared = SystemEmojiPickerReplacer()

    private let defaults = UserDefaults.standard
    private static let hiToolboxDomain = "com.apple.HIToolbox" as CFString
    private static let fnUsageKey = "AppleFnUsageType" as CFString
    /// `AppleFnUsageType` value for "Do Nothing" — set so the OS stops claiming
    /// the Globe key while we detect a lone tap ourselves.
    private static let fnUsageNone = 0

    private init() {}

    /// The system emoji shortcut Mojito claims — ⌃⌘Space, the real macOS
    /// Emoji & Symbols chord.
    static let systemShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .control])

    /// The browser hotkey's default — what the reset button restores.
    static let defaultShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .option])

    /// Whether Mojito stands in for the ⌃⌘Space panel: the browser hotkey owns
    /// ⌃⌘Space and the macOS Emoji & Symbols panel (CGS hotkey 50) is suppressed.
    /// The persisted flag is the source of truth — NOT the hotkey value, which in
    /// the dev build reflects the release app's inherited fallback. Drives the
    /// "Replace" button's visibility: once on, there's nothing left to replace.
    var replacesPanel: Bool { defaults.bool(forKey: PrefsKey.replaceSystemEmojiPickerEnabled) }

    /// Whether a lone Globe/Fn tap opens the browser. Its own toggle in Settings,
    /// independent of the ⌃⌘Space replacement.
    var globeEnabled: Bool { defaults.bool(forKey: PrefsKey.globeKeyEnabled) }
    var globeOpensBrowser: Bool { globeEnabled }

    /// Set by `enableGlobe()` when the Fn pref had to change: the Globe takeover
    /// only fully lands after the user logs out and back in.
    private(set) var needsLogoutForGlobe = false

    /// Re-assert the CGS disable at launch (it resets every login). The hotkey
    /// binding and Fn pref persist on their own; only the CGS state is runtime.
    func applyAtLaunch() {
        guard replacesPanel else { return }
        SystemSymbolicHotkey.setCharacterPalette(enabled: false)
    }

    // MARK: Combined actions (Replace button / onboarding)

    /// "Replace System Picker": claim ⌃⌘Space, suppress the macOS panel, and
    /// take over the Globe key — the whole feature in one tap.
    func replaceSystemPicker() {
        setBrowserShortcut(Self.systemShortcut)
        enablePanelReplacement()
        enableGlobe()
    }

    /// Reset: restore the default hotkey, the system panel, and the Globe key.
    func restoreSystemPicker() {
        setBrowserShortcut(Self.defaultShortcut)
        disablePanelReplacement()
        disableGlobe()
    }

    /// The bind is programmatic so it skips the recorder's "already a system
    /// shortcut" alert that ⌃⌘Space would otherwise trip.
    func setBrowserShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(shortcut, for: .showEmojiBrowser)
    }

    // MARK: ⌃⌘Space panel replacement

    /// Best-effort suppress the macOS Emoji & Symbols panel (CGS hotkey 50).
    /// Separate from the hotkey bind so the recorder can sync this to a ⌃⌘Space
    /// the user typed directly.
    func enablePanelReplacement() {
        defaults.set(true, forKey: PrefsKey.replaceSystemEmojiPickerEnabled)
        if defaults.object(forKey: PrefsKey.priorCharacterPaletteEnabled) == nil {
            defaults.set(SystemSymbolicHotkey.characterPaletteEnabled,
                         forKey: PrefsKey.priorCharacterPaletteEnabled)
        }
        SystemSymbolicHotkey.setCharacterPalette(enabled: false)
    }

    func disablePanelReplacement() {
        defaults.set(false, forKey: PrefsKey.replaceSystemEmojiPickerEnabled)
        let restore = defaults.object(forKey: PrefsKey.priorCharacterPaletteEnabled) as? Bool ?? true
        SystemSymbolicHotkey.setCharacterPalette(enabled: restore)
        defaults.removeObject(forKey: PrefsKey.priorCharacterPaletteEnabled)
    }

    // MARK: Globe / Fn key

    func enableGlobe() {
        defaults.set(true, forKey: PrefsKey.globeKeyEnabled)
        takeOverGlobeKey()
    }

    func disableGlobe() {
        defaults.set(false, forKey: PrefsKey.globeKeyEnabled)
        restoreGlobeKey()
    }

    // MARK: Globe / Fn key

    private func takeOverGlobeKey() {
        let current = currentFnUsageType()
        if defaults.object(forKey: PrefsKey.priorFnUsageType) == nil {
            defaults.set(current, forKey: PrefsKey.priorFnUsageType)
        }
        // If Fn is already "Do Nothing", our event-tap detection works
        // immediately and nothing competes — no logout needed.
        if current != Self.fnUsageNone {
            setFnUsageType(Self.fnUsageNone)
            needsLogoutForGlobe = true
        } else {
            needsLogoutForGlobe = false
        }
    }

    private func restoreGlobeKey() {
        if let prior = defaults.object(forKey: PrefsKey.priorFnUsageType) as? Int {
            setFnUsageType(prior)
            defaults.removeObject(forKey: PrefsKey.priorFnUsageType)
        }
        needsLogoutForGlobe = false
    }

    private func currentFnUsageType() -> Int {
        CFPreferencesCopyAppValue(Self.fnUsageKey, Self.hiToolboxDomain) as? Int ?? 0
    }

    private func setFnUsageType(_ value: Int) {
        CFPreferencesSetAppValue(Self.fnUsageKey, value as CFNumber, Self.hiToolboxDomain)
        _ = CFPreferencesAppSynchronize(Self.hiToolboxDomain)
    }
}
