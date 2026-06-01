#!/usr/bin/env bash
#
# Release script for Mojito.
#
# Usage:  scripts/release.sh <version>
# Env vars expected (set up once, then forget):
#   APPLE_ID                — your Apple ID email
#   APPLE_TEAM_ID           — your 10-char team ID
#   APPLE_APP_SPECIFIC_PWD  — app-specific password from appleid.apple.com
#   GITHUB_REPO             — e.g. wr/mojito
#
# Optional:
#   SPARKLE_PRIVATE_KEY_PATH — path to an exported EdDSA private key file. If
#                              unset (recommended), sign_update reads the key
#                              from your login keychain — that's where
#                              ./bin/generate_keys stored it.
#
# What it does:
#   1. Builds Release with Xcode, signed with Developer ID.
#   2. Wraps Mojito.app in a DMG with create-dmg.
#   3. Submits the DMG to Apple notarytool, waits, staples.
#   4. Signs the DMG with Sparkle's EdDSA key, captures the signature.
#   5. Creates a GitHub Release with the DMG attached (via gh CLI).
#   6. Updates appcast.xml on the gh-pages branch with the new entry.
#
# Things you must do before this works:
#   - Apple Developer Program membership ($99/yr).
#   - Developer ID Application certificate installed in your login keychain.
#   - Run once:  xcrun notarytool store-credentials AC_PASSWORD --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PWD"
#   - Generate a Sparkle keypair (only once):  ./bin/generate_keys
#     The PUBLIC key it prints goes into project.yml under SUPublicEDKey
#     (then `xcodegen generate`). The PRIVATE key stays in your keychain.
#     To export it for backup:  ./bin/generate_keys -x mojito-sparkle.key
#     (store that file somewhere safe — losing it means users on old versions
#     can never be auto-updated again.)
#   - brew install create-dmg gh
#
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: $0 <version>  (e.g. 0.2.0)" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Load project-local env (gitignored). Holds APPLE_TEAM_ID, GITHUB_REPO,
# and any other developer-specific values that shouldn't be in version control.
if [[ -f "$REPO_ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$REPO_ROOT/.env"
    set +a
fi

require() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        echo "error: $var is not set" >&2
        exit 1
    fi
}
require APPLE_TEAM_ID
require GITHUB_REPO

# Refuse to release if the Sparkle EdDSA public key isn't embedded. Shipping
# with an empty SUPublicEDKey means Sparkle would have no signature anchor to
# verify against — even though SUFeedURL is HTTPS, that's not a substitute for
# update signing (DNS, CDN, or a compromised gh-pages branch could all serve
# malicious payloads).
INFO_PLIST="$REPO_ROOT/Resources/Info.plist"
SU_PUBKEY=$(plutil -extract SUPublicEDKey raw "$INFO_PLIST" 2>/dev/null || true)
if [[ -z "$SU_PUBKEY" || "$SU_PUBKEY" == "<null>" ]]; then
    echo "error: SUPublicEDKey in Resources/Info.plist is empty." >&2
    echo "       Generate a keypair once with Sparkle's generate_keys tool:" >&2
    echo "         ./bin/generate_keys" >&2
    echo "       Put the PUBLIC key into project.yml under SUPublicEDKey," >&2
    echo "       run 'xcodegen generate', and store the PRIVATE key at" >&2
    echo "       \$SPARKLE_PRIVATE_KEY_PATH (chmod 600). Never commit it." >&2
    exit 1
fi

BUILD_DIR="$REPO_ROOT/build/release"
APP_NAME="Mojito"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
# Single DMG per release, named without a version suffix. The version is
# already encoded in the GitHub release tag (`/v$VERSION/Mojito.dmg`), so
# Sparkle still resolves a unique URL per release while the marketing site
# can keep linking to /releases/latest/download/Mojito.dmg.
DMG_PATH="$REPO_ROOT/dist/$APP_NAME.dmg"

mkdir -p "$BUILD_DIR" "$(dirname "$DMG_PATH")"

echo "→ Bumping version to $VERSION"
# Update marketing version (drives CFBundleShortVersionString).
sed -i '' -E "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml

# Auto-bump CURRENT_PROJECT_VERSION (drives CFBundleVersion + sparkle:version).
# Sparkle compares THIS field (not the marketing version) for upgrade decisions,
# so it must monotonically increase across releases.
CURRENT_BUILD=$(sed -nE 's/.*CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' project.yml)
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" project.yml
echo "   marketing: $VERSION"
echo "   build:     $NEW_BUILD"

xcodegen generate

echo "→ Building Release"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    clean build

echo "→ Re-signing nested helpers (Sparkle XPC services + frameworks)"
# Xcode's SwiftPM build leaves Sparkle's helpers signed with Sparkle's
# distribution identity, not our Developer ID. Apple notarization rejects
# this. We re-sign every helper bottom-up with our Developer ID + a secure
# timestamp + hardened runtime.
#
# The order matters: deepest items first, then bundles that contain them.
# Signing the same path twice is idempotent — codesign just replaces.
SIGN_IDENTITY="Developer ID Application"
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE_FW/Versions/B"

SPARKLE_HELPERS=(
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
    "$SPARKLE_VERSION/XPCServices/Installer.xpc"
    "$SPARKLE_VERSION/Updater.app"
    "$SPARKLE_VERSION/Autoupdate"
    "$SPARKLE_FW"
)
for target in "${SPARKLE_HELPERS[@]}"; do
    if [[ -e "$target" ]]; then
        codesign --force --sign "$SIGN_IDENTITY" \
            --timestamp --options runtime \
            "$target"
    fi
done

# Catch-all: any other dylibs or frameworks SwiftPM produced.
while IFS= read -r -d '' target; do
    case "$target" in
        "$SPARKLE_FW"*) continue ;;
    esac
    codesign --force --sign "$SIGN_IDENTITY" \
        --timestamp --options runtime \
        "$target" >/dev/null 2>&1 || true
