#!/usr/bin/env bash
# Install the pre-push hook by symlinking it into .git/hooks/.
# Safe to re-run.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HOOK_SRC="$ROOT/scripts/hooks/pre-push"
HOOK_DST="$ROOT/.git/hooks/pre-push"

if [[ ! -d "$ROOT/.git" && ! -f "$ROOT/.git" ]]; then
  printf 'no .git found in %s\n' "$ROOT" >&2
  exit 1
fi

# .git may be a file (worktree) — resolve to the actual hooks dir
HOOKS_DIR="$(git rev-parse --git-path hooks)"
HOOK_DST="$HOOKS_DIR/pre-push"

mkdir -p "$HOOKS_DIR"

if [[ -e "$HOOK_DST" && ! -L "$HOOK_DST" ]]; then
  printf '%s already exists and is not a symlink — backing up to %s.bak\n' "$HOOK_DST" "$HOOK_DST"
  mv "$HOOK_DST" "$HOOK_DST.bak"
fi

ln -snf "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_SRC"

printf '✓ installed: %s → %s\n' "$HOOK_DST" "$HOOK_SRC"
