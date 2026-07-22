#!/bin/bash
#
# End-to-end regression harness for the Arc typing-stall class of bug (W-555).
#
# Arc suppresses its web accessibility tree, so Mojito reaches for AppleScript /
# AX paths that don't behave like other browsers — and slow work on those paths,
# run inside the CGEventTap callback, makes macOS disable the tap by timeout and
# DROP the keystroke. Unit tests can't exercise the live tap, so this drives real
# Arc + a real Mojito build and asserts the symptom is absent.
#
# How it works:
#   1. Build Mojito Dev from THIS worktree (so a regressed-but-unrebuilt binary
#      can't pass green), and relaunch it with MOJITO_E2E_LOG=1 — which mirrors
#      the in-app DebugRecorder activity log into the unified log (subsystem
#      ee.wells.Mojito, category e2e). See Sources/Mojito/Debug/DebugRecorder.swift.
#   2. PROBE: type a `:` trigger and require an `engine colon` event to appear.
#      That proves synthetic HID keystrokes actually reach Mojito's tap; without
#      it the run is inconclusive (activating Arc alone emits a focus event, so
#      "saw Arc" is NOT proof anything was typed).
#   3. Type terminator-heavy phrases into fresh Arc tabs (Cmd+T), repeated to
#      provoke the busy-new-tab stall.
#   4. Read the e2e log over the recorded time window and assert ZERO
#      `keyMonitor tapLost reason=timeout` events. That event IS the bug.
#
# Requirements (checked, but can't be granted by the script):
#   - Arc installed.
#   - The dev toolchain (xcodebuild/swiftc) + a working Debug build (the
#     gitignored Giphy key etc. in place, per CLAUDE.md).
#   - Accessibility + Input Monitoring granted to "Mojito Dev".
#   - Accessibility for the driving terminal (to post HID CGEvents).
#
# Usage:
#   scripts/e2e/arc-typing-regression.sh [--cycles N] [--phrase "text"]
#                                        [--no-build] [--app PATH] [--keep]
#
# Exit codes: 0 pass, 1 fail (timeouts observed), 2 inconclusive/precondition.

set -uo pipefail

# ---- config / args ---------------------------------------------------------
CYCLES=5
PHRASE="how to cook a great meal for dinner today"
PROBE=":tada "                       # colon trigger → must produce `engine colon`
KEEP_RUNNING=0
DO_BUILD=1
DEV_APP=""                           # resolved from the build unless --app given
ARC_BUNDLE="company.thebrowser.Browser"
SUBSYSTEM="ee.wells.Mojito"
SETTLE_SECS=3
LOG=/usr/bin/log                     # `log` is a zsh builtin that shadows this
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PRED="subsystem == \"$SUBSYSTEM\" && category == \"e2e\""

while [ $# -gt 0 ]; do
  case "$1" in
    --cycles)   CYCLES="$2"; shift 2 ;;
    --phrase)   PHRASE="$2"; shift 2 ;;
    --app)      DEV_APP="$2"; DO_BUILD=0; shift 2 ;;
    --no-build) DO_BUILD=0; shift ;;
    --keep)     KEEP_RUNNING=1; shift ;;
    -h|--help)  sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$CYCLES" in ''|*[!0-9]*) echo "--cycles must be a positive integer" >&2; exit 2 ;; esac
[ "$CYCLES" -ge 1 ] || { echo "--cycles must be >= 1" >&2; exit 2; }

CGTYPE=""
PRIOR_ENV=""; HAD_PRIOR_ENV=0

say()  { printf '\033[1m> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mFAIL: %s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32mOK: %s\033[0m\n' "$*"; }

cleanup() {
  [ -n "$CGTYPE" ] && rm -f "$CGTYPE"
  # Restore the session env var to exactly what it was (or clear it).
  if [ "$HAD_PRIOR_ENV" -eq 1 ]; then
    launchctl setenv MOJITO_E2E_LOG "$PRIOR_ENV" 2>/dev/null
  else
    launchctl unsetenv MOJITO_E2E_LOG 2>/dev/null
  fi
  if [ "$KEEP_RUNNING" -eq 0 ]; then
    osascript -e 'tell application "Mojito Dev" to quit' >/dev/null 2>&1
  fi
}
trap cleanup EXIT

# Post a batch of HID keystrokes and FAIL HARD if the helper errors — a silent
# no-op here is exactly how the harness would end up testing nothing.
drive() { "$CGTYPE" "$@" || { fail "cgtype failed: $*"; exit 2; }; }

# ---- preflight -------------------------------------------------------------
say "Preflight"
if ! open -Ra "Arc" 2>/dev/null && ! mdfind "kMDItemCFBundleIdentifier == '$ARC_BUNDLE'" | grep -q .; then
  fail "Arc not installed (bundle $ARC_BUNDLE)."; exit 2
fi

