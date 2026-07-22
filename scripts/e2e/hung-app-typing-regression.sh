#!/bin/bash
#
# Deterministic E2E regression test for the "hung frontmost app drops
# keystrokes" class (W-547 Safari lag, W-555 Arc, generalized in W-557).
#
# Mojito's key monitor is a CGEventTap whose callback runs on the MAIN thread.
# On a trigger keystroke it builds an app context, which historically made
# synchronous cross-process IPC to the frontmost app — an AppleScript URL read
# (Arc) and AX attribute queries (every app). When that app is slow or hung,
# the IPC blocks the tap callback; past the ~1s system tap timeout macOS
# disables the tap and DROPS the keystroke. Unit tests can't exercise the live
# tap, so this drives a real Mojito build against a real, deliberately-frozen
# app and asserts the symptom is absent.
#
# The trick that makes it deterministic (unlike wall-clock "type fast and hope"):
# SIGSTOP the target app so it CANNOT answer any IPC, type into it, then SIGCONT.
# A build that does blocking IPC on the tap thread drops keystrokes every time
# (RED); a build that keeps the tap non-blocking never does (GREEN). It reliably
# separates fixed from unfixed — the whole point.
#
# Targets both a browser (Arc — the AppleScript + AX paths) and a non-browser
# control (TextEdit — the AX path alone), so a regression in either path is
# caught and attributable.
#
# Requirements (checked, can't be granted here):
#   - Arc installed; the dev toolchain + a working Debug build (gitignored Giphy
#     key etc. per CLAUDE.md); Accessibility + Input Monitoring for "Mojito Dev";
#     Accessibility for the driving terminal (to post HID CGEvents). The first
#     Arc URL read also needs a one-time Automation grant — the warmup below
#     establishes it before the timed test so it can't skew a result.
#
# Usage:
#   scripts/e2e/hung-app-typing-regression.sh [--cycles N] [--freeze SECS]
#                                             [--no-build] [--app PATH] [--keep]
#
# Exit: 0 pass, 1 fail (keystrokes dropped), 2 inconclusive/precondition.

set -uo pipefail

CYCLES=3
FREEZE_SECS=2
DO_BUILD=1
DEV_APP=""
KEEP_RUNNING=0
ARC_BUNDLE="company.thebrowser.Browser"
SUBSYSTEM="ee.wells.Mojito"
PRED="subsystem == \"$SUBSYSTEM\" && category == \"e2e\""
LOG=/usr/bin/log                     # `log` is a zsh builtin that shadows this
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PHRASE="how to cook a great meal for dinner"

while [ $# -gt 0 ]; do
  case "$1" in
    --cycles)   CYCLES="$2"; shift 2 ;;
    --freeze)   FREEZE_SECS="$2"; shift 2 ;;
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
TE_LAUNCHED=0                              # 1 only if WE started TextEdit
say()  { printf '\033[1m> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mFAIL: %s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32mOK: %s\033[0m\n' "$*"; }

thaw_all() {
  for p in $(pgrep -x Arc) $(pgrep -x TextEdit); do kill -CONT "$p" 2>/dev/null; done
}
cleanup() {
  thaw_all                                  # never leave a target frozen
  [ -n "$CGTYPE" ] && rm -f "$CGTYPE"
  # Only quit TextEdit if this run launched it — never discard a user's docs.
  [ "$TE_LAUNCHED" -eq 1 ] && osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
  if [ "$HAD_PRIOR_ENV" -eq 1 ]; then
    launchctl setenv MOJITO_E2E_LOG "$PRIOR_ENV" 2>/dev/null
  else
    launchctl unsetenv MOJITO_E2E_LOG 2>/dev/null
  fi
  [ "$KEEP_RUNNING" -eq 0 ] && osascript -e 'tell application "Mojito Dev" to quit' >/dev/null 2>&1
}
trap cleanup EXIT

drive() { "$CGTYPE" "$@" || { fail "cgtype failed: $*"; exit 2; }; }

# Name of the frontmost app process, for verifying activation actually took.
frontmost_name() {
  osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null
}

