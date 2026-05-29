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
    /// `denylist` (default) = block apps/sites in the excluded lists.
    /// `allowlist` = block everything except apps/sites in the allowed lists.
    /// In allowlist mode a URL-pattern match implicitly allows the browser
    /// hosting it, so users don't have to allowlist Chrome to allow github.com.
    static let exclusionMode         = "mojito.exclusions.mode"      // String, ExclusionMode raw
    static let allowedBundleIDs      = "mojito.allowBundleIDs"       // [String]
    static let allowedURLPatterns    = "mojito.allowURLPatterns"     // [String]
    static let usageCounts           = "mojito.usageCounts"          // [String: Int]  (hexcode → count)
    /// Set once on first launch.
    static let firstLaunchDate       = "mojito.firstLaunchDate"
    /// Self-attested; no payment integration.
    static let donated               = "mojito.donated"
    /// `[String]` of `EasterEgg` raw values.
    static let easterEggsDiscovered  = "mojito.easterEggs.discovered"
    /// Raw value from `SkinTone`.
    static let skinTone              = "mojito.skinTone"
    /// `:D` → 😃 conversion.
    static let emoticonsEnabled      = "mojito.emoticonsEnabled"
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
}
