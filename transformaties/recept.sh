#!/usr/bin/env bash
# Transformatie: één recept draaien via de Maven-plugin en het resultaat committen
# ("chore(recept): <naam>"). De recepten (recepten/ en eventueel RECEPTEN_MAP) zijn aan het
# begin van de run lokaal geïnstalleerd; de plugin-versie staat in recepten/pom.xml.
#
# Uit het migratiebestand: RECEPT
# Optioneel uit config.env: MVN_ARGS (extra Maven-argumenten)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/recepten.sh"

: "${RECEPT:?zet RECEPT}"
plugin="$(sed -n 's:.*<rewrite-maven-plugin.version>\(.*\)</rewrite-maven-plugin.version>.*:\1:p' "$ROOT/recepten/pom.xml")"

args=(-B "org.openrewrite.maven:rewrite-maven-plugin:${plugin}:run"
      "-Drewrite.activeRecipes=${RECEPT}"
      "-Drewrite.recipeArtifactCoordinates=${RECEPTEN_ARTEFACTEN:-$RECEPTEN_ARTEFACT}")

# shellcheck disable=SC2086
if ! "$(mvn_cmd)" "${args[@]}" ${MVN_ARGS:-}; then
  reden "recept $RECEPT faalt (zie de Maven-output)"
  exit 1
fi

# Build-output van de plugin hoort niet in de commit.
"$ROOT/lib/opruimen.sh"
if [ -n "$(git status --porcelain)" ]; then
  commit_alles "chore(recept): $RECEPT"
fi
