#!/usr/bin/env bash
# Stap: OpenRewrite-recepten draaien via de Maven-plugin.
#
# Verplicht:
#   REWRITE_PLUGIN_VERSION   versie van rewrite-maven-plugin
#   REWRITE_RECIPES          komma-gescheiden lijst met recepten
# Optioneel:
#   REWRITE_RECIPE_ARTIFACTS komma-gescheiden groupId:artifactId:version
#   REWRITE_CONFIG           pad naar een (centrale) rewrite.yml
#   REWRITE_GOAL             run (standaard) of dryRun
#   REWRITE_PATCH_OUT        bij dryRun: bestand waarin de patch bewaard wordt
#                            (local.sh zet dit op work/<naam>.rewrite.patch)
#   MVN_ARGS                 extra Maven-argumenten
set -euo pipefail
. "$(dirname "$0")/_lib.sh"

require_pom
: "${REWRITE_PLUGIN_VERSION:?zet REWRITE_PLUGIN_VERSION}"
: "${REWRITE_RECIPES:?zet REWRITE_RECIPES}"

goal="${REWRITE_GOAL:-run}"
args=(-B "org.openrewrite.maven:rewrite-maven-plugin:${REWRITE_PLUGIN_VERSION}:${goal}"
      "-Drewrite.activeRecipes=${REWRITE_RECIPES}")

if [ -n "${REWRITE_RECIPE_ARTIFACTS:-}" ]; then
  args+=("-Drewrite.recipeArtifactCoordinates=${REWRITE_RECIPE_ARTIFACTS}")
fi
if [ -n "${REWRITE_CONFIG:-}" ]; then
  args+=("-Drewrite.configLocation=${REWRITE_CONFIG}")
fi

# shellcheck disable=SC2086
"$(mvn_cmd)" "${args[@]}" ${MVN_ARGS:-}

# Bij dryRun staat het resultaat in target/rewrite/rewrite.patch, en target/
# wordt na de stappen opgeruimd. Toon en bewaar de patch daarom hier.
if [ "$goal" = "dryRun" ]; then
  found=0
  while IFS= read -r p; do
    found=1
    echo "--- $p"
    cat "$p"
    if [ -n "${REWRITE_PATCH_OUT:-}" ]; then cat "$p" >> "$REWRITE_PATCH_OUT"; fi
  done < <(find . -path ./.git -prune -o -path '*/target/rewrite/rewrite.patch' -print)
  [ "$found" = 1 ] || echo "dryRun: geen wijzigingen"
fi
