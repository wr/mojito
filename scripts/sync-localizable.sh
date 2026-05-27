#!/usr/bin/env bash
# Refresh Resources/Localizable.xcstrings from the per-file .stringsdata
# emitted by the Swift compiler (SWIFT_EMIT_LOC_STRINGS = YES). Run after
# `xcodebuild build` whenever you add or change a SwiftUI Text("…") /
# String(localized: "…") so the catalog reflects current source.
#
# Xcode's IDE syncs automatically on build; this is the headless path.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

DERIV_BASE=$(xcodebuild -project Mojito.xcodeproj -scheme Mojito \
    -configuration Debug -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]+OBJECT_FILE_DIR_normal[[:space:]]/ {print $2; exit}')

ARCH=$(uname -m)
DERIV="$DERIV_BASE/$ARCH"

if [[ ! -d "$DERIV" ]]; then
    echo "Build artifacts not found at $DERIV"
    echo "Run a Debug build first: xcodebuild -project Mojito.xcodeproj -scheme Mojito -configuration Debug -destination 'platform=macOS' build"
    exit 1
fi

find "$DERIV" -name '*.stringsdata' \
    -not -name 'ExtractedAppShortcutsMetadata.stringsdata' \
    -print0 \
  | xargs -0 xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata

echo "Synced strings into Resources/Localizable.xcstrings."