done < <(find "$APP_PATH/Contents/Frameworks" \
            \( -name "*.dylib" -o -name "*.framework" \) \
            -print0 2>/dev/null | sort -rz)

echo "→ Re-signing app shell"
codesign --force --sign "$SIGN_IDENTITY" \
    --timestamp --options runtime \
    --entitlements "$REPO_ROOT/Resources/Mojito.entitlements" \
    "$APP_PATH"

echo "→ Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" || {
    echo "warning: spctl pre-notarization assessment failed (expected on first run)"
}

echo "→ Creating DMG"
rm -f "$DMG_PATH"
create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "$APP_NAME.app" 140 180 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 400 180 \
    "$DMG_PATH" \
    "$APP_PATH"

echo "→ Notarizing"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "AC_PASSWORD" \
    --wait

echo "→ Stapling"
xcrun stapler staple "$DMG_PATH"

echo "→ Signing for Sparkle"
# Prefer the keychain-stored key (default for sign_update in Sparkle 2.x).
# Fall back to the file path if the user has explicitly exported a key.
if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" ]]; then
    SIGN_OUTPUT=$(./bin/sign_update -f "$SPARKLE_PRIVATE_KEY_PATH" "$DMG_PATH" 2>&1)
else
    SIGN_OUTPUT=$(./bin/sign_update "$DMG_PATH" 2>&1)
fi
echo "$SIGN_OUTPUT"
EDDSA_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(stat -f%z "$DMG_PATH")

if [[ -z "$EDDSA_SIGNATURE" ]]; then
    echo "error: could not parse Sparkle signature" >&2
    exit 1
fi

echo "→ Extracting release notes for v$VERSION from CHANGELOG.md"
# Pull the body of the `## v$VERSION` section (everything up to the next `##`).
# This fragment is the single source of truth for both the GitHub Release body
# and the Sparkle HTML notes, so the two can never drift apart.
CHANGELOG_FRAGMENT=$(mktemp)
# Stop at the next *version* heading, not any `## ` — the per-release body
# now uses `## New` / `## Fixed` section headings that must be captured.
awk -v header="## v$VERSION" '
    $0 == header { capture = 1; next }
    capture && /^## v[0-9]/ { exit }
    capture { print }
' "$REPO_ROOT/CHANGELOG.md" > "$CHANGELOG_FRAGMENT"
if [[ ! -s "$CHANGELOG_FRAGMENT" ]]; then
    echo "error: no '## v$VERSION' section found in CHANGELOG.md." >&2
    echo "       Add a '## v$VERSION' entry before releasing." >&2
    exit 1
fi

echo "→ Creating GitHub Release"
RELEASE_NOTES_FILE=$(mktemp)
{
    echo "## $APP_NAME $VERSION"
    echo ""
    cat "$CHANGELOG_FRAGMENT"
} > "$RELEASE_NOTES_FILE"

gh release create "v$VERSION" "$DMG_PATH" \
    --repo "$GITHUB_REPO" \
    --title "v$VERSION" \
    --notes-file "$RELEASE_NOTES_FILE"

DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$APP_NAME.dmg"

echo "→ Updating appcast.xml on gh-pages"
GH_PAGES_DIR=$(mktemp -d)
git clone --depth 1 --branch gh-pages "https://github.com/$GITHUB_REPO.git" "$GH_PAGES_DIR" || \
    (mkdir -p "$GH_PAGES_DIR" && cd "$GH_PAGES_DIR" && git init && git checkout -b gh-pages)

echo "→ Rendering release-notes HTML"
RELEASE_NOTES_URL="https://mojito.wells.ee/release-notes/$VERSION.html"
FULL_NOTES_URL="https://mojito.wells.ee/release-notes/history.html"
mkdir -p "$GH_PAGES_DIR/release-notes"
python3 "$REPO_ROOT/scripts/md_to_release_notes.py" \
    --title "$APP_NAME $VERSION" \
    < "$CHANGELOG_FRAGMENT" \
    > "$GH_PAGES_DIR/release-notes/$VERSION.html"

# Full version history → Sparkle's "Version history" link. Render every
# `## vX.Y.Z` section (skip the `# Changelog` intro, which is repo-internal).
echo "→ Rendering full version-history HTML"
awk '/^## v[0-9]/ { p = 1 } p' "$REPO_ROOT/CHANGELOG.md" \
    | python3 "$REPO_ROOT/scripts/md_to_release_notes.py" \
        --title "$APP_NAME — Version History" \
    > "$GH_PAGES_DIR/release-notes/history.html"

APPCAST="$GH_PAGES_DIR/appcast.xml"
python3 "$REPO_ROOT/scripts/update_appcast.py" \
    --appcast "$APPCAST" \
    --version "$VERSION" \
    --build "$NEW_BUILD" \
    --url "$DOWNLOAD_URL" \
    --length "$LENGTH" \
    --signature "$EDDSA_SIGNATURE" \
    --release-notes-url "$RELEASE_NOTES_URL" \
    --full-release-notes-url "$FULL_NOTES_URL"

cd "$GH_PAGES_DIR"
git add appcast.xml release-notes
git commit -m "Mojito $VERSION"
git push origin gh-pages

echo "✅ Released $APP_NAME $VERSION"
echo "   DMG:    $DMG_PATH"
echo "   GitHub: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
