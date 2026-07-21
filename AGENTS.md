# AGENTS.md

Guidance for coding agents (Claude Code, Codex) working in this repository. Single source of truth — CLAUDE.md just imports this file.

## Source of truth
- GitHub: github.com/wr/mojito (this checkout tracks the `gh-pages` branch)
- Linear project: Mojito (id: 08a62212-7546-4dee-b7c4-0ffed3fff097), Personal team (key `W`, issue IDs `W-123`)
- Branch prefix: wells/
- PR mode: ready

## What this is

The `gh-pages` branch of `wr/mojito`, served at <https://mojito.wells.ee> via GitHub Pages. Three distinct things live here:

1. **Marketing site** — `index.html`, `style.css`, `picker.js`, and image assets. Static; no build, no tests, no package manager. To preview, open `index.html` directly or run `python3 -m http.server` in the repo root.
2. **Sparkle update feed** — `appcast.xml`. **Do not hand-edit.** It's overwritten on every release by `scripts/release.sh` on the `main` branch, which then pushes the updated feed here. If you need to change feed format/structure, edit the template in the release script on `main`, not the generated XML here.
3. **Stats page** — `stats.html` / `stats.css` / `stats-live.js` (see its own section below).

The Swift app source lives on the `main` branch (sibling worktree at `../mojito`). That repo has its own CLAUDE.md describing the app — don't duplicate that content here.

## Stats page — `stats.html`

A public "Mojito, by the numbers" page at <https://mojito.wells.ee/stats>. Three files: `stats.html` (markup), `stats.css`, `stats-live.js`.

- **Sample data is baked into the markup** so the page renders correctly before JS runs and as a fallback if the API is down. On a successful fetch the live data always wins — even all-zeros (pre-launch), which renders a tidy placeholder instead of stale sample.
- **Data source:** `stats-live.js` fetches `/api/stats.json` from two endpoints in order — `stats.mojito.wells.ee` (prod), then `mojito-stats.wells-riley.workers.dev` (the Cloudflare Worker behind it) — with a 4s abort timeout; if both fail it keeps the sample.
- **Sections:** big-number tiles, top-emoji rows, an insertion-type mix bar, distribution bars (macOS version / arch / app version / language), and a feature-usage grid. Language/feature/skin-tone label maps live at the top of `stats-live.js`.
- Shares `style.css` with the marketing site plus its own `stats.css`, both cache-busted `?v=NN` — bump on any visible change.

## Architecture — `picker.js`

`picker.js` is a working JS reimplementation of the app's emoji picker (`Sources/Mojito/Picker/PickerView.swift` on `main`), used as the live demo on the landing page. ~4000 lines, single IIFE, no framework. Three concerns interleaved:

- **Carousel of mock app windows** (TextEdit, iMessage, Terminal, Mastodon, Reminders). `setActiveApp(idx)` slides the active app in from the right and the previous one out to the left. Honors `prefers-reduced-motion` — that mode skips the slide and shows a single static input.
- **Picker pipeline** — `handleInput → activeQuery → search (fuzzy score) → positionPicker → renderPicker`. `positionPicker` uses a canvas `measureText` to find the pixel offset of the `:` on the current line and anchors the picker there. It flips above the line if it would clip below the hero card. Picker dimensions/colors intentionally mirror the real app — the file header comment names the Swift sources to keep in sync. `activeQuery` also detects the app's other triggers by counting the colon run: `::` searches a small embedded `SYMBOLS` table (same picker UI, rows render as `::code`), and `:::` opens the mock GIF panel (`#gif-panel`, canned thumbnails in `gifs/`, iMessage-only — the pick is "sent" as a bubble).
- **Autoplay scene loop** — `scenes` table at the bottom drives the demo. Each scene targets one app, optionally prefills text, types `before` + `:query`, lets the picker settle, replaces with the top match, then types `after`. `autoplayToken` is the cancellation primitive: every user input increments it and any in-flight `typeScene` bails when its token goes stale. Don't replace this with `AbortController` — the token survives across `setTimeout` boundaries cleanly.

The embedded shortcode `DB` (lines ~85–3530) is a JS-shaped subset of the app's emojibase data — it's only what the demo needs, not the full table. Don't try to keep it in lockstep with the app's database.

## CSS gotchas (load-bearing — read before editing `style.css`)

- **Dark-mode app overrides must live at the END of `style.css`.** Per-app rules later in the file use the `background:` shorthand, which resets `background-color` and wins the cascade over earlier `@media (prefers-color-scheme: dark)` blocks. Keep two dark-mode blocks: one near the top for `:root` variable overrides, one at the very bottom for `.hero-card` / `.app-*` / pill backgrounds. See `~/.claude/projects/-Users-wells-projects-mojito/memory/css-dark-mode-cascade.md`.
- **macOS Tahoe (26) window chrome spec** (used by every `.app .title-bar` variant): 14px stoplights, 9px gap, 18px padding above/below/left, 50px bar height, 14px squircle corners, **no `border-bottom` on any title bar**. See `~/.claude/projects/-Users-wells-projects-mojito/memory/macos-tahoe-stoplight-spec.md`.
- The picker uses CSS `border-radius: 14px`, not a `clip-path` superellipse — `clip-path` breaks the box-shadow + border, and at 14px the rounded corner is visually indistinguishable from a true squircle anyway. The picker.js header has a comment explaining this; don't reintroduce `clip-path`.
- `style.css` and `picker.js` are referenced with `?v=NN` cache busters in `index.html`. Bump both when shipping a visible change so users on Cloudflare/GitHub Pages caches see it.

## Release / deploy

GitHub Pages serves whatever is on `gh-pages`. Push to deploy. There is no CI step. The release flow that updates `appcast.xml` runs from `main` (`scripts/release.sh <version>` in the sibling repo) and pushes to `gh-pages` as its last step — so during a release window, expect commits to land here from that script, not by hand.

## Pre-publish checks

`scripts/check.sh` validates the site before push: image compression, html/css/js lint, OG/Twitter/SEO metadata, internal + external links (lychee), Lighthouse (perf/SEO/a11y/best-practices, mobile + desktop, against a local server). A `pre-push` hook runs it automatically.

```bash
brew bundle && npm install      # one-time: system + node deps
./scripts/install-hooks.sh      # one-time: wire up the pre-push hook
./scripts/check.sh              # run all checks manually
```

Flags: `--skip-{images,lint,meta,links,lighthouse}`, `--no-external` (offline link check), `--ci` (image script reports deltas instead of staging). Individual checks under `scripts/checks/` are standalone.

The hook **self-skips when the only file in the push is `appcast.xml`** so the `main`-branch release script's auto-push isn't gated. Emergency bypass: `git push --no-verify`.
