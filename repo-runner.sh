#!/usr/bin/env bash
# Draait één migratie binnen één gekloonde service (cwd = repo). Wordt gebruikt door
# run.sh (via multi-gitter), uitproberen.sh en in-repo.sh; de waarden uit het migratiebestand
# staan in de environment. Elke transformatie commit zijn eigen wijzigingen.
#
# Optioneel: ZONDER_VERIFY=1 slaat de controle over (alleen bij een dry-run).
#            RESULTATEN=<bestand>: hier komt één regel met de uitkomst bij
#            (service, uitkomst, reden, stop-commit: de volledige template-commit waar
#            de cruft update stopte, anders leeg).
#            DEBUG_MAP=<map>: schrijf per service naar <map>/<service>/ de uitvoer
#            (uitvoer.log), de commits als patch (wijzigingen.patch) en bij handwerk
#            de stand waarin de migratie stopte (onafgemaakt.diff, status.txt).
#            WAARSCHUWINGEN=<bestand>: hier komen de waarschuwingen van de
#            transformaties bij (service, tekst), voor de MR-beschrijving.
#            BASIS=<commit>: vergelijk hiermee voor Gewijzigd/Ongewijzigd (in-repo.sh:
#            het begin van de branch); standaard de commit bij de start.
#
# Exit-codes (multi-gitter maakt alleen bij 0 een PR, en alleen als er commits zijn):
#   0  Gewijzigd of Ongewijzigd
#   10 Niet van toepassing
#   20 Handwerk nodig
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"

: "${MIGRATIE:?zet MIGRATIE}"
SERVICE="${REPOSITORY:-$(basename "$PWD")}"   # REPOSITORY zet multi-gitter
export SERVICE   # voor waarschuwing (lib/common.sh)

REDEN_BESTAND="$(mktemp)"
STOP_BESTAND="$(mktemp)"
export REDEN_BESTAND STOP_BESTAND
trap 'rm -f "$REDEN_BESTAND" "$STOP_BESTAND"' EXIT

if [ -n "${DEBUG_MAP:-}" ]; then
  DEBUG="$DEBUG_MAP/$SERVICE"
  mkdir -p "$DEBUG"
  exec > >(tee "$DEBUG/uitvoer.log") 2>&1
fi

schrijf_debug() {
  [ -n "${DEBUG:-}" ] && [ -n "${start:-}" ] || return 0
  if [ "$(git rev-parse HEAD)" != "$start" ]; then
    git format-patch -q --stdout "$start..HEAD" > "$DEBUG/wijzigingen.patch"
  fi
  if [ -n "$(git status --porcelain)" ]; then
    git status --short > "$DEBUG/status.txt"
    git diff HEAD > "$DEBUG/onafgemaakt.diff" || true
  fi
}

uitkomst() {  # <exit-code> <uitkomst> [reden]
  schrijf_debug
  if [ -n "${RESULTATEN:-}" ]; then
    printf '%s\t%s\t%s\t%s\n' "$SERVICE" "$2" "${3:-}" "$(cat "$STOP_BESTAND")" >> "$RESULTATEN"
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
if [ -n "${ALLEEN_MET_DEPENDENCY:-}" ] && ! find . -path ./.git -prune -o -name pom.xml -print0 \
     | xargs -0 grep -qs "<artifactId>$ALLEEN_MET_DEPENDENCY</artifactId>"; then
  uitkomst 10 "Niet van toepassing" "gebruikt $ALLEEN_MET_DEPENDENCY niet"
fi
if [ -n "${CRUFT_UPDATE:-}${CRUFT_ZET:-}" ] && [ ! -f .cruft.json ]; then
  if [ -n "${ALLEEN_MET_DEPENDENCY:-}" ]; then
    uitkomst 10 "Niet van toepassing" "afnemer zonder template (geen .cruft.json)"
  fi
  uitkomst 10 "Niet van toepassing" "geen template-service (geen .cruft.json)"
fi

start="${BASIS:-$(git rev-parse HEAD)}"

# Transformaties, in vaste volgorde: cruft update, variabelen omzetten, recept,
# dependency-versies.
if [ -n "${CRUFT_UPDATE:-}" ]; then
  echo ">> transformatie: cruft update"
  "$ROOT/transformaties/cruft-update.sh" || {
    # 10: het template van de service heeft de TEMPLATE_REF niet (een ander template)
    [ $? -eq 10 ] && uitkomst 10 "Niet van toepassing" "$(cat "$REDEN_BESTAND")"
    handwerk "cruft update mislukt"
  }
fi
for z in ${CRUFT_ZET:-}; do
  echo ">> transformatie: template-variabele $z"
  "$ROOT/transformaties/cruft-zet.sh" "$z" || handwerk "template-variabele $z omzetten mislukt"
done
if [ -n "${RECEPT:-}" ]; then
  echo ">> transformatie: recept $RECEPT"
  "$ROOT/transformaties/recept.sh" || handwerk "recept $RECEPT mislukt"
fi
if [ -n "${DEPENDENCY_VERSIE:-}" ]; then
  echo ">> transformatie: dependency-versies $DEPENDENCY_VERSIE"
  "$ROOT/transformaties/dependency-versie.sh" || handwerk "dependency-versies ophogen mislukt"
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
reden="$(git rev-list --count "$start..HEAD") commit(s)"
if [ -n "${CRUFT_UPDATE:-}${CRUFT_ZET:-}" ]; then reden+=", template $(jq -r '.commit[0:7]' .cruft.json)"; fi
uitkomst 0 "Gewijzigd" "$reden"
