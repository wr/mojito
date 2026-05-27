#!/usr/bin/env bash
# Launch Mojito Dev.app in a specific locale so you can spot-check the
# translated UI without changing your Mac's system language.
#
# Usage:
#   scripts/run-locale.sh <locale>
#
# Locale codes match `knownRegions` in project.yml — bare codes like
# `fr`, `ja`, `zh-Hans`, `ar`, etc. The script picks a sensible
# AppleLocale (region) to go with each language so date/number
# formatting reads right.
#
# The currently-running Mojito Dev instance is killed first, since
# SingleInstanceCoordinator would otherwise terminate the new launch.
# After your test, normal launches (Spotlight / Dock) go back to your
# system language — the override only applies to launches via this
# script.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    cat >&2 <<EOF
usage: $(basename "$0") <locale>
examples: en, en-GB, de, es, es-419, fr, it, pt-BR, ja, zh-Hans, zh-Hant,
          ko, hi, ru, pl, nl, ar, fa, he
EOF
    exit 1
fi

LOCALE=$1
case "$LOCALE" in
    en)      APPLE_LOCALE=en_US ;;
    en-GB)   APPLE_LOCALE=en_GB ;;
    de)      APPLE_LOCALE=de_DE ;;
    es)      APPLE_LOCALE=es_ES ;;
    es-419)  APPLE_LOCALE=es_419 ;;
    fr)      APPLE_LOCALE=fr_FR ;;
    it)      APPLE_LOCALE=it_IT ;;
    pt-BR)   APPLE_LOCALE=pt_BR ;;
    ja)      APPLE_LOCALE=ja_JP ;;
    zh-Hans) APPLE_LOCALE=zh_CN ;;
    zh-Hant) APPLE_LOCALE=zh_TW ;;
    ko)      APPLE_LOCALE=ko_KR ;;
    hi)      APPLE_LOCALE=hi_IN ;;
    ru)      APPLE_LOCALE=ru_RU ;;
    pl)      APPLE_LOCALE=pl_PL ;;
    nl)      APPLE_LOCALE=nl_NL ;;
    ar)      APPLE_LOCALE=ar_SA ;;
    fa)      APPLE_LOCALE=fa_IR ;;
    he)      APPLE_LOCALE=he_IL ;;
    *)
        echo "unknown locale: $LOCALE" >&2
        echo "supported: en, en-GB, de, es, es-419, fr, it, pt-BR, ja, zh-Hans, zh-Hant, ko, hi, ru, pl, nl, ar, fa, he" >&2
        exit 1
        ;;
esac

APP="/Applications/Mojito Dev.app"
if [[ ! -d "$APP" ]]; then
    echo "Mojito Dev.app not found at $APP — build a Debug config first." >&2
    exit 1
fi

pkill -f "Mojito Dev" || true
# Brief pause so the old instance's resources release before launchd
# tries to fire the new one.
sleep 0.3

echo "Launching Mojito Dev with AppleLanguages=($LOCALE), AppleLocale=$APPLE_LOCALE"
open -n "$APP" --args -AppleLanguages "($LOCALE)" -AppleLocale "$APPLE_LOCALE"
