import Foundation

enum PrefsKey {
    static let onboardingComplete    = "mojito.onboarding.complete"
    static let pausedUntil           = "mojito.paused.until"
    static let launchAtLogin         = "mojito.launchAtLogin"
    static let useFrequencyBoost     = "mojito.search.frequencyBoost"
    static let excludedBundleIDs     = "mojito.excludeBundleIDs"     // [String]
    static let excludedURLPatterns   = "mojito.excludeURLPatterns"   // [String]
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
}