# ---- preflight -------------------------------------------------------------
say "Preflight"
if ! open -Ra "Arc" 2>/dev/null && ! mdfind "kMDItemCFBundleIdentifier == '$ARC_BUNDLE'" | grep -q .; then
  fail "Arc not installed (bundle $ARC_BUNDLE)."; exit 2
fi

# ---- build -----------------------------------------------------------------
if [ "$DO_BUILD" -eq 1 ]; then
  say "Building Mojito Dev (Debug) from $REPO_ROOT"
  BUILD_LOG="$(mktemp)"
  if ! xcodebuild -project "$REPO_ROOT/Mojito.xcodeproj" -scheme Mojito \
       -configuration Debug -destination 'platform=macOS' build >"$BUILD_LOG" 2>&1; then
    fail "Build failed. Tail:"; tail -20 "$BUILD_LOG" >&2; exit 2
  fi
  DEV_APP="$(xcodebuild -project "$REPO_ROOT/Mojito.xcodeproj" -scheme Mojito \
         -configuration Debug -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
         | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/Mojito Dev.app"
  rm -f "$BUILD_LOG"
  ok "Built: $DEV_APP"
fi
[ -z "$DEV_APP" ] && DEV_APP="/Applications/Mojito Dev.app"
[ -x "$DEV_APP/Contents/MacOS/Mojito Dev" ] || { fail "No runnable Mojito Dev at: $DEV_APP"; exit 2; }

# ---- compile the HID keystroke helper --------------------------------------
CGTYPE="$(mktemp -t cgtype)"
swiftc "$(dirname "$0")/cgtype.swift" -o "$CGTYPE" 2>/dev/null \
  || { fail "Could not compile cgtype.swift (need the Xcode/Swift toolchain)."; exit 2; }

# ---- relaunch Mojito Dev with E2E logging ----------------------------------
say "Relaunching Mojito Dev with MOJITO_E2E_LOG=1"
if PRIOR_ENV="$(launchctl getenv MOJITO_E2E_LOG 2>/dev/null)" && [ -n "$PRIOR_ENV" ]; then
  HAD_PRIOR_ENV=1
fi
osascript -e 'tell application "Mojito Dev" to quit' >/dev/null 2>&1
pkill -x "Mojito Dev" 2>/dev/null; sleep 1
launchctl setenv MOJITO_E2E_LOG 1
open "$DEV_APP"; sleep 3
pgrep -x "Mojito Dev" >/dev/null || { fail "Mojito Dev did not stay running."; exit 2; }
ok "Mojito Dev running (pid $(pgrep -x 'Mojito Dev' | head -1))"

capture_since() { "$LOG" show --start "$1" --style compact --predicate "$PRED" 2>/dev/null; }

# ---- warmup + probe --------------------------------------------------------
# Type a `:` trigger in Arc while it's responsive. Two jobs: (1) prove synthetic
# HID keystrokes reach Mojito's engine (`engine colon`) — else the run is
# inconclusive, not a pass; (2) trigger the first Arc URL read now so its
# one-time Automation grant is settled before the timed freeze test (an
# unresolved TCC prompt mid-test would stall it).
say "Warmup + probe (Arc responsive)"
osascript -e 'tell application "Arc" to activate' >/dev/null 2>&1; sleep 1
osascript -e 'tell application "Arc" to tell front window to tell tab 1 to select' >/dev/null 2>&1
WARM_T0="$(date -v-2S '+%Y-%m-%d %H:%M:%S')"
drive hotkey command t; sleep 0.4; drive type ":tada "; sleep 0.5; drive key 53; sleep 1.5
if [ "$(capture_since "$WARM_T0" | grep -c 'engine colon')" -lt 1 ]; then
  fail "Inconclusive — the probe ':' never reached Mojito (no 'engine colon')."
  echo "     HID keystrokes aren't hitting the tap. Grant Accessibility/Input" >&2
  echo "     Monitoring to Mojito Dev, and Accessibility to this terminal." >&2
  exit 2
fi
ok "Probe reached the engine — keystrokes are live"

