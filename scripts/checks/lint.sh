#!/usr/bin/env bash
# Lint HTML, CSS, and JS.
# - htmlhint on index.html, stats.html and every guide page (*/index.html)
# - stylelint on style.css, stats.css and guides.css
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

# Guide pages live at <slug>/index.html (clean directory URLs).
GUIDE_PAGES=$(git ls-files '*/index.html' | grep -v '^node_modules/' || true)

gray "  htmlhint index.html stats.html + $(echo "$GUIDE_PAGES" | grep -c . ) guide pages"
# shellcheck disable=SC2086
if ! npx --no-install htmlhint index.html stats.html $GUIDE_PAGES; then
  fail=1
fi

gray "  stylelint style.css stats.css guides.css"
if ! npx --no-install stylelint style.css stats.css guides.css; then
  fail=1
fi

gray "  node --check guide-demo.js"
if ! node --check guide-demo.js; then
  red "  guide-demo.js has a syntax error"
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
