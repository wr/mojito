# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Source of truth
- GitHub: github.com/wr/mojito
- Linear project: Mojito (id: 08a62212-7546-4dee-b7c4-0ffed3fff097), Personal team (key `W`, issue IDs `W-123`)
- Branch prefix: wells/
- PR mode: ready

## What this is

Mojito is a macOS menu-bar utility (`ee.wells.Mojito`, deployment target 14.0) that expands `:emoji:` shortcodes into real emoji in any text field anywhere on macOS. It hooks `CGEventTap` to watch keystrokes globally, runs a state machine over the events, and uses synthetic keyboard events to delete the typed `:query:` and insert the chosen emoji.

## Commands

```bash
# Regenerate Xcode project after editing project.yml or adding/removing Swift files
xcodegen generate

# Debug build (signed with the local "Mojito Dev" identity).
# Debug builds use bundle ID `ee.wells.Mojito.dev`, product name "Mojito Dev",
# and produce "Mojito Dev.app" — so dev TCC grants stay separate from the
# released Mojito.app. The dev build inherits the release app's UserDefaults
# as a fallback layer (see Sources/Mojito/App/main.swift).
xcodebuild -project Mojito.xcodeproj -scheme Mojito -configuration Debug -destination 'platform=macOS' build

# A post-build phase rsyncs Mojito Dev.app to /Applications and — if the app
# was already running — auto-kills + relaunches it so the new binary takes
# over. Cold builds (app not running) don't auto-launch; start manually:
open "/Applications/Mojito Dev.app"

# Full release (Developer ID signing → notarize → staple → Sparkle-sign DMG → gh release → push gh-pages).
# APPLE_TEAM_ID and GITHUB_REPO come from your shell env (e.g. ~/.zshrc or a local .envrc).
scripts/release.sh <version>

# One-time dev environment setup: creates a stable self-signed "Mojito Dev" identity
# in the user keychain so TCC grants survive rebuilds.
scripts/setup-dev-signing.sh

# Rebuild the bundled emoji DB from emojibase (SHA-pinned; mismatched checksums abort)
python3 scripts/build_emoji_db.py

# Refresh Resources/Localizable.xcstrings after adding/changing UI strings.
# Xcode IDE syncs on build; this is the headless equivalent.
scripts/sync-localizable.sh

# Launch Mojito Dev in a specific locale to spot-check translations
# without changing your system language. Kills any running dev instance
# first so SingleInstanceCoordinator doesn't terminate the new launch.
scripts/run-locale.sh fr   # or ja, ar, zh-Hans, etc.

# Run the unit test suite (xcodegen + xcodebuild test). Also wired into the
# pre-push hook below — activate once per clone with the line under it.
scripts/run-tests.sh
git config core.hooksPath .githooks
```

## Testing

Pure-logic unit tests live under `Tests/MojitoTests/` and use Apple's Swift
Testing framework (`@Test` / `#expect`). `scripts/run-tests.sh` regenerates
the Xcode project and runs `xcodebuild test`; the `.githooks/pre-push` hook
calls it, so a failing test blocks `git push` once the hook is enabled.

What's worth testing here: anything pure-logic with no AppKit / AX /
CGEventTap dependency — `TriggerStateMachine`, `FzyScorer`, `FuzzyMatcher`,
`EmojiDatabase`, `SkinTone`, `EmoticonTable`, `AmbientEmoticonTable`,
`SymbolsDatabase`, the regex paths in `ExclusionStore`. What's NOT worth
testing in this repo: anything that touches `AXUIElement`, `CGEventTap`,
`NSPanel`, synthetic `CGEvent` posting, or the focused-element cache —
those need a live AX-permitted environment and tend to break in ways unit
tests don't catch anyway.

`Sources/Mojito/App/main.swift` short-circuits into a bare runloop when
`XCTestConfigurationFilePath` is set, so the test bundle can load into the
host app without firing up the menubar / single-instance / event-tap
machinery.

### Things that have bitten us repeatedly

