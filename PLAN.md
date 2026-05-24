# Mojito — Plan

A macOS menu bar app that adds Slack-style `:emoji_name:` text entry anywhere you type. Fuzzy matching, inline picker near the caret, per-app/per-website exclusions for places that already have it natively.

> Status: planning. Build starts once Xcode finishes installing.

---

## 1. Goals & non-goals

**Goals**
- Type `:eggpl…` anywhere → see a small popup of fuzzy matches → press `:` or Return → the typed text is replaced with 🍆.
- Works in any AppKit, Catalyst, Electron, web text field on macOS.
- Looks and feels like a first-party Apple utility (think Raycast, Bartender, MacWhisper polish).
- Drop-in install, clear permission onboarding, auto-updates from GitHub.
- Distributable: signed with Developer ID, notarized, code-signed `.dmg`.

**Non-goals (v1)**
- Custom emoji upload (Slack-style images). Unicode only.
- Mobile / iPad version.
- Per-emoji skin-tone picker (use system default; ship later).
- Sandboxed App Store version (incompatible with required permissions).
- Full Markdown / rich shortcut expansion. Only `:emoji:` → emoji.

---

## 2. Core functionality

### 2.1 Trigger model

A small state machine running inside the global keystroke listener:

```
              ┌────────────┐
   any key →  │   Idle     │
              └─────┬──────┘
                    │ user types ":"
                    ▼
              ┌────────────┐
        ┌──── │ Capturing  │ ◄──── shows picker as soon as ≥1 char in query
        │     │ query=""   │
        │     └─────┬──────┘
        │           │
        │  letter / digit / _ / + / - → append, refresh picker
        │  backspace                  → drop last (cancel if empty)
        │  ↑ / ↓                      → navigate picker (key intercepted)
        │  Return / Tab               → insert highlighted (key intercepted)
        │  ":"                        → insert top match (key intercepted)
        │  Esc / space / newline / .  → cancel, key passes through
        │  focus change / click       → cancel
        ▼
   Insertion → back to Idle
```

### 2.2 Insertion mechanics

1. Compute how many characters to delete: `:` + query.count + (`:` if user closed it) = N.
2. Post N synthetic backspace `CGEvent`s to the focused process.
3. Post the chosen emoji string as a synthetic key event with `CGEventKeyboardSetUnicodeString`.

Why not pasteboard? Pasteboard insertion is faster but pollutes clipboard history and triggers clipboard managers. Synthetic keys preserve clipboard and behave identically to typing. Fallback to pasteboard only if synthetic insertion fails (rare — happens in some Electron apps).

### 2.3 Fuzzy matching

- Database: Emojibase (~3,500 Slack-style shortcodes, ~1.8MB JSON, MIT licensed).
- Index: lower-cased shortcode + tags + CLDR name → token list.
- Scoring: prefix match > substring match > subsequence match. Tiebreak: shorter shortcode wins, then frequency-weighted by usage history.
- Limit: top 6 results in picker; arrow keys scroll the rest.

### 2.4 Context detection

Before activating on `:`, check current context:

- `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` → app match.
- If app is a known browser, query AX tree for current URL:
  - Safari: `kAXURLAttribute` on the focused web area.
  - Chrome/Arc/Brave/Edge (Chromium): address bar value via `AXTextField` with role description "address and search bar", or `AXURL` via the experimental Chromium AX tree.
  - Firefox: address bar reads `AXValue` of the URL field.
- Compare against exclusion list (bundle IDs + URL host glob patterns).

If excluded → `:` is not consumed, picker doesn't show, normal typing.

### 2.5 Edge cases

| Case | Behavior |
|---|---|
| Password field (`AXSecureTextField`) | Don't activate; never log keystrokes there. |
| Caret position not exposed by AX | Anchor picker to mouse pointer or last known caret. |
| User pastes `:foo:` | Don't expand pasted text — only typed characters trigger. |
| Two `:` in same word (`a:b:c`) | First `:` starts capture; if next char isn't a name char, cancel. |
| Compound emoji (👨‍👩‍👧) | Emojibase handles ZWJ sequences correctly; insert as-is. |
| Skin tone modifiers | v1: insert default. v2: hold modifier or `:wave::skin-tone-3:`. |
| Permissions revoked at runtime | Disable monitor, flip menu bar icon to red, post non-modal alert. |
| App in background gets `:` typed | Tap is global; only frontmost app's context matters. |

