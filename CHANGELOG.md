# Changelog

Notable changes to Mojito, newest first. Each `## vX.Y.Z` section is the
single source of truth for that release: `scripts/release.sh` extracts it for
both the GitHub Release body and the Sparkle update notes shown in the in-app
updater.

## v1.8.1

## New
- **Install with Homebrew:** `brew install --cask wr/tap/mojito`. ([#167](https://github.com/wr/mojito/pull/167))

## Fixed
- Keystrokes are no longer dropped when the frontmost app hangs or is slow to respond — most visible in Arc. ([#175](https://github.com/wr/mojito/pull/175), [#177](https://github.com/wr/mojito/pull/177))
- Trimmed a rare hitch on the first `:` trigger by keeping accessibility work off the keystroke path. ([#165](https://github.com/wr/mojito/pull/165))

## v1.8.0

## New
- **Insert several emoji in one go:** hold Shift when picking — Shift+Return, Shift+Tab, or Shift+click — and the picker stays open for the next one. Type to search again, plain Return to insert and close. Works in the shortcode list and the full browser grid. ([#163](https://github.com/wr/mojito/pull/163))
- **Custom aliases:** map your own `:word:` to any emoji or symbol in Settings ▸ Aliases — they work alongside the built-in shortcodes. ([#161](https://github.com/wr/mojito/pull/161))

## Fixed
- Per-site exclusions now match subdomains of plain URL patterns (`example.com` covers `app.example.com`). ([#160](https://github.com/wr/mojito/pull/160))
- Per-site exclusions now work in Arc, whose tab URL isn't exposed the usual way. ([#159](https://github.com/wr/mojito/pull/159))
- Shortcut recording in Settings ends cleanly when the window loses focus. ([#162](https://github.com/wr/mojito/pull/162))
- Pickers can no longer be covered by an app's own pop-up windows. ([#155](https://github.com/wr/mojito/pull/155))

## v1.7.0

## New
- **Replace the system emoji picker:** turn it on and ⌃⌘Space — or a tap of the 🌐 Globe key — opens Mojito's emoji browser instead of the macOS Emoji & Symbols panel. Set it up in onboarding or Settings ▸ General. ([#149](https://github.com/wr/mojito/pull/149))
- **Smoother setup:** onboarding now lets you turn features on or off and pick each trigger up front, and ends on a live field to try a shortcut on the spot. ([#153](https://github.com/wr/mojito/pull/153))
- **New app icon** with a Liquid Glass look for macOS Golden Gate. ([#150](https://github.com/wr/mojito/pull/150))

## v1.6.0

## New
- **Search by keyword:** find emoji by meaning, not just the exact shortcode — `:happy` surfaces 😀, `:meditation` finds 🧘, plus `:zen`, `:laugh`, and the rest. ([#145](https://github.com/wr/mojito/pull/145))

## Fixed
- **Clickable picker:** autocomplete results respond to the mouse now — click a row to insert it, and rows highlight on hover. ([#146](https://github.com/wr/mojito/pull/146))

## v1.5.1

## Fixed
- **Update window:** the "Check for Updates" window now reliably comes to the front instead of opening behind other apps — and no longer bounces the Dock icon. ([#138](https://github.com/wr/mojito/pull/138))

## v1.5.0

## New
- **Customizable triggers:** Pick what fires each feature — emoji, symbols, GIF search, and Quick Access. Keep the defaults (`:emoji:`, `::`, `:::`, `:?`) or set your own, like `::emoji::`. Handy in languages that use `:` a lot, or alongside apps that have their own `:` emoji menu. ([#137](https://github.com/wr/mojito/pull/137))

## Fixed
- **Update prompt:** Mojito now comes to the front when it shows the "update available" window, instead of hiding behind other apps. ([#135](https://github.com/wr/mojito/pull/135))

## v1.4.0

## New
- **Easter-egg sound controls:** new switches in Settings → General let you mute the "easter egg found" chime, mute the sounds easter eggs make, or turn easter eggs off entirely. ([#133](https://github.com/wr/mojito/pull/133))

## Fixed
- **"Convert text arrows" now works on its own:** arrow conversion (`->` → →) can be toggled independently of "Convert emoticons." ([#131](https://github.com/wr/mojito/pull/131))
- Easter-egg polish.

## v1.3.0

## New
- **Top emoji:** your most-used emoji now shows in About even at low usage volume ([#123](https://github.com/wr/mojito/pull/123))
- **Compatibility:** updates for macOS 27 ([#127](https://github.com/wr/mojito/pull/127))

## Fixed
- **Web exclusions:** page URLs are now detected via the AXURL attribute, fixing URL matching in more browsers ([#126](https://github.com/wr/mojito/pull/126))
- **Under the hood:** codebase cleanup and small optimizations ([#128](https://github.com/wr/mojito/pull/128))
- Easter-egg polish ([#129](https://github.com/wr/mojito/pull/129))

## v1.2.3

## Fixed
- **Bug fixes and improvements.**
- Easter-egg polish.

## v1.2.2

## New
- **Anonymous usage stats:** Mojito can now share opt-out, fully anonymous aggregate stats — popular emoji, feature usage, your macOS version — and the whole dataset is public at [mojito.wells.ee/stats](https://mojito.wells.ee/stats). Nothing you type is ever included; turn it off anytime in Settings. ([#103](https://github.com/wr/mojito/pull/103))

## Fixed
- **Easter-egg polish.**

## v1.2.1

## New
- **Text arrows:** type `->`, `<-`, or `<->` and they turn into → ← ↔. ([#93](https://github.com/wr/mojito/pull/93))

## Fixed
- **Update window:** now shows release notes, and "Version history" opens the full changelog. ([#95](https://github.com/wr/mojito/pull/95), [#97](https://github.com/wr/mojito/pull/97))
- Easter-egg polish.

## v1.2.0

**New**

- **Browse all emojis** (#68) — a full grid covering the whole library. Open it from the menu-bar menu, a keyboard shortcut, or from Quick Access, then jump between categories and arrow-key around.
- **Quick Access** — type `:?` to pull up your favorites and most-used emoji. Pin the ones you want under Settings → Quick Access.

**Fixed & improved**

- **Symbols** (#88) — `::` search now reaches every symbol macOS can draw: the £ sign and other currencies, Greek letters (`::lambda`, `::Delta`, `::omega`), fractions (`::half`), Braille, and more.
- The picker now opens on the screen with your cursor on multi-monitor setups (#82).
- GIFs paste as a file, so they animate in Slack, Discord, and other apps (#85).
- Easter-egg fixes.

## v1.1.1

- Fixed an issue where Mojito could accidentally trigger in an excluded app.
- Improved debug logs.

## v1.1.0

**New**

- **Allowlist mode for exclusions** — flip your exclusions into an allowlist so Mojito runs *only* in the apps and sites you pick, instead of everywhere except a blocklist.

Plus various fixes and improvements.

## v1.0.8

- Fixed a full-screen effect that could appear oversized on large / 4K displays.

## v1.0.7

- **About → Copy Debug Info** — an anonymized debug report to make support easier.
- **Symbols** — picker entries force text presentation, and un-renderable glyphs are dropped from the corpus.
- **GIF picker** — faster: search and thumbnail loads share one connection.
- **Fixes**
  - Keystrokes pass through correctly during capture in excluded apps and when there's no picker result.
  - Picker keeps its top padding when scrolled to the top.
- Easter-egg additions and polish.

## v1.0.6

Added easter eggs. Find them.

## v1.0.5

**Fix:** GIF search (`:::`) now actually works in the released app. v1.0.4 shipped without the Giphy API key packaged, so the panel showed "API key required" on every search. The key is now baked into builds.

## v1.0.4

**GIF search.** Type `:::` in any text field to pop a Giphy-backed search panel. Arrow keys + Enter to insert inline. Translated into all 19 locales.

Toggle off (or restrict to non-excluded apps) under **Settings → General** and **Settings → Exclusions**. Privacy detail: when on, your query goes to Giphy.

## v1.0.3

**Now available in 18 more languages** 🌍

Mojito's interface is translated into 18 new locales (full list in the GitHub repo). Translations were LLM-drafted and will improve as native speakers review them — corrections welcome.

Plus a help hint for the macOS 26 menu-bar visibility toggle, and small UI polish.

## v1.0.2

- **Smarter emoji search.** Typing `:eye` now surfaces `:eyes:` and `:eye:` ahead of longer shortcodes containing `eye`. Prefix matches now always rank above mid-string matches, regardless of how often you've used the others.
- **Hide the menu bar icon.** New "Show icon in menu bar" preference in Settings → General. When hidden, reopen Settings by launching Mojito from Finder or Spotlight.
- **Tidied Settings layout.** "Rank frequently used emoji higher" moved into the Emoji section. The menu-bar hint now appears inline below the toggle that triggers it.
- **iMessage no longer excluded by default.** Add it to your exclusions list if you prefer the old behavior.

Plus a little easter-egg polish.

## v1.0.1

Bug fixes and polish.

## v1.0.0

Initial release.