- **You MUST run `xcodegen generate` after**: adding/removing/renaming a `.swift` file, changing `project.yml`, or touching anything under `Resources/` that's referenced by the build phase. `xcodebuild` will appear to succeed against a stale project without picking up new files.
- **SourceKit cross-file diagnostics lie.** Editing a Swift file in this repo regularly produces `Cannot find type 'PickerViewModel'` / `Cannot find 'PrefsKey'` diagnostics for symbols defined in sibling files. They resolve at build time. Trust `xcodebuild`, not SourceKit, when verifying correctness.
- **Do not switch to ad-hoc signing (`-`).** The "Mojito Dev" self-signed identity is what keeps Accessibility / Input Monitoring TCC grants stable across rebuilds. Every ad-hoc rebuild gets a fresh cdhash and TCC treats it as a different app.
- **Debug builds have their own bundle ID (`ee.wells.Mojito.dev`).** This is intentional — it keeps the dev build's TCC grants, login-item registration, and ⌘-Tab presence fully separate from any released `Mojito.app` on the same Mac. You'll need to grant Accessibility + Input Monitoring once to `Mojito Dev.app` (separately from `Mojito.app`); they'll persist across rebuilds because the "Mojito Dev" code-signing identity is stable. Sparkle is disabled in Debug so the dev build doesn't try to update itself to the release.
- **Don't bump the emoji DB by re-running `build_emoji_db.py` alone.** The script pins SHA256 digests of upstream emojibase files in `EXPECTED_SHA256`. Bumping requires manual review + paste of new digests (the script explains the procedure in its header).
- **`SUPublicEDKey` in `project.yml` must be set before any release.** It's substituted into `Resources/Info.plist` at build time via the `info.properties` block, and `scripts/release.sh` aborts if it's empty. Generate via `./bin/generate_keys` (Sparkle stashes the private key in the login keychain, prints the public key; paste public into `project.yml`).

## Architecture

### Trigger loop

The keystroke pipeline is:

```
KeyMonitor (CGEventTap, .cgSessionEventTap)
   ↓ TriggerInput
TriggerStateMachine (.idle / .capturing(query:))
   ↓ TriggerAction (+ consumesKey)
Engine.apply(action:)
   ↓
TextInserter (synthetic CGEvents) — or one of the easter-egg effects under Sources/Mojito/App/
```

`KeyMonitor.start()` is asserted to run on the main queue via `dispatchPrecondition`. This is load-bearing: the tap's runloop source is added to `CFRunLoopGetCurrent()`, which means the C callback fires on the main thread. The `Engine` delegate methods are declared `nonisolated` and use `MainActor.assumeIsolated` to dispatch synchronously — this is what lets the callback's return value (consume vs pass through) depend on state-machine output. Do not switch to `Task { @MainActor in … }` here; you lose the synchronous return semantics.

### Two insertion modes

`TriggerAction.insertEmoji(query:mode:)` carries an `InsertMode`:

- **`.fromPicker`** — user pressed Return / Tab. The terminating key was consumed (`consumesKey: true`), so the focused app has `:query` (no closing colon) when `Engine.insert` runs synchronously. Delete `query.count + 1` chars and replace.
- **`.exactMatch`** — user typed the closing `:`. The colon was *not* consumed; it passes through. `Engine.apply` defers via `DispatchQueue.main.async` so the closing colon lands in the focused app first, then deletes `query.count + 2` chars. Before falling through to `database.exact(key)`, the exact-match path consults `EggIndex.id(forExactQuery:)` so a registered easter-egg trigger fires instead of inserting an emoji. If neither path matches, the typed `:query:` stays as-is (no surprise replacement). See the easter-egg section below for why those triggers are hashed instead of inlined.

`TriggerAction.checkEmoticon(query:terminator:)` fires when a cancel char (space/punctuation) ends capture. `Engine.handleEmoticon` looks up the table in `EmoticonTable` and decides whether to consume the terminator (e.g. `:)` — terminator is part of the emoticon) or preserve it (e.g. `:D ` — space is just a delimiter).

### Picker

`PickerWindow` is an `NSPanel` (borderless, non-activating, `.statusWindow` level) hosting a SwiftUI `PickerView`. `Engine` defers `show(near:)` by one runloop tick after a keystroke so the focused app processes the key (caret moves) before we ask AX where the caret is — otherwise AX returns stale coordinates.

`FocusedElementCache` is a singleton that maintains the active app's focused `AXUIElement` via an `AXObserver` subscribed to `kAXFocusedUIElementChangedNotification`. `CaretLocator` and `AppContext.focusedFieldIsSecure` read from the cache to avoid a synchronous cross-process AX call on every `:` trigger. `AppDelegate` eagerly initializes the singleton at launch.

### Emoji search

`EmojiDatabase.indexed` is an array of `IndexedEmoji`, each carrying a real `Emoji` plus precomputed `EmojiHaystack` entries (lowercased `[Character]` arrays for every shortcode + label). This is built once at DB load. `FuzzyMatcher.search` iterates `database.indexed` and runs `FzyScorer.score(needle:haystack:)` — a Swift port of John Hawthorn's fzy scoring algorithm. Critically, the search loop **never allocates strings**, which keeps per-keystroke cost in the microseconds.