---

## 3. UX walkthrough

### 3.1 First-run onboarding

Five-screen flow in a 600×440 centered window. No skip on permission screens.

```
┌──────────────────────────────────────────┐
│                                          │
│              [ 🍹 Mojito ]               │
│                                          │
│   Type :tada: anywhere. Get 🎉.          │
│                                          │
│        ───── how it works ─────          │
│                                          │
│   You type     →   Mojito shows         │
│   :hear|           ┌─────────────┐      │
│                    │ ❤️  :heart:  │      │
│                    │ 😍 :heart_…│      │
│                    └─────────────┘      │
│   Press : or ↵  →  ❤️                   │
│                                          │
│                    [  Continue  ]        │
└──────────────────────────────────────────┘
```

Screens:

1. **Welcome** — animated demo (looped 4-second clip showing `:tada:` → 🎉 in a TextEdit window). [Continue]
2. **Accessibility permission** — explain *why* (read text caret position to anchor the picker; detect the focused app). Big button: "Open System Settings". Live status indicator (●) below: red until granted, then green. Auto-advance once granted, or [Continue] enables.
3. **Input Monitoring permission** — explain *why* (watch keystrokes for `:` triggers; nothing is stored, nothing is sent). Same flow.
4. **What's excluded by default** — a scrollable list with checkboxes. Slack, Discord, Messages, Notion, Linear, Figma, GitHub.com, etc. all pre-checked. "You can change these anytime in Settings." [Continue]
5. **You're set** — "Mojito lives in your menu bar 🍹. Try typing `:tada:` in any text field." [Get Started] closes onboarding, gentle pulse animation on the menu bar item.

Onboarding state stored in `UserDefaults`; can be re-opened from Settings → "Show onboarding again".

### 3.2 Day-to-day picker UX

The picker is the entire daily UX surface. It needs to feel invisible-when-wrong and inevitable-when-right.

```
┌──────────────────────────────────┐
│  ❤️    heart                     │
│  😍   heart_eyes        ◄ hover  │
│  💕   two_hearts                 │
│  💖   sparkling_heart            │
│  💞   revolving_hearts           │
│  💓   heartbeat                  │
└──────────────────────────────────┘
       ↑ anchored ~6px below caret
```

Details:
- **Width**: 280pt, fixed. Height grows with results, max 6 rows visible.
- **Row height**: 32pt. Emoji 22pt, shortcode 13pt SF Mono / SF Pro.
- **Selection**: subtle accent-tinted background, system accent color.
- **Material**: `.hudWindow` panel style with vibrancy, rounded 10pt corners, subtle 1pt border in dark mode.
- **Anchoring**: caret bottom-left + (0, -6). If caret would put picker off-screen, flip above caret. If still off-screen, pin to nearest screen edge.
- **Animation**: 120ms fade + 4pt slide-in. Keyboard navigation has no animation (instant feedback).
- **Empty state**: if query has no matches, show "No emoji for `:xyz:`" in single row, dimmed. Esc dismisses.
- **Dismissal**: Esc, click outside, focus change, ~5 sec idle without typing.

### 3.3 Menu bar

Status item with a 🍹 SF Symbol (`mug.fill` doesn't exist; we'll use a custom monochrome SVG of a mojito glass that obeys template image rules — flips for dark/light menu bar).

Click reveals:
```
✓  Mojito is on
   ──────────────
   Pause for 1 hour
   Pause until tomorrow
   ──────────────
   Settings…           ⌘,
   Check for Updates…
   About Mojito
   ──────────────
   Quit Mojito         ⌘Q
```

Right-click on the status item also opens this menu (no separate left-click panel in v1).

