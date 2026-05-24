import Foundation

enum PrefsKey {
    static let onboardingComplete    = "mojito.onboarding.complete"
    static let pausedUntil           = "mojito.paused.until"
    static let launchAtLogin         = "mojito.launchAtLogin"
    static let useFrequencyBoost     = "mojito.search.frequencyBoost"
    static let excludedBundleIDs     = "mojito.excludeBundleIDs"     // [String]
    static let excludedURLPatterns   = "mojito.excludeURLPatterns"   // [String]
    static let usageCounts           = "mojito.usageCounts"          // [String: Int]  (hexcode → count)
    /// Unix timestamp the user first launched the app. Set once and never changed.
    static let firstLaunchDate       = "mojito.firstLaunchDate"
    /// User-reported "I donated" flag. Self-attestation only — no payment integration.
    static let donated               = "mojito.donated"
    /// Set of discovered easter-egg IDs (raw values from `EasterEgg`).
    static let easterEggsDiscovered  = "mojito.easterEggs.discovered" // [String]
    /// User's selected skin-tone modifier (raw value from `SkinTone`).
    static let skinTone              = "mojito.skinTone"
    /// Whether `:D` → 😃 style emoticon conversion is active.
    static let emoticonsEnabled      = "mojito.emoticonsEnabled"
    /// Whether the experimental Symbols (★ ⌘ ⌥ ...) extension is included
    /// in fuzzy search.
    static let symbolsEnabled        = "mojito.symbolsEnabled"
    /// When true (and symbols are enabled), `:foo` searches emoji only;
    /// `::foo` is required to search symbols. Keeps the noisy symbols
    /// corpus off the default `:` flow.
    static let symbolsRequireDoubleColon = "mojito.symbols.requireDoubleColon"
    /// Count of DVD-logo corner hits across all the keyword sessions. Drives
    /// the "Perfect Bounce" discovery + the inline counter rendered in the
    /// Easter eggs settings list.
    static let perfectBounceCount    = "mojito.perfectBounce.count"
}
