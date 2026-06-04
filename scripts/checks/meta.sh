#!/usr/bin/env bash
# Validate social/OG/SEO metadata in index.html.
# Required tags, sensible length bounds, og-image dimensions ~1200x630.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
gray()   { printf '\033[90m%s\033[0m\n' "$*"; }

fail=0

HTML="$(cat index.html)"

# Extract content of a tag, e.g. attr_val 'property' 'og:title'
attr_val() {
  local key="$1" name="$2"
  printf '%s' "$HTML" \
    | tr '\n' ' ' \
    | grep -oE "<meta[^>]*${key}=[\"']${name}[\"'][^>]*>" \
    | head -1 \
    | sed -E "s/.*content=[\"']([^\"']*)[\"'].*/\1/"
}

title_text() {
  printf '%s' "$HTML" | tr '\n' ' ' | grep -oE '<title[^>]*>[^<]*</title>' | head -1 | sed -E 's,</?title[^>]*>,,g'
}

link_href() {
  local rel="$1"
  printf '%s' "$HTML" | tr '\n' ' ' \
    | grep -oE "<link[^>]*rel=[\"']${rel}[\"'][^>]*>" \
    | head -1 \
    | sed -E "s/.*href=[\"']([^\"']*)[\"'].*/\1/"
}

check_len() {
  local label="$1" val="$2" min="$3" max="$4"
  local n=${#val}
  if [[ -z "$val" ]]; then
    red "  missing: $label"
    fail=1
  elif [[ $n -lt $min || $n -gt $max ]]; then
    yellow "  $label length $n outside [$min,$max]: \"$val\""
    fail=1
  else
    gray "  ✓ $label (${n} chars)"
  fi
}

check_present() {
  local label="$1" val="$2"
  if [[ -z "$val" ]]; then
    red "  missing: $label"
    fail=1
  else
    gray "  ✓ $label = $val"
  fi
}

check_len  "<title>"               "$(title_text)"                       30 65
check_len  "meta description"      "$(attr_val name description)"        70 160
check_present "canonical link"     "$(link_href canonical)"
check_present "apple-touch-icon"   "$(link_href apple-touch-icon)"

check_present "og:title"           "$(attr_val property og:title)"
check_present "og:description"     "$(attr_val property og:description)"
check_present "og:image"           "$(attr_val property og:image)"
check_present "og:url"             "$(attr_val property og:url)"
check_present "og:type"            "$(attr_val property og:type)"

check_present "twitter:card"       "$(attr_val name twitter:card)"
check_present "twitter:title"      "$(attr_val name twitter:title)"
check_present "twitter:description" "$(attr_val name twitter:description)"
check_present "twitter:image"      "$(attr_val name twitter:image)"

# og-image dimensions (macOS-only via sips). The recommended size is 1200x630.
if [[ -f og-image.png ]] && command -v sips >/dev/null 2>&1; then
  w=$(sips -g pixelWidth  og-image.png 2>/dev/null | awk '/pixelWidth/  {print $2}')
  h=$(sips -g pixelHeight og-image.png 2>/dev/null | awk '/pixelHeight/ {print $2}')
  if [[ -n "$w" && -n "$h" ]]; then
    ratio=$(awk -v w="$w" -v h="$h" 'BEGIN { printf "%.3f", w/h }')
    if [[ "$w" -lt 1200 || "$h" -lt 600 ]]; then
      yellow "  og-image.png is ${w}x${h} — should be at least 1200x630"
      fail=1
    elif awk -v r="$ratio" 'BEGIN { exit !(r < 1.7 || r > 2.1) }'; then
      yellow "  og-image.png aspect ratio $ratio is off (target ~1.91)"
      fail=1
    else
      gray "  ✓ og-image.png ${w}x${h} (ratio $ratio)"
    fi
  fi
fi

if [[ $fail -eq 1 ]]; then
  red "meta check failed"
  exit 1
fi
green "  meta OK"
exit 0