Special "pinned" rows are appended after the fzy results when the lowercased query hashes to an entry in `EggIndex.prefix` (which already covers 3+ char prefixes of every registered easter-egg trigger). The pinned hexcode is the opaque id (`k01`, `k02`, …) returned by `EggIndex`, so `Engine.insert` and `PickerView` route on that id without ever string-matching the keyword. Symbols (★ ⌘ ⌥ etc.) live in `SymbolsDatabase.indexed()` and get prepended to the corpus only when `PrefsKey.symbolsEnabled` is true.

### Skin tone

`Emoji.supportsSkinTone` is decoded from `k: bool` in `emoji.json`, populated by `build_emoji_db.py` from emojibase's `skins` array. `SkinTone.apply(to:)` inserts the modifier **after the first scalar** of the emoji string — not appended at the end. This matters for ZWJ sequences: `🧔‍♀️` (U+1F9D4 ZWJ U+2640 FE0F) + dark modifier must become `🧔🏿‍♀️` ([1F9D4, 1F3FF, 200D, 2640, FE0F]), not `🧔‍♀️🏿`. The Engine and the picker preview both go through `SkinTone.apply(to:)`.

### Easter eggs

Mojito ships a handful of hidden effects triggered by specific `:keyword:` shortcodes. The triggers and display strings are *deliberately obfuscated* in source:

- `Sources/Mojito/EmojiDB/EggIndex.swift` stores only SHA-256 hashes of the lowercased trigger words (and their 3+ char prefixes). Lookups go through `EggIndex.id(forExactQuery:)` / `.id(forPrefix:)`, which return opaque ids.
- `Sources/Mojito/App/EggStrings.swift` carries the human-readable display strings (banner labels, picker pinned-row text) as XOR-masked bytes.

Goal: `strings <binary>` and a casual repo skim won't surface the list. The hard rule in [Style guidelines → Easter eggs in writing](#easter-eggs-in-writing--hard-rule) below governs how (and how little) to talk about them outside the obfuscated source.

`scripts/build_egg_strings.py` regenerates `EggStrings.swift` from a plaintext `label  text` list piped in via stdin. The plaintext list lives on your disk only — never commit it. The script header explains the XOR encoding and rotation procedure. To add a new egg, also add its hashed forms to `EggIndex.swift` (the script does not currently emit those — they're added by hand alongside the new effect's Swift file).

`Sources/Mojito/App/EasterEggTracker.swift` keeps per-egg "discovered" state in `UserDefaults` and, on first discovery, fires the `AchievementBanner` overlay and the `DiscoveryFanfare` sound (a synthesized square-wave arpeggio — no asset blob). The individual effects each live in their own Swift file under `Sources/Mojito/App/`; the file list is intentionally not enumerated here — see the directory if you need to find one.

### Security / signing posture

- Dev (`Resources/Mojito.dev.entitlements`) carries `cs.disable-library-validation` so the self-signed identity can load Xcode-signed SwiftPM dylibs.
- Release (`Resources/Mojito.entitlements`) is minimal (just `app-sandbox: false`). Library validation stays on — defense against dylib injection.
- `release.sh` re-signs every helper inside `Sparkle.framework` (XPC services, `Updater.app`, `Autoupdate`) explicitly with the Developer ID identity + hardened runtime + secure timestamp. The default SwiftPM-produced signatures use Sparkle's distribution identity and Apple's notary rejects them.
- The release script bumps both `MARKETING_VERSION` (semver, drives `CFBundleShortVersionString` and `sparkle:shortVersionString`) and `CURRENT_PROJECT_VERSION` (integer build number, drives `CFBundleVersion` and `sparkle:version`). Sparkle's version comparison uses the build number, not the marketing version — confusing these caused the v0.1.1 → v0.1.2 update flow to silently no-op the first time.

### What's persisted

UserDefaults only. Keys live in `PrefsKey`. Notably: `usageCounts` (hexcode → int) drives the fuzzy match's frequency boost; `pausedUntil` (timeIntervalSince1970) is read at launch by `AppDelegate` to restore pause state; `firstLaunchDate` is stamped once on the very first launch and shown as "User since" in About. Nothing else is written or transmitted (no telemetry, no analytics).

### Onboarding / Settings windows

Both windows route through `DockIconManager.windowDidOpen()` / `.windowDidClose()`, which ref-counts visible non-menubar windows and toggles `NSApp.setActivationPolicy(.regular / .accessory)` accordingly. When any settings/onboarding window is open, Mojito has a dock icon and shows in ⌘Tab; when the last closes, it drops back to a pure menu-bar app.

