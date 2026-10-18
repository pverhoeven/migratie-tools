#!/usr/bin/env bash
# Transformatie: dependency-versies ophogen, bv. bij een kwetsbaarheid, en het resultaat
# committen ("fix(deps): <artifactId> naar <versie>"). Per groupId:artifactId:versie draaien
# twee standaardrecepten van OpenRewrite, zonder eigen recept:
#   - UpgradeDependencyVersion: de service noemt de dependency zelf (ook met de versie in
#     een property, dependencyManagement of beheerd door een parent of BOM)
#   - UpgradeTransitiveDependencyVersion: de dependency komt er indirect in; de versie
#     komt dan in dependencyManagement
# Beide doen alleen iets als de huidige versie lager is; een service die al veilig is of
# de dependency niet gebruikt, blijft ongewijzigd.
#
# Uit het migratiebestand: DEPENDENCY_VERSIE (een of meer groupId:artifactId:versie,
# gescheiden door spaties)
# Optioneel uit config.env: MVN_ARGS (extra Maven-argumenten)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"

: "${DEPENDENCY_VERSIE:?zet DEPENDENCY_VERSIE}"
plugin="$(sed -n 's:.*<rewrite-maven-plugin.version>\(.*\)</rewrite-maven-plugin.version>.*:\1:p' "$ROOT/recepten/pom.xml")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
{
  echo "type: specs.openrewrite.org/v1beta/recipe"
  echo "name: local.migratietools.DependencyVersie"
  echo "displayName: Dependency-versies ophogen"
  echo "recipeList:"
  for d in $DEPENDENCY_VERSIE; do
    IFS=: read -r g a v <<< "$d"
    cat <<EOF
  - org.openrewrite.maven.UpgradeDependencyVersion:
      groupId: "$g"
      artifactId: "$a"
      newVersion: "$v"
      overrideManagedVersion: true
  - org.openrewrite.maven.UpgradeTransitiveDependencyVersion:
      groupId: "$g"
      artifactId: "$a"
      version: "$v"
      because: "migratie ${MIGRATIE:-?}"
EOF
  done
} > "$tmp/rewrite.yml"

args=(-B "org.openrewrite.maven:rewrite-maven-plugin:${plugin}:run"
      "-Drewrite.configLocation=$tmp/rewrite.yml"
      "-Drewrite.activeRecipes=local.migratietools.DependencyVersie")

# shellcheck disable=SC2086
if ! "$(mvn_cmd)" "${args[@]}" ${MVN_ARGS:-}; then
  reden "dependency-versies ophogen faalt (zie de Maven-output)"
  exit 1
fi

# Build-output van de plugin hoort niet in de commit.
"$ROOT/lib/opruimen.sh"
if [ -n "$(git status --porcelain)" ]; then
  onderwerp="$(for d in $DEPENDENCY_VERSIE; do IFS=: read -r _ a v <<< "$d"; printf '%s naar %s, ' "$a" "$v"; done | sed 's/, $//')"
  commit_alles "fix(deps): $onderwerp"
fi