States:
- Active: filled glass icon
- Paused: outline glass icon, badge
- Permission missing: red exclamation badge

### 3.4 Settings window

SwiftUI `Settings` scene, ~640×500 window, three sidebar tabs (NavigationSplitView), looks like System Settings.

```
┌──────────────────────────────────────────────┐
│ ◉ General      │  Launch at login   [✓]      │
│ ◉ Exclusions   │  Pause shortcut   [⌘⌥M ▾]   │
│ ◉ Permissions  │  Picker theme     [Auto ▾]  │
│ ◉ About        │  Picker accent    [● ● ● ●] │
│                │  Show usage frequency  [✓]  │
│                │                             │
└──────────────────────────────────────────────┘
```

**General**
- Launch at login (uses `SMAppService`)
- Global pause/resume shortcut (uses KeyboardShortcuts library)
- Picker theme: Auto / Light / Dark
- Picker accent color override
- Show usage-frequency boost in fuzzy matching
- Reset usage history

**Exclusions**
- Two sub-sections: **Apps** and **Websites**.
- Apps: list of bundle IDs with app icon + name. [+] picks an app; [-] removes selected.
- Websites: list of host or glob patterns (`mail.google.com`, `*.notion.so`). [+] adds, [-] removes. "Add current tab" button reads frontmost browser URL.
- Pre-seeded list visible, user can untoggle individually.
- Search field at top.

**Permissions**
- Three rows: Accessibility ●, Input Monitoring ●, Notifications (optional, for "update available" toasts) ●.
- Each row: status indicator + "Open System Settings" button + last-checked timestamp.

**About**
- Version, build, "Check for updates" button.
- Links: GitHub, report issue, license, privacy policy.
- Credits: Emojibase, Sparkle, KeyboardShortcuts, etc.

---

## 4. Visual design

### 4.1 Aesthetic direction