# ---- build from this worktree (unless told not to) -------------------------
if [ "$DO_BUILD" -eq 1 ]; then
  say "Building Mojito Dev (Debug) from $REPO_ROOT"
  BUILD_LOG="$(mktemp)"
  if ! xcodebuild -project "$REPO_ROOT/Mojito.xcodeproj" -scheme Mojito \
       -configuration Debug -destination 'platform=macOS' build >"$BUILD_LOG" 2>&1; then
    fail "Build failed. Tail:"; tail -20 "$BUILD_LOG" >&2; exit 2
  fi
  BPD="$(xcodebuild -project "$REPO_ROOT/Mojito.xcodeproj" -scheme Mojito \
         -configuration Debug -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
         | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
  rm -f "$BUILD_LOG"
  DEV_APP="$BPD/Mojito Dev.app"
  ok "Built: $DEV_APP"
fi
[ -z "$DEV_APP" ] && DEV_APP="/Applications/Mojito Dev.app"
if [ ! -x "$DEV_APP/Contents/MacOS/Mojito Dev" ]; then
  fail "No runnable Mojito Dev at: $DEV_APP"; exit 2
fi

# ---- compile the HID keystroke helper --------------------------------------
# HID-level CGEvents, NOT AppleScript keystroke: the latter does not traverse
# Mojito's session event tap, so it can't drive the code under test.
CGTYPE="$(mktemp -t cgtype)"
if ! swiftc "$(dirname "$0")/cgtype.swift" -o "$CGTYPE" 2>/dev/null; then
  fail "Could not compile cgtype.swift (need the Xcode/Swift toolchain)."; exit 2
fi

# ---- relaunch Mojito Dev with E2E logging ----------------------------------
say "Relaunching Mojito Dev with MOJITO_E2E_LOG=1"
if PRIOR_ENV="$(launchctl getenv MOJITO_E2E_LOG 2>/dev/null)" && [ -n "$PRIOR_ENV" ]; then
  HAD_PRIOR_ENV=1
fi
osascript -e 'tell application "Mojito Dev" to quit' >/dev/null 2>&1
pkill -x "Mojito Dev" 2>/dev/null
sleep 1
# Inject the env via launchd, then launch through LaunchServices (`open`): a
# directly-exec'd bundle binary doesn't come up as a proper GUI app (no
# NSWorkspace notifications). TCC grants key off the code signature, so the
# "Mojito Dev" identity's Accessibility / Input Monitoring still apply.
launchctl setenv MOJITO_E2E_LOG 1
open "$DEV_APP"
sleep "$SETTLE_SECS"
pgrep -x "Mojito Dev" >/dev/null || { fail "Mojito Dev did not stay running."; exit 2; }
ok "Mojito Dev running (pid $(pgrep -x 'Mojito Dev' | head -1))"

# Everything from here is timestamped; read the log back over this window
# (log show, not a streamed pipe — no attach race, no truncated tail).
T0="$(date -v-2S '+%Y-%m-%d %H:%M:%S')"
capture() { "$LOG" show --start "$T0" --style compact --predicate "$PRED" 2>/dev/null; }

# ---- PROBE: prove synthetic keystrokes reach Mojito's tap ------------------
say "Probe: verifying HID keystrokes reach Mojito's engine"
osascript -e 'tell application "Arc" to activate' >/dev/null 2>&1
sleep 1
drive hotkey command t
sleep 0.4
drive type "$PROBE"
sleep 0.3
drive key 53
sleep 1.5
if [ "$(capture | grep -c 'engine colon')" -lt 1 ]; then
  fail "Inconclusive — the probe ':' never reached Mojito (no 'engine colon')."
  echo "     Synthetic keystrokes aren't hitting the tap. Likely: Mojito Dev" >&2
  echo "     lacks Accessibility/Input Monitoring, or the driving terminal" >&2
  echo "     lacks Accessibility to post HID events. Grant in System Settings." >&2
  exit 2
fi
ok "Probe reached the engine — keystrokes are live"

# ---- drive Arc -------------------------------------------------------------
say "Driving Arc: $CYCLES new-tab cycles, typing \"$PHRASE\""
for i in $(seq 1 "$CYCLES"); do
  osascript -e 'tell application "Arc" to activate' >/dev/null 2>&1
  sleep 0.4
  drive hotkey command t     # new tab → Arc's command bar (the busy-render window)
  sleep 0.4
  drive type "$PHRASE"       # words + spaces → the ambient-emoticon detect() path
  sleep 0.5
  drive key 53               # escape → dismiss the command bar
  printf '  cycle %d/%d\n' "$i" "$CYCLES"
  sleep 0.3
done
sleep 2   # let trailing log lines persist

# ---- analyze ---------------------------------------------------------------
say "Analyzing"
CAP="$(capture)"
TOTAL_EVENTS=$(printf '%s\n' "$CAP" | grep -c "e2e")
TIMEOUTS=$(printf '%s\n' "$CAP" | grep "keyMonitor tapLost" | grep -c "reason=timeout")

echo "  e2e log lines:    $TOTAL_EVENTS"
echo "  tapLost timeouts: $TIMEOUTS"

if [ "$TIMEOUTS" -gt 0 ]; then
  fail "$TIMEOUTS event-tap timeout(s) while typing in Arc — keystrokes were dropped."
  printf '%s\n' "$CAP" | grep "keyMonitor tapLost" | tail -20 >&2
  exit 1
fi

ok "No event-tap timeouts across $CYCLES Arc typing cycles (probe confirmed live). Healthy."
exit 0
