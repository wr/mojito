#!/usr/bin/env bash
# Pre-publish check workflow for mojito-site.
# Runs every check in scripts/checks/. Each is independently runnable.
#
# Flags:
#   --skip-images       skip image auto-compression
#   --skip-lint         skip html/css/js linters
#   --skip-meta         skip OG/Twitter/SEO metadata check
#   --skip-links        skip lychee link check
#   --skip-lighthouse   skip Lighthouse
#   --no-external       link check stays offline (no external HEAD requests)
#   --ci                report only — images script reports deltas instead of staging

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_IMAGES=0
SKIP_LINT=0
SKIP_META=0
SKIP_LINKS=0
SKIP_LH=0
NO_EXTERNAL=0
CI_MODE=0

for arg in "$@"; do
  case "$arg" in
    --skip-images)      SKIP_IMAGES=1 ;;
    --skip-lint)        SKIP_LINT=1 ;;
    --skip-meta)        SKIP_META=1 ;;
    --skip-links)       SKIP_LINKS=1 ;;
    --skip-lighthouse)  SKIP_LH=1 ;;
    --no-external)      NO_EXTERNAL=1 ;;
    --ci)               CI_MODE=1 ;;
    -h|--help)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    *)
      printf 'unknown flag: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
red()    { printf '\033[1;31m%s\033[0m\n' "$*"; }
green()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }

results=()
run() {
  local name="$1" cmd="$2"
  bold "▸ $name"
  if eval "$cmd"; then
    results+=("✓ $name")
    return 0
  else
    results+=("✗ $name")
    return 1
  fi
}

failed=0
[[ $SKIP_IMAGES -eq 0 ]] && { run images "scripts/checks/images.sh $([[ $CI_MODE -eq 1 ]] && echo --ci)" || failed=1; }
[[ $SKIP_LINT   -eq 0 ]] && { run lint   "scripts/checks/lint.sh"   || failed=1; }
[[ $SKIP_META   -eq 0 ]] && { run meta   "scripts/checks/meta.sh"   || failed=1; }
[[ $SKIP_LINKS  -eq 0 ]] && { run links  "scripts/checks/links.sh $([[ $NO_EXTERNAL -eq 1 ]] && echo --no-external)" || failed=1; }
[[ $SKIP_LH     -eq 0 ]] && { run lighthouse "scripts/checks/lighthouse.sh" || failed=1; }

echo
bold "── summary ──"
for r in ${results[@]+"${results[@]}"}; do
  case "$r" in
    ✓*) green "  $r" ;;
    ✗*) red   "  $r" ;;
  esac
done

if [[ $failed -eq 1 ]]; then
  echo
  red "one or more checks failed"
  exit 1
fi

echo
green "all checks passed"
exit 0
