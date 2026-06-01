# Changelog

Notable changes to Mojito, newest first. Each `## vX.Y.Z` section is the
single source of truth for that release: `scripts/release.sh` extracts it for
both the GitHub Release body and the Sparkle update notes shown in the in-app
updater.

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
