import Foundation

enum PrefsKey {
    static let onboardingComplete    = "mojito.onboarding.complete"
    /// Last onboarding step shown, so a quit+reopen (sometimes needed for a
    /// fresh Accessibility grant to register) resumes mid-flow instead of
    /// restarting at the welcome screen. Raw value of `OnboardingRoot.Step`.
    static let onboardingStep        = "mojito.onboarding.step"
    static let pausedUntil           = "mojito.paused.until"
    static let launchAtLogin         = "mojito.launchAtLogin"
    /// When false, the menu-bar status item is suppressed; users reach
    /// Settings by relaunching the app from Finder / Spotlight.
    static let showMenuBarIcon       = "mojito.showMenuBarIcon"
    static let useFrequencyBoost     = "mojito.search.frequencyBoost"
    static let excludedBundleIDs     = "mojito.excludeBundleIDs"     // [String]
    static let excludedURLPatterns   = "mojito.excludeURLPatterns"   // [String]
    /// One-time flag: developer-tool bundle IDs have been folded into the
    /// excluded list. Lets existing installs pick up the editor/terminal
    /// defaults once (arrow conversion collides with code operators) without
    /// re-adding any the user later removes.
    static let devToolExclusionsSeeded = "mojito.exclusions.devToolsSeeded"
    /// `denylist` (default) = block apps/sites in the excluded lists.
    /// `allowlist` = block everything except apps/sites in the allowed lists.
    /// In allowlist mode a URL-pattern match implicitly allows the browser
    /// hosting it, so users don't have to allowlist Chrome to allow github.com.
    static let exclusionMode         = "mojito.exclusions.mode"      // String, ExclusionMode raw
    static let allowedBundleIDs      = "mojito.allowBundleIDs"       // [String]
    static let allowedURLPatterns    = "mojito.allowURLPatterns"     // [String]
    static let usageCounts           = "mojito.usageCounts"          // [String: Int]  (hexcode → count)
    /// User-defined shortcodes that resolve to an emoji. JSON-encoded
    /// `[CustomAlias]` (alias string → hexcode). Additive on top of the baked
    /// emoji corpus; an alias wins over a built-in shortcode with the same
    /// spelling. Managed in Settings ▸ Shortcuts.
    static let customAliases         = "mojito.customAliases"        // Data (JSON [CustomAlias])
    /// The 8 Quick Access slots surfaced on `:<trigger>` and managed in
    /// Settings ▸ General. An 8-element `[String]` where `""` is an auto
    /// (most-used) slot and any other value is a pinned emoji hexcode.
    static let quickAccessSlots      = "mojito.quickAccess"          // [String]  (8 slots; "" = auto)
    /// Whether the `:?` Quick Access pill is enabled (default true).
    static let quickAccessEnabled    = "mojito.quickAccessEnabled"
    /// JSON-encoded `TriggerConfig` — the user-editable trigger strings for
    /// emoji / symbols / GIF / quick-access. Absent on installs that predate
    /// the feature; `TriggerConfigStore.load()` migrates from the legacy
    /// per-feature prefs once and persists the result here.
    static let triggers              = "mojito.triggers"
    /// Set once on first launch.
    static let firstLaunchDate       = "mojito.firstLaunchDate"
    /// Self-attested; no payment integration.
    static let donated               = "mojito.donated"
    /// `[String]` of `EasterEgg` raw values.
    static let easterEggsDiscovered  = "mojito.easterEggs.discovered"
    /// Master switch for easter eggs (default on). When off, no egg fires
    /// or is discovered — except the one awarded for turning this off.
    static let eggsEnabled           = "mojito.eggs.enabled"
    /// Easter-egg audio toggles. Both default on; the visuals always play.
    /// `discoverySound` gates the "egg found" chime (`DiscoveryFanfare`);
    /// `effectSounds` gates the audio an individual egg makes while running.
    static let eggDiscoverySoundEnabled = "mojito.eggs.discoverySound"
    static let eggEffectSoundsEnabled   = "mojito.eggs.effectSounds"
    /// Raw value from `SkinTone`.
    static let skinTone              = "mojito.skinTone"
    /// `:D` → 😃 conversion.
    static let emoticonsEnabled      = "mojito.emoticonsEnabled"
    /// Text-arrow conversion (`->` → →, `<-` → ←, `<->` → ↔), independent
    /// of `emoticonsEnabled`. Default on; off leaves arrows as literal text.
    static let arrowConversionEnabled = "mojito.arrowConversionEnabled"
    /// Experimental Symbols (★ ⌘ ⌥ …) included in fuzzy search.
    static let symbolsEnabled        = "mojito.symbolsEnabled"
    /// `:foo` = emoji only; `::foo` = symbols. Keeps the noisy symbols
    /// corpus off the default flow.
    static let symbolsRequireDoubleColon = "mojito.symbols.requireDoubleColon"
    /// Key name kept for backward compatibility with existing installs.
    static let perfectBounceCount    = "mojito.perfectBounce.count"
    /// User-provided Giphy beta API key for GIF search (`:::` trigger).
    /// `defaults write ee.wells.Mojito.dev mojito.giphyApiKey "<key>"`.
    static let giphyApiKey           = "mojito.giphyApiKey"
    /// Master switch for the `:::` GIF picker. When off, `:::` is just
    /// three colons in your text — no network call, no panel.
    static let gifSearchEnabled      = "mojito.gifSearch.enabled"
    /// When true, the GIF picker fires even in apps/URLs listed in the
    /// exclusion list. Default true: users tend to exclude apps that
    /// have their own emoji UI (Slack, Discord), not their own GIF UI.
    static let gifBypassExclusions   = "mojito.gifSearch.bypassExclusions"
    /// Lifetime totals that drive milestone achievements (k36–k48).
    /// Separate from `usageCounts` so milestones aren't reset when the
    /// user clears their per-emoji stats. Existing users seed from
    /// `usageCounts` on first launch with this build.
    static let totalEmojiInserted    = "mojito.totals.emojiInserted"
    static let totalSymbolInserted   = "mojito.totals.symbolInserted"
    static let totalGifInserted      = "mojito.totals.gifInserted"
    /// Lifetime emoticon conversions (`:)` → 🙂, ambient `<3` → ❤️). Pure
    /// diagnostic tally — no milestone achievements ride on it — so the
    /// debug report can show whether conversions are landing at all.
    static let totalEmoticonInserted = "mojito.totals.emoticonInserted"

