#!/usr/bin/env bash
# Stap: build en tests draaien. Faalt de build, dan wordt de repo overgeslagen
# en komt er dus geen PR.
# Optioneel: MVN_VERIFY_ARGS="-DskipITs"
set -euo pipefail
. "$(dirname "$0")/_lib.sh"

require_pom

# Alles wat de build aanmaakt of wijzigt (target/, dependency-reduced-pom.xml,
# node_modules/, ...) hoort niet in de commit. Leg daarom de huidige stand vast
# in de index en zet die na de build terug, ook als de build faalt.
git add -A
restore() {
  git clean -fdq
  git checkout -q -- . 2>/dev/null || true
  git reset -q
}
trap restore EXIT

# shellcheck disable=SC2086
"$(mvn_cmd)" -B ${MVN_VERIFY_ARGS:-} verify
