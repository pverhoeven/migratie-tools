#!/usr/bin/env bash
# Transformatie: één OpenRewrite-recept draaien via de Maven-plugin en het resultaat
# committen ("recept: <naam>").
#
# Uit het migratiebestand: RECEPT, REWRITE_PLUGIN_VERSION, REWRITE_RECIPE_ARTIFACTS
# Optioneel uit config.env: MVN_ARGS (extra Maven-argumenten)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"

: "${RECEPT:?zet RECEPT}"
: "${REWRITE_PLUGIN_VERSION:?zet REWRITE_PLUGIN_VERSION}"

args=(-B "org.openrewrite.maven:rewrite-maven-plugin:${REWRITE_PLUGIN_VERSION}:run"
      "-Drewrite.activeRecipes=${RECEPT}")
if [ -n "${REWRITE_RECIPE_ARTIFACTS:-}" ]; then
  args+=("-Drewrite.recipeArtifactCoordinates=${REWRITE_RECIPE_ARTIFACTS}")
fi

# shellcheck disable=SC2086
"$(mvn_cmd)" "${args[@]}" ${MVN_ARGS:-}

# Build-output van de plugin hoort niet in de commit.
"$ROOT/lib/opruimen.sh"
if [ -n "$(git status --porcelain)" ]; then
  commit_alles "recept: $RECEPT"
fi
