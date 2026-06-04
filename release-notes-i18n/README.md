# Localized release notes

`CHANGELOG.md` (repo root) is the English source of truth. Each file here is a
**per-locale mirror** of its `## vX.Y.Z` sections, used to render localized
release-notes pages that Sparkle shows in the in-app updater (matched by the
user's preferred language).

One file per locale, named by BCP-47 code: `de.md`, `pt-BR.md`, `zh-Hans.md`,
`ar.md`, … (the 18 non-English locales the app ships). English is never
duplicated here — it comes straight from `CHANGELOG.md`.

## Format

Mirror `CHANGELOG.md`: one `## vX.Y.Z` heading per release, newest first, with
the same body shape. Translate the section headings (`## New` → `## Neu`, …),
the bullet text, and the bold lead-in label; keep verbatim:

- the version heading (`## v1.2.2`),
- PR refs like `([#103](https://github.com/wr/mojito/pull/103))`,
- URLs and `inline code`,
- product names (Mojito, macOS, Sparkle, Giphy, …).

## Adding a release

When you add a `## vX.Y.Z` section to `CHANGELOG.md`, add the translated
section (at the top) to each locale file here. `scripts/release.sh` renders a
locale **only if it has a section for the version being released** — otherwise
that language falls back to English in the updater, so partial coverage is
safe. The rendered set is passed to `scripts/update_appcast.py`, which emits
`xml:lang`-tagged `sparkle:releaseNotesLink` / `fullReleaseNotesLink` entries
(English tagged + first as the no-match fallback).

`ar`, `fa`, `he` render right-to-left (`md_to_release_notes.py --lang` sets
`<html dir>`).