`SettingsRoot` uses a `NavigationSplitView` with a manually-managed `NSWindow` (not SwiftUI's `Settings` scene, which is flaky for `.accessory` apps). A small `WindowAccessor` `NSViewRepresentable` reaches up to the hosting `NSWindow` to set `.title` dynamically based on the selected sidebar tab.

## File layout (where to look)

- `Sources/Mojito/App/` — entry point, `Engine`, easter-egg effects + `EasterEggTracker` / `AchievementBanner` / `DiscoveryFanfare` / `EggStrings` (see Easter eggs above), `Shortcuts.swift` (KeyboardShortcuts pause hotkeys), updater, dock-icon manager
- `Sources/Mojito/KeyMonitor/` — `CGEventTap` wrapper + state machine
- `Sources/Mojito/Picker/` — NSPanel + SwiftUI picker + caret positioning
- `Sources/Mojito/EmojiDB/` — emoji/emoticon/symbol data + `FzyScorer` + `EggIndex` (hashed easter-egg lookups)
- `Sources/Mojito/Context/` — frontmost-app/URL detection + focused-AX-element cache
- `Sources/Mojito/Inserter/` — synthetic-keystroke insertion
- `Sources/Mojito/Permissions/` — AX + Input Monitoring permission polling/prompting
- `Sources/Mojito/Exclusions/` — apps / URL patterns Mojito stays out of
- `Sources/Mojito/MenuBar/` — `NSStatusItem` controller
- `Sources/Mojito/Onboarding/`, `Sources/Mojito/Settings/` — SwiftUI window content
- `Sources/Mojito/Util/PrefsKey.swift` — every UserDefaults key in one place
- `scripts/` — `release.sh`, `setup-dev-signing.sh`, `run-tests.sh`, `build_emoji_db.py`, `build_egg_strings.py`, `update_appcast.py`, `sync-localizable.sh`, `translate-localizable.py`, `run-locale.sh`
- `bin/` — vendored `generate_keys` and `sign_update` from Sparkle (committed so release doesn't depend on DerivedData being intact)
- `Resources/` — Info.plist, entitlements, emoji.json, AppIcon.icns, easter-egg assets

## Style guidelines

### Code comments

Be brief. Comment only when the *why* isn't obvious from the code itself —
hidden constraints, subtle invariants, workarounds for specific bugs, behavior
that would surprise a reader. Describe what the code *is*, not what you did or
which user request prompted it. Don't reference tasks, fixes, or callers
("added for X", "handles the case from W-NN") — that belongs in commit
messages / PR descriptions and rots as the code evolves. If removing the
comment wouldn't confuse a future reader, don't write it.

### Easter eggs in writing — hard rule

**Easter-egg specifics never leak outside the obfuscated source.**
A reader of the GitHub repo, issue tracker, branch list, PR list, or
release page should be unable to enumerate the eggs or work out what any
of them does. This is load-bearing for the discovery design implemented
in `EggIndex.swift` (hashed triggers) and `EggStrings.swift` (XOR-masked
display strings) — see [[easter-egg-keyword-obfuscation]].

**Allowed**, anywhere — a bare CRUD acknowledgment and nothing else:

> *added easter eggs* · *fixed easter eggs* · *updated easter eggs* ·
> *removed easter eggs* · *easter-egg polish*

**Forbidden** in commit messages, PR titles/descriptions, branch names,
release notes, tag annotations, Linear issues/comments, GitHub issues,
and code comments:

- The trigger keyword (or any substring or partial spelling of it).
- The egg's display title (e.g. the name shown in About after discovery).
- The opaque id (`kNN`).
- The count of eggs added / changed / removed.
- A description of what the egg does — visual, sound, game, etc.
- A glyph, emoji, or icon associated with it.
- Hints, themes, references, allusions, category, era, or source material.
- The filename of the effect's Swift file (the names spoil the egg).

In short: if a curious onlooker could use what you wrote to narrow down
*which* egg or *what* it does, don't write it. When in doubt, leave it
out. If you need to discuss a specific egg in a place that will be
visible outside the source, *don't* — refactor the discussion into the
code itself (where the obfuscation already lives) or skip it.

## Issue tracking & workflow

Linear + Git workflow lives in `~/.claude/CLAUDE.md` (Linear SSOT + Git workflow sections). The `## Source of truth` block at the top of this file scopes those behaviors to this repo.

Mojito-specific notes:

- **Project URL:** https://linear.app/wells-riley/project/mojito-c138ddd4ca3b
- **Statuses available:** Backlog, Todo, Todo (AI), In Progress, In Review, Done, Canceled, Duplicate.
- **Branches:** `wells/w-NN-short-slug` (lowercase `w-NN` + kebab slug — matches Linear's auto-generated `gitBranchName`).
- **Commits / PR titles:** reference the uppercase ID (e.g. `W-42: fix caret position on Sonoma`) so Linear auto-links.
- **Always open a PR**, even for solo work — don't push directly to `main`. One commit per logical change.
