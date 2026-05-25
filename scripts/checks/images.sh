#!/usr/bin/env bash
# Auto-compress every tracked PNG/JPG/SVG/GIF in place.
# Idempotent — re-runs on already-optimized files are no-ops.
# In --ci mode, reports size deltas but does not modify files.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CI_MODE=0
[[ "${1:-}" == "--ci" ]] && CI_MODE=1

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
gray()   { printf '\033[90m%s\033[0m\n' "$*"; }

need() { command -v "$1" >/dev/null 2>&1 || { red "missing tool: $1 (try: brew bundle)"; exit 1; }; }
need oxipng
need jpegoptim
need svgo
need gifsicle

IMAGES=$(git ls-files '*.png' '*.jpg' '*.jpeg' '*.svg' '*.gif' 2>/dev/null || true)
if [[ -z "$IMAGES" ]]; then
  gray "no tracked images"
  exit 0
fi

changed=0
while IFS= read -r img; do
  [[ -z "$img" || ! -f "$img" ]] && continue
  before=$(stat -f%z "$img" 2>/dev/null || stat -c%s "$img")
  tmp=$(mktemp -t mojito-img)
  cp "$img" "$tmp"

  case "$img" in
    *.png)            oxipng -o4 --strip safe --quiet "$tmp" || true ;;
    *.jpg|*.jpeg)     jpegoptim --strip-all --quiet -m92 "$tmp" >/dev/null 2>&1 || true ;;
    *.svg)            svgo --multipass --quiet -i "$tmp" -o "$tmp" >/dev/null 2>&1 || true ;;
    *.gif)            gifsicle -O3 -o "$tmp" "$tmp" >/dev/null 2>&1 || true ;;
  esac

  after=$(stat -f%z "$tmp" 2>/dev/null || stat -c%s "$tmp")
  delta=$((before - after))

  if [[ $delta -gt 0 ]]; then
    pct=$(( delta * 100 / before ))
    if [[ $CI_MODE -eq 1 ]]; then
      yellow "  could shrink $img by ${delta}B (${pct}%)"
      rm -f "$tmp"
      changed=1
    else
      mv "$tmp" "$img"
      git add "$img" 2>/dev/null || true
      green "  shrunk $img by ${delta}B (${pct}%) and staged"
      changed=1
    fi
  else
    rm -f "$tmp"
  fi
done <<< "$IMAGES"

if [[ $CI_MODE -eq 1 && $changed -eq 1 ]]; then
  red "image check failed — run ./scripts/checks/images.sh to compress"
  exit 1
fi

[[ $changed -eq 0 ]] && gray "all images already optimal"
exit 0