# ---- freeze one target for one cycle, return tapLost count for the window --
# Args: $1 = pgrep pattern, $2 = activate osascript, $3 = focus keystroke driver
# Runs in the main shell (not a subshell) so a `drive` failure's `exit` actually
# halts the script; publishes the tapLost count via the global TAP_TIMEOUTS.
TAP_TIMEOUTS=0
run_target() {
  local name="$1" activate="$2"
  say "Target: $name — $CYCLES freeze cycles (${FREEZE_SECS}s each)"
  local t0; t0="$(date -v-2S '+%Y-%m-%d %H:%M:%S')"
  local i
  for i in $(seq 1 "$CYCLES"); do
    osascript -e "$activate" >/dev/null 2>&1; sleep 0.4
    # Verify the target is actually frontmost BEFORE freezing — otherwise the
    # phrase would go to some other app and a clean log would be a false pass.
    local fm; fm="$(frontmost_name)"
    if [ "$fm" != "$name" ]; then
      fail "$name is not frontmost (got '${fm:-none}') — activation failed; inconclusive."
      exit 2
    fi
    drive hotkey command l                       # focus a text field (URL bar / doc)
    sleep 0.2
    local tpid; tpid="$(pgrep -x "$name" | head -1)"
    [ -n "$tpid" ] || { fail "$name is not running — can't freeze it; inconclusive."; exit 2; }
    for p in $(pgrep -x "$name"); do kill -STOP "$p"; done   # freeze: no IPC answers
    # PROVE it actually froze — a failed STOP would leave the target responsive
    # and a clean log would be a false pass. `T` = stopped.
    local st; st="$(ps -o state= -p "$tpid" 2>/dev/null | tr -d ' ')"
    case "$st" in
      T*) ;;
      *)  for p in $(pgrep -x "$name"); do kill -CONT "$p" 2>/dev/null; done
          fail "$name did not freeze (state '${st:-gone}') — inconclusive."; exit 2 ;;
    esac
    drive type "$PHRASE "                          # each word+space fires detect()
    sleep "$FREEZE_SECS"                           # hold: a blocking tap path times out here
    for p in $(pgrep -x "$name"); do kill -CONT "$p"; done   # thaw
    drive key 53
    printf '  %s cycle %d/%d\n' "$name" "$i" "$CYCLES"
    sleep 0.6
  done
  sleep 1.5
  TAP_TIMEOUTS="$(capture_since "$t0" | grep 'keyMonitor tapLost' | grep -c 'reason=timeout')"
}

FAILED=0

# Arc — exercises the AppleScript URL path + the AX field/URL queries.
run_target Arc 'tell application "Arc" to activate'
if [ "$TAP_TIMEOUTS" -gt 0 ]; then fail "Arc: $TAP_TIMEOUTS dropped-keystroke timeout(s)."; FAILED=1
else ok "Arc: no tap timeouts across $CYCLES frozen-typing cycles."; fi

# TextEdit — non-browser control; isolates the AX-query path (no URL read).
# Only run it if TextEdit isn't already open — freezing/quitting a TextEdit that
# holds the user's unsaved documents would risk their work.
if pgrep -x TextEdit >/dev/null; then
  say "TextEdit already running — skipping the non-browser control (won't touch your open documents)."
else
  TE_LAUNCHED=1
  open -a TextEdit; sleep 1
  osascript -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1; sleep 0.5
  run_target TextEdit 'tell application "TextEdit" to activate'
  if [ "$TAP_TIMEOUTS" -gt 0 ]; then fail "TextEdit: $TAP_TIMEOUTS dropped-keystroke timeout(s)."; FAILED=1
  else ok "TextEdit: no tap timeouts across $CYCLES frozen-typing cycles."; fi
fi

# ---- verdict ---------------------------------------------------------------
if [ "$FAILED" -eq 0 ]; then
  ok "PASS — a frozen frontmost app did not drop keystrokes (probe confirmed live)."
  exit 0
fi
fail "Keystrokes dropped while a frontmost app was hung — the tap path is blocking on cross-process IPC."
exit 1
