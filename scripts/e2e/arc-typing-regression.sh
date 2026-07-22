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
#   1. Relaunch the Mojito Dev build with MOJITO_E2E_LOG=1, which mirrors the
#      in-app DebugRecorder activity log into the unified log (subsystem
#      ee.wells.Mojito, category e2e). See Sources/Mojito/Debug/DebugRecorder.swift.
#   2. Capture that log stream while typing terminator-heavy phrases into fresh
#      Arc tabs (Cmd+T), repeated to provoke the busy-new-tab stall.
#   3. Assert ZERO `keyMonitor tapLost reason=timeout` events in the window —
#      that event IS the dropped-keystroke bug. A run that records no e2e events
#      at all is reported inconclusive (app not hooked / TCC not granted), never
#      a false pass.
#
# Requirements (the harness can check but not grant):
#   - Arc installed.
#   - A Mojito Dev build (xcodebuild -scheme Mojito -configuration Debug) with
#     Accessibility + Input Monitoring granted to "Mojito Dev".
#   - The terminal/agent driving this has Accessibility (to synthesize keystrokes
#     via System Events).
#
# Usage:
#   scripts/e2e/arc-typing-regression.sh [--cycles N] [--phrase "text"] [--keep]
#
# Exit codes: 0 pass, 1 fail (timeouts observed), 2 inconclusive/precondition.

set -uo pipefail

# ---- config / args ---------------------------------------------------------
CYCLES=5
PHRASE="how to cook a great meal for dinner today"
KEEP_RUNNING=0
DEV_APP="/Applications/Mojito Dev.app"
DEV_BIN="$DEV_APP/Contents/MacOS/Mojito Dev"
ARC_BUNDLE="company.thebrowser.Browser"
SUBSYSTEM="ee.wells.Mojito"
SETTLE_SECS=3

while [ $# -gt 0 ]; do
  case "$1" in
    --cycles) CYCLES="$2"; shift 2 ;;
    --phrase) PHRASE="$2"; shift 2 ;;
    --app)    DEV_APP="$2"; DEV_BIN="$DEV_APP/Contents/MacOS/Mojito Dev"; shift 2 ;;
    --keep)   KEEP_RUNNING=1; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

LOGFILE="$(mktemp -t mojito-e2e-arc)"
STREAM_PID=""
CGTYPE=""

say()  { printf '\033[1m> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mFAIL: %s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32mOK: %s\033[0m\n' "$*"; }

# `log` is a shell builtin in zsh — shadowing /usr/bin/log yields empty output.
LOG=/usr/bin/log

cleanup() {
  [ -n "$STREAM_PID" ] && kill "$STREAM_PID" 2>/dev/null
  [ -n "$CGTYPE" ] && rm -f "$CGTYPE"
  launchctl unsetenv MOJITO_E2E_LOG 2>/dev/null
  if [ "$KEEP_RUNNING" -eq 0 ]; then
    osascript -e 'tell application "Mojito Dev" to quit' >/dev/null 2>&1
  fi
}
trap cleanup EXIT

# ---- preflight -------------------------------------------------------------
say "Preflight"
if ! open -Ra "Arc" 2>/dev/null && ! mdfind "kMDItemCFBundleIdentifier == '$ARC_BUNDLE'" | grep -q .; then
  fail "Arc not installed (bundle $ARC_BUNDLE)."; exit 2
fi
if [ ! -x "$DEV_BIN" ]; then
  fail "Mojito Dev not built. Run: xcodebuild -project Mojito.xcodeproj -scheme Mojito -configuration Debug -destination 'platform=macOS' build"; exit 2
fi
ok "Arc present; Mojito Dev present"

