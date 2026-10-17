#!/usr/bin/env bash
# Draait één migratie binnen één gekloonde service (cwd = repo). Wordt gebruikt door
# zowel run.sh (via multi-gitter) als local.sh; de waarden uit het migratiebestand
# staan in de environment. Elke transformatie commit zijn eigen wijzigingen.
#
# Optioneel: ZONDER_VERIFY=1 slaat de controle over (alleen bij een dry-run).
#            RESULTATEN=<bestand>: hier komt één regel met de uitkomst bij.
#
# Exit-codes (multi-gitter maakt alleen bij 0 een PR, en alleen als er commits zijn):
#   0  Gewijzigd of Ongewijzigd
#   10 Niet van toepassing
#   20 Handwerk nodig
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

: "${MIGRATIE:?zet MIGRATIE}"
SERVICE="${REPOSITORY:-$(basename "$PWD")}"   # REPOSITORY zet multi-gitter

REDEN_BESTAND="$(mktemp)"
export REDEN_BESTAND
trap 'rm -f "$REDEN_BESTAND"' EXIT

uitkomst() {  # <exit-code> <uitkomst> [reden]
  if [ -n "${RESULTATEN:-}" ]; then
    printf '%s\t%s\t%s\n' "$SERVICE" "$2" "${3:-}" >> "$RESULTATEN"
  fi
  echo "== $SERVICE: $2${3:+ ($3)}"
  exit "$1"
}
handwerk() {  # <standaardreden>; een transformatie of controle kan een betere reden geven
  local r
  r="$(cat "$REDEN_BESTAND")"
  uitkomst 20 "Handwerk nodig" "${r:-$1}"
}

# Het token is alleen voor multi-gitter zelf; de builds (tests, plugins) van de
# services hoeven het niet te zien.
unset GITLAB_TOKEN

# Van toepassing? Eén keer bepaald, voor alle transformaties van de migratie samen.
if [ ! -f pom.xml ]; then
  uitkomst 10 "Niet van toepassing" "geen pom.xml"
fi
if [ -n "${TEMPLATE_VERSION:-}" ] && [ ! -f .cruft.json ]; then
  uitkomst 10 "Niet van toepassing" "geen template-service (geen .cruft.json)"
fi

start="$(git rev-parse HEAD)"

# Transformaties, in vaste volgorde: eerst het template, dan het recept.
if [ -n "${TEMPLATE_VERSION:-}" ]; then
  echo ">> transformatie: template naar $TEMPLATE_VERSION"
  "$ROOT/transformaties/template-update.sh" || handwerk "template-update naar $TEMPLATE_VERSION mislukt"
fi
if [ -n "${RECEPT:-}" ]; then
  echo ">> transformatie: recept $RECEPT"
  "$ROOT/transformaties/recept.sh" || handwerk "recept $RECEPT mislukt"
fi

# Controle
if [ "${ZONDER_VERIFY:-0}" = "1" ]; then
  echo ">> controle: verify overgeslagen"
else
  echo ">> controle: verify"
  "$ROOT/controles/verify.sh" || handwerk "controle verify is rood (build of tests)"
fi

"$ROOT/lib/opruimen.sh"

if [ "$(git rev-parse HEAD)" = "$start" ]; then
  uitkomst 0 "Ongewijzigd"
fi
uitkomst 0 "Gewijzigd" "$(git rev-list --count "$start..HEAD") commit(s)"
