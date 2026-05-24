#!/bin/bash
# Regenerate the Xcode project (xcodegen is fast + idempotent) so newly
# added test files are picked up, then run the MojitoTests bundle.
# Invoked by .githooks/pre-push; also runnable by hand.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not installed. brew install xcodegen" >&2
  exit 1
fi

xcodegen generate >/dev/null

xcodebuild test \
  -project Mojito.xcodeproj \
  -scheme Mojito \
  -configuration Debug \
  -destination 'platform=macOS' \
  -quiet