    // MARK: Replace system emoji picker
    /// When true, the browser hotkey owns ⌃⌘Space and the macOS Emoji & Symbols
    /// panel is best-effort suppressed. Independent of the Globe toggle below.
    static let replaceSystemEmojiPickerEnabled = "mojito.replaceSystemEmojiPicker.enabled"
    /// When true, a lone Globe/Fn tap opens the browser (its own toggle).
    static let globeKeyEnabled                 = "mojito.replaceSystemEmojiPicker.globeEnabled"
    /// `AppleFnUsageType` value captured before we set it to 0, restored when the
    /// Globe toggle goes off. Absent unless the Globe takeover is on.
    static let priorFnUsageType                = "mojito.replaceSystemEmojiPicker.priorFnUsageType"
    /// Whether symbolic hotkey 50 (Character Viewer) was enabled before we
    /// disabled it, restored when panel replacement goes off.
    static let priorCharacterPaletteEnabled    = "mojito.replaceSystemEmojiPicker.priorPaletteEnabled"

    // MARK: Anonymous usage statistics
    /// Opt-out master switch. Default true, but nothing is sent until
    /// `telemetryConsentSeen` is also true (Homebrew-style consent gate).
    static let telemetryEnabled        = "mojito.telemetry.enabled"
    /// Flipped once the user has seen the one-time consent notice (or the
    /// Privacy settings tab). Gates all uploads so nothing leaves the Mac
    /// before disclosure.
    static let telemetryConsentSeen    = "mojito.telemetry.consentSeen"
    /// UTC day number of the last successful upload — throttles to ≤1/day.
    static let telemetryLastUploadDay  = "mojito.telemetry.lastUploadDay"
    /// Daily-aggregate deltas, cleared on a successful upload. Per-emoji map
    /// is capped per-emoji on write (anti-skew, not identification). No
    /// identifiers, timestamps, or free text are ever accumulated here.
    static let telemetryPendingEmoji        = "mojito.telemetry.pending.emoji"        // [String: Int]
    static let telemetryPendingEmojiTotal   = "mojito.telemetry.pending.emojiTotal"   // Int
    static let telemetryPendingSymbol       = "mojito.telemetry.pending.symbol"       // Int
    static let telemetryPendingGif          = "mojito.telemetry.pending.gif"          // Int
    static let telemetryPendingEmoticon     = "mojito.telemetry.pending.emoticon"     // Int
    static let telemetryPendingEggs         = "mojito.telemetry.pending.eggs"         // Int
    static let telemetryPendingQuickAccess  = "mojito.telemetry.pending.quickAccess"  // Int
}
