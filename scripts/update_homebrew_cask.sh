#!/usr/bin/env bash
#
# Point the Homebrew cask at a published release.
#
# Usage:  scripts/update_homebrew_cask.sh <version>
# Env vars expected:
#   GITHUB_REPO        — e.g. wr/mojito
# Optional:
#   HOMEBREW_TAP_REPO  — defaults to <owner of GITHUB_REPO>/homebrew-tap
#
# Rewrites `version` and `sha256` in Casks/mojito.rb and pushes the change to
# the tap's default branch. The sha256 comes from GitHub's digest of the
# uploaded release asset — the exact bytes `brew` will download — rather than
# a local DMG that may have been rebuilt since.
#
# release.sh runs this after publishing. Run it by hand to re-sync the tap if
# that step failed.
#
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: $0 <version>  (e.g. 0.2.0)" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$REPO_ROOT/.env"
    set +a
fi

if [[ -z "${GITHUB_REPO:-}" ]]; then
    echo "error: GITHUB_REPO is not set" >&2
    exit 1
fi
TAP_REPO="${HOMEBREW_TAP_REPO:-${GITHUB_REPO%%/*}/homebrew-tap}"
CASK_FILE="Casks/mojito.rb"
ASSET_NAME="Mojito.dmg"

DIGEST=$(gh release view "v$VERSION" --repo "$GITHUB_REPO" --json assets \
    --jq ".assets[] | select(.name == \"$ASSET_NAME\") | .digest")
SHA256="${DIGEST#sha256:}"
if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: no sha256 digest for $ASSET_NAME on $GITHUB_REPO v$VERSION (got '$DIGEST')." >&2
    exit 1
fi

TAP_DIR=$(mktemp -d)
trap 'rm -rf "$TAP_DIR"' EXIT
git clone --quiet --depth 1 "https://github.com/$TAP_REPO.git" "$TAP_DIR"

CASK="$TAP_DIR/$CASK_FILE"
sed -i '' -E \
    -e "s/^  version \"[^\"]*\"$/  version \"$VERSION\"/" \
    -e "s/^  sha256 \"[0-9a-f]*\"$/  sha256 \"$SHA256\"/" \
    "$CASK"
# sed exits 0 even when nothing matched, so confirm both lines actually landed
# before committing a cask that points at the wrong DMG.
if ! grep -qx "  version \"$VERSION\"" "$CASK" || ! grep -qx "  sha256 \"$SHA256\"" "$CASK"; then
    echo "error: couldn't rewrite version/sha256 in $TAP_REPO/$CASK_FILE." >&2
    exit 1
fi

cd "$TAP_DIR"
if git diff --quiet; then
    echo "   $TAP_REPO already at $VERSION"
    exit 0
fi
git add "$CASK_FILE"
git commit -q -m "mojito $VERSION"
git push --quiet origin HEAD
echo "   $TAP_REPO → $VERSION ($SHA256)"
