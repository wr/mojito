---
description: Build, notarize, and ship a new Mojito release
argument-hint: <version> e.g. 0.3.0
---

# Release Mojito

Drive a full release of Mojito end-to-end: pre-flight checks → build & sign → notarize → Sparkle-sign → GitHub release → appcast update → commit & push the version bump.

The user invoked: `/release $ARGUMENTS`

If `$ARGUMENTS` is empty, ask the user for the target version (e.g. `0.3.0`) and stop. Otherwise treat `$ARGUMENTS` as `<version>` (strip a leading `v` if present).

---

## Step 1 — Pre-flight (read-only; bail loudly if anything fails)

Run these in parallel, then report the results:

```bash
# Working tree state — release.sh will mutate project.yml; nothing else should be dirty.
git status --porcelain

# Confirm we're on main and up to date.
git rev-parse --abbrev-ref HEAD
git fetch origin main --quiet && git rev-list --left-right --count main...origin/main

# Required tools.
command -v xcodebuild xcodegen create-dmg gh python3
xcrun --find notarytool stapler

# Required env vars (mirror scripts/release.sh).
printenv APPLE_TEAM_ID GITHUB_REPO

# Notarytool keychain profile exists.
xcrun notarytool history --keychain-profile AC_PASSWORD 2>&1 | head -3

# Sparkle keypair: public key must be embedded.
plutil -extract SUPublicEDKey raw Resources/Info.plist

# What version are we coming from?
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" project.yml
```

**Fail-fast checks** — stop and report if any of these are true:

- Working tree has changes other than possibly `project.yml` / `Mojito.xcodeproj/project.pbxproj`. If there are unrelated edits, ask the user whether to stash them first.
- Branch is not `main`, or local main is behind `origin/main`.
- Any required tool is missing — tell the user to `brew install create-dmg gh` or install Xcode CLT.
- `APPLE_TEAM_ID` or `GITHUB_REPO` is unset.
- `notarytool history` errors with "keychain item not found" — instruct the user to run once:
  `xcrun notarytool store-credentials AC_PASSWORD --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PWD"`
- `SUPublicEDKey` is missing or null — instruct the user to run `./bin/generate_keys`, paste the public key into `project.yml`, then `xcodegen generate`.
- Requested version is not strictly greater than the current `MARKETING_VERSION` (semver compare). If it isn't, ask the user to confirm a downgrade or correction.
- Sanity-check that a Debug build compiles before kicking off the release: `xcodebuild -project Mojito.xcodeproj -scheme Mojito -configuration Debug -destination 'platform=macOS' build` (tail the output, only proceed on `BUILD SUCCEEDED`).

## Step 2 — Collect release notes

Ask the user for release notes in markdown. Suggest a starter template based on `git log --oneline` since the last tag:

```bash
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [[ -n "$LAST_TAG" ]]; then
    git log --oneline "$LAST_TAG..HEAD"
fi
```

Show the user the commit list and ask them to either (a) write notes directly, or (b) tell you to draft from the commits and have them approve. Save the final notes to a temp file path you'll reuse in Step 4. Don't proceed until the user approves.

## Step 3 — Run release.sh

```bash
scripts/release.sh <version>
```

This script:

1. Bumps `MARKETING_VERSION` to `<version>` and auto-increments `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Runs `xcodegen generate` (so `project.pbxproj` updates).
3. Builds Release with `Developer ID Application` signing + hardened runtime + secure timestamp.
4. Re-signs every helper inside `Sparkle.framework` (XPC services, `Updater.app`, `Autoupdate`) — SwiftPM's default Sparkle signatures are rejected by Apple notary.
5. Wraps `Mojito.app` in a DMG via `create-dmg`.
6. Submits to `notarytool` (waits ~2–10 min), then staples.
7. Calls `./bin/sign_update` to produce an EdDSA signature for the DMG.
8. `gh release create v<version>` with the DMG attached. Release notes are placeholder "TODO" — you will replace them in Step 4.
9. Clones the `gh-pages` branch to a tempdir, runs `scripts/update_appcast.py` to prepend the new release entry, commits, and pushes.

Do **not** suppress output — surface the script's progress so the user can see notarization timing. If the script exits non-zero at any step, stop the skill and report the failure with the last 30 lines of output.

## Step 4 — Replace the placeholder release notes

```bash
gh release edit "v<version>" --repo "$GITHUB_REPO" --notes-file <path-from-step-2>
```

Verify with:

```bash
gh release view "v<version>" --repo "$GITHUB_REPO"
```

## Step 5 — Commit and push the version bump

The release script mutated `project.yml` and `Mojito.xcodeproj/project.pbxproj` but didn't commit them. Do that now so `main` reflects what was shipped:

```bash
git add project.yml Mojito.xcodeproj/project.pbxproj
git commit -m "Release v<version>"
git push origin main
```

Note: the git tag `v<version>` created by `gh release create` points at the commit *before* this bump. That's harmless — Sparkle pulls the DMG from the release asset URL, not from the tag. If you want the tag to match the bump commit, you'd have to delete and recreate it (`git push --delete origin "v<version>" && git tag -f "v<version>" && git push origin "v<version>"`). Skip this unless the user asks.

## Step 6 — Post-release verification

Run in parallel and report results:

```bash
# Release exists with the DMG attached.
gh release view "v<version>" --repo "$GITHUB_REPO" --json assets,name,tagName

# Appcast contains the new entry.
curl -sf "https://wr.github.io/mojito/appcast.xml" | head -40

# Sparkle EdDSA signature on the appcast matches what was uploaded.
curl -sf "https://wr.github.io/mojito/appcast.xml" | grep -A1 "v<version>" | grep -o 'sparkle:edSignature="[^"]*"'
```

Confirm to the user:

- Release URL: `https://github.com/$GITHUB_REPO/releases/tag/v<version>`
- DMG path on disk: `dist/Mojito-<version>.dmg`
- Reminder: to test the update flow, launch a previously-installed older copy of Mojito and use **Mojito → Check for Updates** — Sparkle should offer the new version.

---

## Gotchas

- **Apple Notary can be slow.** Step 3 may hang for 5–15 min on `notarytool submit`. Don't kill it. If it actually fails, `xcrun notarytool log <submission-id> --keychain-profile AC_PASSWORD` shows why.
- **`spctl` pre-notarization assessment failure is expected** on the first signing of a build. The script warns but continues. The post-stapling DMG is what matters.
- **Sparkle private key.** The script reads it from your login keychain by default (where `./bin/generate_keys` stashed it). If you've moved machines, restore the keychain item or set `SPARKLE_PRIVATE_KEY_PATH=/path/to/exported.key`. Losing the key means anyone on a prior version can never auto-update again.
- **Don't switch to ad-hoc signing.** The "Mojito Dev" identity is for *Debug* only. Release must use `Developer ID Application` — the script enforces this.
- **Don't bump the emoji DB in the same release** unless you also re-pinned `EXPECTED_SHA256` in `scripts/build_emoji_db.py` and reviewed the diff.
