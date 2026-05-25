#!/usr/bin/env bash
# Walk all internal + external links in index.html via lychee.
# Spins up a local python http server so root-relative links ("/", "/foo") resolve
# the same way they will once deployed.
# Pass --no-external to skip network-bound external checks (offline mode).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

PORT=8766

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
gray()  { printf '\033[90m%s\033[0m\n' "$*"; }

command -v lychee  >/dev/null 2>&1 || { red "missing tool: lychee (brew install lychee)"; exit 1; }
command -v python3 >/dev/null 2>&1 || { red "missing tool: python3"; exit 1; }

MODE_ARGS=()
# Internal-only: only check links pointing back at our local server.
[[ "${1:-}" == "--no-external" ]] && MODE_ARGS=(--include "localhost:$PORT")

SERVER_PID=
cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

gray "  starting http://localhost:$PORT"
python3 -m http.server "$PORT" >/dev/null 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 30); do
  if curl -sf "http://localhost:$PORT/" >/dev/null; then break; fi
  sleep 0.1
done

gray "  lychee http://localhost:$PORT/"
if ! lychee \
    --no-progress \
    --cache --max-cache-age 1d \
    ${MODE_ARGS[@]+"${MODE_ARGS[@]}"} \
    "http://localhost:$PORT/"; then
  red "link check failed"
  exit 1
fi

green "  links OK"
exit 0
