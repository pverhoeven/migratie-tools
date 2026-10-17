#!/usr/bin/env bash
# Draait één migratie binnen één gekloonde service (cwd = repo). Wordt gebruikt door
# zowel run.sh (via multi-gitter) als local.sh; de waarden uit het migratiebestand
# staan in de environment. Elke transformatie commit zijn eigen wijzigingen.
#
# Optioneel: ZONDER_VERIFY=1 slaat de controle over (alleen bij een dry-run).
# Exit 0 = eventueel iets gewijzigd; non-zero = service overslaan.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

: "${MIGRATIE:?zet MIGRATIE}"

# Het token is alleen voor multi-gitter zelf; de builds (tests, plugins) van de
# services hoeven het niet te zien.
unset GITLAB_TOKEN

# Van toepassing? Eén keer bepaald, voor alle transformaties van de migratie samen.
if [ ! -f pom.xml ]; then
  echo "niet van toepassing: geen pom.xml"; exit 1
fi
if [ -n "${TEMPLATE_VERSION:-}" ] && [ ! -f .cruft.json ]; then
  echo "niet van toepassing: geen template-service (geen .cruft.json)"; exit 1
fi

# Transformaties, in vaste volgorde: eerst het template, dan het recept.
if [ -n "${TEMPLATE_VERSION:-}" ]; then
  echo ">> transformatie: template naar $TEMPLATE_VERSION"
  "$ROOT/transformaties/template-update.sh"
fi
if [ -n "${RECEPT:-}" ]; then
  echo ">> transformatie: recept $RECEPT"
  "$ROOT/transformaties/recept.sh"
fi

# Controle
if [ "${ZONDER_VERIFY:-0}" = "1" ]; then
  echo ">> controle: verify overgeslagen"
else
  echo ">> controle: verify"
  "$ROOT/controles/verify.sh"
fi

"$ROOT/lib/opruimen.sh"