# ---- (re)launch Mojito Dev with E2E logging --------------------------------
say "Launching Mojito Dev with MOJITO_E2E_LOG=1"
# Quit any running dev instance so we control the env of the one under test.
osascript -e 'tell application "Mojito Dev" to quit' >/dev/null 2>&1
pkill -x "Mojito Dev" 2>/dev/null
sleep 1
# Inject the env via launchd, then launch through LaunchServices (`open`), not
# direct-exec: a directly-exec'd bundle binary doesn't come up as a proper GUI
# app (no NSWorkspace notifications → no activity to observe). TCC grants key off
# the code signature, so the "Mojito Dev" identity's Accessibility / Input
# Monitoring still apply. The launchd var is cleared in cleanup.
launchctl setenv MOJITO_E2E_LOG 1
open "$DEV_APP"
sleep "$SETTLE_SECS"
if ! pgrep -x "Mojito Dev" >/dev/null; then
  fail "Mojito Dev did not stay running after launch."; exit 2
fi
ok "Mojito Dev running (pid $(pgrep -x 'Mojito Dev' | head -1))"

# ---- capture the unified log ----------------------------------------------
say "Capturing e2e log"
"$LOG" stream --style compact \
  --predicate "subsystem == \"$SUBSYSTEM\" && category == \"e2e\"" \
  > "$LOGFILE" 2>/dev/null &
STREAM_PID=$!
sleep 2   # let the stream attach

# ---- build the keystroke helper -------------------------------------------
# HID-level CGEvents, NOT AppleScript keystroke: the latter does not traverse
# Mojito's session event tap, so it can't drive (or stress) the code under test.
CGTYPE="$(mktemp -t cgtype)"
if ! swiftc "$(dirname "$0")/cgtype.swift" -o "$CGTYPE" 2>/dev/null; then
  fail "Could not compile cgtype.swift (need the Xcode/Swift toolchain)."; exit 2
fi

# ---- drive Arc -------------------------------------------------------------
say "Driving Arc: $CYCLES new-tab cycles, typing \"$PHRASE\""
osascript -e 'tell application "Arc" to activate' >/dev/null 2>&1
sleep 1
for i in $(seq 1 "$CYCLES"); do
  osascript -e 'tell application "Arc" to activate' >/dev/null 2>&1
  sleep 0.4
  "$CGTYPE" hotkey command t     # new tab → Arc's command bar (the busy-render window)
  sleep 0.4
  "$CGTYPE" type "$PHRASE"       # words + spaces → the ambient-emoticon detect() path
  sleep 0.5
  "$CGTYPE" key 53               # escape → dismiss the command bar
  printf '  cycle %d/%d\n' "$i" "$CYCLES"
  sleep 0.3
done
sleep 2   # let trailing log lines flush

# ---- analyze ---------------------------------------------------------------
say "Analyzing"
kill "$STREAM_PID" 2>/dev/null; STREAM_PID=""

# grep -c always prints a count (0 when no match); no `|| echo 0` — that would
# append a second "0" and break the numeric tests below.
TOTAL_EVENTS=$(grep -c "e2e" "$LOGFILE" 2>/dev/null)
ARC_SEEN=$(grep -c "company.thebrowser.Browser" "$LOGFILE" 2>/dev/null)
TIMEOUTS=$(grep "keyMonitor tapLost" "$LOGFILE" 2>/dev/null | grep -c "reason=timeout")

echo "  e2e log lines:        $TOTAL_EVENTS"
echo "  Arc-attributed lines: $ARC_SEEN"
echo "  tapLost timeouts:     $TIMEOUTS"
echo "  (full log: $LOGFILE)"

# No events at all → the app wasn't logging/hooked. Don't call that a pass.
if [ "$TOTAL_EVENTS" -eq 0 ] || [ "$ARC_SEEN" -eq 0 ]; then
  fail "Inconclusive — no e2e activity captured for Arc."
  echo "     Likely: Mojito Dev lacks Accessibility/Input Monitoring, or the" >&2
  echo "     driving terminal lacks Accessibility to synthesize keystrokes." >&2
  echo "     Grant in System Settings > Privacy & Security, then rerun." >&2
  exit 2
fi

if [ "$TIMEOUTS" -gt 0 ]; then
  fail "$TIMEOUTS event-tap timeout(s) while typing in Arc — keystrokes were dropped."
  grep "keyMonitor tapLost" "$LOGFILE" | tail -20 >&2
  exit 1
fi

ok "No event-tap timeouts across $CYCLES Arc typing cycles. Typing path is healthy."
exit 0
