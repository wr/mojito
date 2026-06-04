#!/usr/bin/env bash
# Lint HTML, CSS, and JS.
# - htmlhint on index.html
# - stylelint on style.css
# - node --check on picker.js (syntax only; the file is a 4000-line IIFE that mirrors
#   Swift code intentionally, so stylistic ESLint rules would just generate noise)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
gray()  { printf '\033[90m%s\033[0m\n' "$*"; }

need() { command -v "$1" >/dev/null 2>&1 || { red "missing tool: $1"; exit 1; }; }
need node
need npx

fail=0

gray "  htmlhint index.html"
if ! npx --no-install htmlhint index.html; then
  fail=1
fi

gray "  stylelint style.css"
if ! npx --no-install stylelint style.css; then
  fail=1
fi

gray "  node --check picker.js"
if ! node --check picker.js; then
  red "  picker.js has a syntax error"
  fail=1
fi

gray "  node --check i18n.js"
if ! node --check i18n.js; then
  red "  i18n.js has a syntax error"
  fail=1
fi

if [[ $fail -eq 1 ]]; then
  red "lint failed"
  exit 1
fi
green "  lint clean"
exit 0
