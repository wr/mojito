# E2E harness — live Arc typing regression

Unit tests can't touch the `CGEventTap`. This harness drives a real Mojito build
against a real app and asserts the tap stays healthy — built for the class of
bugs Arc keeps producing, where slow work on Mojito's event-tap path makes macOS
disable the tap by timeout and **drop keystrokes** (W-555).

## What's here

- `arc-typing-regression.sh` — the harness. Relaunches the Mojito Dev build with
  E2E logging on, types terminator-heavy phrases into fresh Arc tabs, and asserts
  **zero `keyMonitor tapLost reason=timeout`** events.
- `cgtype.swift` — synthetic keystroke helper (compiled on the fly by the harness).

## The signal

With `MOJITO_E2E_LOG=1`, `DebugRecorder` mirrors its activity log into the unified
log (subsystem `ee.wells.Mojito`, category `e2e`) — see
`Sources/Mojito/Debug/DebugRecorder.swift`. The harness reads that log over the
run's time window (`log show`, not a streamed pipe — no attach race) and counts
tap timeouts. That event *is* the dropped-keystroke bug; the flag is a no-op (the
logger isn't even constructed) without the env var, so production is untouched.

## Guardrails against a false green

A test harness that passes while testing nothing is worse than none, so:

- **Builds from this worktree by default** (`--no-build` / `--app` to override).
  A regressed-but-unrebuilt binary can't sneak a stale green through.
- **Probes first.** Before the stress cycles it types a `:` trigger and requires
  an `engine colon` event to appear — positive proof that synthetic HID
  keystrokes actually reach Mojito's tap. No probe hit → **inconclusive** (exit 2),
  never a pass. (Merely activating Arc emits a focus event, so "saw Arc" is not
  proof anything was typed.)
- **Fails hard on driver errors** — `cgtype` exits non-zero if it can't post an
  event, and every drive step is checked; a bad `--cycles` is rejected up front.

## Requirements (the harness checks, but can't grant)

- **Arc installed.**
- **The dev toolchain + a working Debug build** — `xcodebuild`/`swiftc`, and the
  gitignored bits (Giphy key, per CLAUDE.md) in place so the build succeeds.
- **Accessibility + Input Monitoring granted to `Mojito Dev.app`.** Grants persist
  across rebuilds because the "Mojito Dev" signing identity is stable.
- **Accessibility for the driving terminal** — `cgtype` posts HID CGEvents, which
  needs the invoking process permitted.

## Run

```bash
scripts/e2e/arc-typing-regression.sh                 # build, 5 cycles, default phrase
scripts/e2e/arc-typing-regression.sh --cycles 10
scripts/e2e/arc-typing-regression.sh --no-build      # reuse the last build
scripts/e2e/arc-typing-regression.sh --app "/Applications/Mojito Dev.app"
```

Exit: `0` healthy, `1` timeouts observed (bug), `2` inconclusive/precondition
(Arc missing, build failed, or the probe never reached the tap — all reported,
never a false pass).

## Gotchas baked in (learned the hard way)

- **HID CGEvents, not AppleScript `keystroke`.** System Events keystrokes do NOT
  traverse Mojito's `.cgSessionEventTap` — they never reach the engine, so they
  can't reproduce (or stress) a tap-path bug. `cgtype` posts at `.cghidEventTap`.
  Verified: HID-posted `:tada` fires `engine colon` / `picker open`; System
  Events `:tada` fires nothing.
- **`/usr/bin/log`, not `log`.** `log` is a zsh builtin that shadows the binary
  and silently prints nothing.
- **Launch via `launchctl setenv` + `open`, not direct-exec.** A directly-exec'd
  bundle binary doesn't come up as a proper GUI app, so there are no NSWorkspace
  notifications to observe. LaunchServices launch inherits the launchd env, and
  TCC grants key off the code signature, so they still apply.

## Extending

Add scenarios by parameterizing the target/phrase, or add new `cgtype` verbs
(it does `type`, `hotkey <mod> <letter>`, `key <keycode>`). The same os_log
stream exposes `engine`, `picker`, `insert`, `focus`, and `permissions` events —
so other Arc regressions (picker mispositioning, exclusions) can assert on those
too.
