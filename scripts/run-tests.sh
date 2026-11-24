#!/bin/bash
# Regenerate the Xcode project (xcodegen is fast + idempotent) so newly
# added test files are picked up, then run the MojitoTests bundle.
# Invoked by .githooks/pre-push and CI; also runnable by hand. Extra
# arguments (build-setting overrides, -derivedDataPath, …) go to xcodebuild.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not installed. brew install xcodegen" >&2
  exit 1
fi

xcodegen generate >/dev/null

# MOJITO_INSTALL_DEV_APP=NO skips the Debug build's install to /Applications,
# so a test run (or a push) doesn't replace or restart the Mojito Dev you're using.
xcodebuild test \
  -project Mojito.xcodeproj \
  -scheme Mojito \
  -configuration Debug \
  -destination 'platform=macOS' \
  -quiet \
  MOJITO_INSTALL_DEV_APP=NO \
  "$@"