Tahoe-era Apple utility. Translucent vibrancy where it makes sense (picker, settings sidebar), opaque elsewhere. Generous spacing. SF Pro / SF Pro Rounded for headers, SF Mono for shortcodes. Accent color = system (defaults to light blue but respects user's macOS accent).

App icon: a stylized mojito glass viewed from the side, simple, two-tone (mint green + glass white), with a tiny lime wedge. Designed to read at 16pt menu bar size and 1024pt launchpad.

### 4.2 Picker spec

```
Window
├── NSPanel (borderless, .floating, .nonactivating, ignoresMouseEvents: false)
│   ├── NSVisualEffectView (.hudWindow, .behindWindow, .active)
│   └── NSHostingView<PickerView>
│       ├── ForEach result row
│       │   ├── Text(emoji).font(.system(size: 22))
│       │   ├── Text(shortcode).font(.system(size: 13))
│       │   └── if hovered/selected: rounded rect background
│       └── divider + "↑↓ select   ↵ insert   esc dismiss" footer (10pt, dimmed)
```

Picker is a single SwiftUI view; selection state is a `@State Int`. Keyboard nav handled outside SwiftUI (in KeyMonitor) since we need to intercept arrows globally; KeyMonitor mutates an `@ObservableObject` view model.

### 4.3 Onboarding screens

Card-style 600×440 modal-but-not-modal (ordered front, but doesn't block other apps). Each screen is its own SwiftUI view inside a `TabView` with custom dot indicator. Hero illustration top, one-paragraph copy, single primary button bottom-right, optional secondary "Back" bottom-left.

Hero illustrations: lightweight SwiftUI vector compositions, no PNGs. Animated where helpful (subtle, looping ≤4s).

### 4.4 Color & typography tokens

```
Picker.background    = NSVisualEffectView .hudWindow
Picker.border        = white @ 8% (dark) / black @ 8% (light)
Picker.cornerRadius  = 10
Picker.shadow        = 0px 4px 16px rgba(0,0,0,0.18)

Row.idle             = .clear
Row.hover            = .primary @ 6%
Row.selected         = .accentColor @ 18%

Text.shortcode       = .secondary, .system(size: 13)
Text.shortcut.match  = .primary  (matched chars get bold)

Onboarding.title     = .system(size: 28, weight: .semibold, design: .rounded)
Onboarding.body      = .system(size: 14)
Onboarding.button    = .borderedProminent, controlSize: .large
```

---

## 5. Auto-updating

Use **Sparkle 2** (`https://sparkle-project.org`). Industry standard, free, MIT, supports EdDSA-signed appcasts.

### 5.1 Setup

- Add Sparkle via Swift Package Manager: `https://github.com/sparkle-project/Sparkle`.
- Generate EdDSA key pair; private key stored on developer machine, public key embedded in `Info.plist` as `SUPublicEDKey`.
- Host an `appcast.xml` at `https://mojito.app/appcast.xml` (or a GitHub Pages URL like `https://wells.github.io/mojito/appcast.xml`).
- Releases:
  1. Build, notarize, staple `Mojito-x.y.z.dmg`.
  2. Run `sign_update Mojito-x.y.z.dmg` → produces signature.
  3. Update `appcast.xml` with new entry, signature, version, release notes URL.
  4. Push DMG and appcast to release hosting.
  5. Tag GitHub release.

### 5.2 In-app behavior

- Check for updates on launch (after a 30s delay) and every 24h.
- "Update available" → non-modal Sparkle dialog with release notes (Markdown rendered).
- User clicks "Install Update" → Sparkle downloads, verifies signature, relaunches.
- Settings → "Check for Updates" forces immediate check.
- Optional: opt-in "include beta channel" toggle → use a second appcast URL.

### 5.3 GitHub-only flavor

If you don't want a separate website: use a GitHub Action to publish `appcast.xml` to the `gh-pages` branch on each tagged release. Sparkle reads it from `https://wells.github.io/mojito/appcast.xml`.

---

## 6. Settings persistence

Two layers:

- **`UserDefaults`** for prefs (theme, accent override, show-frequency boost, exclusion lists, onboarding-seen flag, last-update-check, paused-until timestamp).
- **`~/Library/Application Support/Mojito/usage.sqlite`** for emoji usage counts (small SQLite DB via GRDB or even just a JSON file in v1). Powers frequency-weighted ranking.

All settings backed up via iCloud Drive automatically (Application Support is in the iCloud backup set if user has it on; for explicit sync we'd need CloudKit — out of scope v1).

---

## 7. Tech stack & dependencies

| Concern | Choice | Why |
|---|---|---|
| Language | Swift 5.10 | Stable, modern, full AppKit access. |
| UI | SwiftUI for settings/onboarding/picker rows | Faster iteration. AppKit only for `NSPanel` host and `NSStatusItem`. |
| Build | Xcode project (`.xcodeproj`) | Required for entitlements, code-signing, notarization. SPM also possible but Xcode is cleaner for distribution. |
| Min target | macOS 14 (Sonoma) | Lets us use modern SwiftUI APIs and `SMAppService.mainApp.register` for login. |
| Auto-update | Sparkle 2 | De facto standard. |
| Hotkeys | `sindresorhus/KeyboardShortcuts` (SPM) | Saves writing Carbon hotkey wrapper. MIT. |
| Login at launch | `SMAppService` (system) | Modern replacement for deprecated LSSharedFileList. |
| Emoji DB | Emojibase JSON (vendored) | MIT, comprehensive, Slack-compatible shortcodes. |
| Fuzzy match | Hand-rolled scorer | ~150 LOC. No need for a big dep. |
| Crash reporting | None in v1 | Add Sentry or KSCrash later if useful. |

---

## 8. Permissions architecture

```
PermissionsCoordinator (singleton, ObservableObject)
├── @Published accessibilityGranted: Bool
├── @Published inputMonitoringGranted: Bool
├── @Published notificationsGranted: Bool
│
├── checkAll() — called every 1s while onboarding is open, every 10s otherwise
│   ├── accessibility: AXIsProcessTrusted()
│   ├── input monitoring: IOHIDCheckAccess(.keyboard) == .granted
│   └── notifications: UNUserNotificationCenter authorization status
│
├── requestAccessibility() — opens System Settings deep link, prompts via AXIsProcessTrustedWithOptions
└── requestInputMonitoring() — opens deep link; macOS auto-prompts on first CGEventTap creation
```

Deep links (Sequoia+):
- `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
- `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`

If KeyMonitor is started before Input Monitoring is granted, the tap returns `nil`. We watch for that and re-attempt once the coordinator flips to granted.

---

## 9. Distribution

### 9.1 Signing

- Apple Developer Program account ($99/yr) — need this for a Developer ID Application certificate.
- Set `DEVELOPMENT_TEAM` in Xcode project.
- "Sign to Run Locally" for dev builds; "Developer ID Application" for release.

### 9.2 Notarization

- Build `Mojito.app` with `xcodebuild -scheme Mojito -configuration Release`.
- Wrap in DMG with `create-dmg` (or hdiutil).
- `xcrun notarytool submit Mojito.dmg --keychain-profile "AC_PASSWORD" --wait`.
- `xcrun stapler staple Mojito.dmg`.
- Verify: `spctl -a -t open --context context:primary-signature -v Mojito.dmg`.

### 9.3 GitHub release flow

A `release.sh` script in repo root will:
1. Bump `MARKETING_VERSION`.
2. Build, notarize, staple.
3. Sign DMG for Sparkle.
4. Upload DMG to GitHub release.
5. Update appcast.xml on `gh-pages`.
6. Tag and push.

This script is run manually; CI later if useful.

---

## 10. Roadmap

**v0.1 (POC, maybe 1 evening)**
- Single hardcoded shortcode `:tada:` → 🎉.
- CGEventTap working, synthetic insertion working in TextEdit.
- No picker UI yet.

**v0.2**
- Real Emojibase DB + fuzzy matcher.
- Picker NSPanel anchored to mouse pointer.
- Menu bar icon, quit menu item.

**v0.3**
- AX caret positioning.
- Pre-seeded exclusions for Slack, Discord, Messages.
- Settings window — Exclusions tab functional.

**v0.4**
- Full onboarding flow.
- Permissions coordinator + deep links.
- Polished picker visuals.

**v0.5**
- Sparkle integrated, appcast URL stubbed.
- Settings: General + Permissions + About tabs.
- Login at launch.

**v1.0**
- Notarized DMG + GitHub release.
- Website (optional) or just README on GitHub.
- First public release.

**v1.1+ (parking lot)**
- Skin tone modifiers.
- Custom shortcodes (user-defined `:wells:` → `🧙‍♂️`).
- Recently-used row at top of picker.
- Per-app default skin tone overrides.
- iCloud sync for settings + usage.

---

## 11. Open risks & questions

1. **Caret positioning in Electron apps** (VS Code, Slack web, Notion app) — AX exposure is inconsistent. Worst case: anchor to mouse for those apps.
2. **Synthetic insertion in Electron** — sometimes the unicode-event approach drops characters. Pasteboard fallback covers this but pollutes clipboard.
3. **Permission revocation by macOS after updates** — major macOS upgrades sometimes reset TCC; we need clear in-app messaging when this happens.
4. **Browser URL detection across many browsers** — Chrome/Arc/Brave/Edge share the AX tree; Safari is its own thing; Firefox is its own. Need real testing in each.
5. **Apple's `:emoji:` autocomplete in Notes/Pages on Sequoia+** — they've been adding system-level expansion in some apps. Add those to default exclusions if conflicts emerge.
6. **Notarization wait time** — first submission can take 5–60 min from Apple. Plan releases accordingly.

---

## 12. Decisions still needed (when you're back)

- Confirm minimum macOS target (14 Sonoma seems right; you're on 26 Tahoe).
- Pick app icon style (I'll mock 2–3 options).
- Pick distribution host: GitHub Releases only, or also a small landing page?
- Beta channel: yes/no for v1?
- Any analytics/telemetry, even anonymous? (Default: no.)
