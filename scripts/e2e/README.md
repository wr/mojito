# E2E harness — hung-app typing regression

Unit tests can't touch the `CGEventTap`. This harness drives a real Mojito build
against a real, deliberately-frozen app and asserts the tap stays healthy —
built for the recurring class of bug where slow/blocking work on Mojito's
event-tap path makes macOS disable the tap by timeout and **drop keystrokes**
(W-547 Safari lag, W-555 Arc, generalized in W-557).

## What's here

- `hung-app-typing-regression.sh` — the harness. Relaunches the Mojito Dev build
  with E2E logging, then for each target app **`SIGSTOP`s it, types into it, and
  `SIGCONT`s**, asserting **zero `keyMonitor tapLost reason=timeout`** events.
- `cgtype.swift` — synthetic keystroke helper (compiled on the fly by the harness).

## Why freeze the app

The tap callback runs on the main thread; building the app context on a trigger
keystroke used to make synchronous cross-process IPC to the frontmost app (an
AppleScript URL read for Arc; AX attribute queries for every app). If that app
is slow to answer, the IPC blocks the tap callback past the ~1s system timeout
and macOS drops the keystroke.

Reproducing that with "type fast and hope the app is busy" is flaky and
hardware-dependent — on a fast, idle machine the app answers in milliseconds and
nothing drops, so the test passes whether or not the bug is present. **Freezing
the app with `SIGSTOP` makes it deterministic:** a frozen app *cannot* answer any
IPC, so a build that blocks on it drops keystrokes **every time** (RED), and a
build that keeps the tap non-blocking never does (GREEN). Clean discrimination,
no timing luck.

## Targets

- **Arc** — exercises the AppleScript URL path *and* the AX field/URL queries.
- **TextEdit** — a non-browser control that isolates the AX-query path (no URL
  read), so a regression there is caught and attributable even without a browser.

## The signal

With `MOJITO_E2E_LOG=1`, `DebugRecorder` mirrors its activity log into the unified
log (subsystem `ee.wells.Mojito`, category `e2e`). The harness reads it back over
each cycle's window (`log show`, not a streamed pipe — no attach race) and counts
`keyMonitor tapLost reason=timeout`. That event *is* the dropped-keystroke bug.
The flag is a no-op (the logger isn't even constructed) without the env var, so
production is untouched.

## Guardrails against a false green

- **Builds from this worktree by default** (`--no-build` / `--app` to override) —
  a regressed-but-unrebuilt binary can't sneak a stale green through.
- **Warmup + probe.** Before the freeze cycles it types a `:` trigger into a
  responsive Arc and requires an `engine colon` event — positive proof that
  synthetic HID keystrokes actually reach the tap (no hit → **inconclusive**,
  exit 2, never a pass). The same step settles Arc's one-time Automation grant so
  an unresolved TCC prompt can't stall the timed run.
- **Fails hard on driver errors** — `cgtype` exits non-zero if it can't post an
  event; a bad `--cycles` is rejected up front.
- **Never leaves an app frozen** — an `EXIT` trap `SIGCONT`s every target.

## Run

```bash
scripts/e2e/hung-app-typing-regression.sh                 # build, 3 cycles/target
scripts/e2e/hung-app-typing-regression.sh --cycles 6
scripts/e2e/hung-app-typing-regression.sh --freeze 3      # longer freeze window
scripts/e2e/hung-app-typing-regression.sh --no-build      # reuse the last build
scripts/e2e/hung-app-typing-regression.sh --app "/Applications/Mojito Dev.app"
```

Exit: `0` healthy, `1` keystrokes dropped (bug), `2` inconclusive/precondition
(Arc missing, build failed, or the probe never reached the tap — all reported,
never a false pass).

## Requirements (checked, but can't be granted here)

- **Arc installed.**
- **The dev toolchain + a working Debug build** — `xcodebuild`/`swiftc`, and the
  gitignored bits (Giphy key, per CLAUDE.md) in place so the build succeeds.
- **Accessibility + Input Monitoring granted to `Mojito Dev.app`.** Grants persist
  across rebuilds because the "Mojito Dev" signing identity is stable.
- **Accessibility for the driving terminal** — `cgtype` posts HID CGEvents, which
  needs the invoking process permitted.

## Gotchas baked in (learned the hard way)

- **HID CGEvents, not AppleScript `keystroke`.** System Events keystrokes do NOT
  traverse Mojito's `.cgSessionEventTap` — they never reach the engine. `cgtype`
  posts at `.cghidEventTap`. Verified: HID-posted `:tada` fires `engine colon`;
  System Events `:tada` fires nothing.
- **`/usr/bin/log`, not `log`.** `log` is a zsh builtin that shadows the binary
  and silently prints nothing.
- **Launch via `launchctl setenv` + `open`, not direct-exec.** A directly-exec'd
  bundle binary doesn't come up as a proper GUI app (no NSWorkspace
  notifications). LaunchServices launch inherits the launchd env, and TCC grants
  key off the code signature, so they still apply.
- **Freeze the app *after* focusing a field, thaw *before* the next cycle.** A
  frozen app can't deliver AX focus-change notifications, so set focus while it's
  responsive.

## Extending

Add a target by giving `run_target` its `pgrep` name + an activate command. The
same os_log stream exposes `engine`, `picker`, `insert`, `focus`, and
`permissions` events, so other regressions (picker mispositioning, exclusions)
can assert on those too.
