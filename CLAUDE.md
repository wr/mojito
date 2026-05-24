# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Source of truth
- GitHub: github.com/wr/mojito (this checkout tracks the `gh-pages` branch)
- Linear project: Mojito (id: 08a62212-7546-4dee-b7c4-0ffed3fff097), Personal team (key `W`, issue IDs `W-123`)
- Branch prefix: wells/
- PR mode: ready

## What this is

The `gh-pages` branch of `wr/mojito`, served at <https://mojito.wells.ee> via GitHub Pages. Two distinct things live here:

1. **Marketing site** — `index.html`, `style.css`, `picker.js`, and image assets. Static; no build, no tests, no package manager. To preview, open `index.html` directly or run `python3 -m http.server` in the repo root.
2. **Sparkle update feed** — `appcast.xml`. **Do not hand-edit.** It's overwritten on every release by `scripts/release.sh` on the `main` branch, which then pushes the updated feed here. If you need to change feed format/structure, edit the template in the release script on `main`, not the generated XML here.

The Swift app source lives on the `main` branch (sibling worktree at `/Users/wells/projects/mojito`). That repo has its own CLAUDE.md describing the app — don't duplicate that content here.

## Architecture — `picker.js`

`picker.js` is a working JS reimplementation of the app's emoji picker (`Sources/Mojito/Picker/PickerView.swift` on `main`), used as the live demo on the landing page. ~4000 lines, single IIFE, no framework. Three concerns interleaved:

- **Carousel of mock app windows** (TextEdit, iMessage, Terminal, Mastodon, Reminders). `setActiveApp(idx)` slides the active app in from the right and the previous one out to the left. Honors `prefers-reduced-motion` — that mode skips the slide and shows a single static input.
- **Picker pipeline** — `handleInput → activeQuery → search (fuzzy score) → positionPicker → renderPicker`. `positionPicker` uses a canvas `measureText` to find the pixel offset of the `:` on the current line and anchors the picker there. It flips above the line if it would clip below the hero card. Picker dimensions/colors intentionally mirror the real app — the file header comment names the Swift sources to keep in sync.
- **Autoplay scene loop** — `scenes` table at the bottom drives the demo. Each scene targets one app, optionally prefills text, types `before` + `:query`, lets the picker settle, replaces with the top match, then types `after`. `autoplayToken` is the cancellation primitive: every user input increments it and any in-flight `typeScene` bails when its token goes stale. Don't replace this with `AbortController` — the token survives across `setTimeout` boundaries cleanly.

The embedded shortcode `DB` (lines ~85–3530) is a JS-shaped subset of the app's emojibase data — it's only what the demo needs, not the full table. Don't try to keep it in lockstep with the app's database.

## CSS gotchas (load-bearing — read before editing `style.css`)

- **Dark-mode app overrides must live at the END of `style.css`.** Per-app rules later in the file use the `background:` shorthand, which resets `background-color` and wins the cascade over earlier `@media (prefers-color-scheme: dark)` blocks. Keep two dark-mode blocks: one near the top for `:root` variable overrides, one at the very bottom for `.hero-card` / `.app-*` / pill backgrounds. See `~/.claude/projects/-Users-wells-projects-mojito/memory/css-dark-mode-cascade.md`.
- **macOS Tahoe (26) window chrome spec** (used by every `.app .title-bar` variant): 14px stoplights, 9px gap, 18px padding above/below/left, 50px bar height, 14px squircle corners, **no `border-bottom` on any title bar**. See `~/.claude/projects/-Users-wells-projects-mojito/memory/macos-tahoe-stoplight-spec.md`.
- The picker uses CSS `border-radius: 14px`, not a `clip-path` superellipse — `clip-path` breaks the box-shadow + border, and at 14px the rounded corner is visually indistinguishable from a true squircle anyway. The picker.js header has a comment explaining this; don't reintroduce `clip-path`.
- `style.css` and `picker.js` are referenced with `?v=NN` cache busters in `index.html`. Bump both when shipping a visible change so users on Cloudflare/GitHub Pages caches see it.

## Release / deploy

GitHub Pages serves whatever is on `gh-pages`. Push to deploy. There is no CI step. The release flow that updates `appcast.xml` runs from `main` (`scripts/release.sh <version>` in the sibling repo) and pushes to `gh-pages` as its last step — so during a release window, expect commits to land here from that script, not by hand.
