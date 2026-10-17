#!/usr/bin/env bash
# Controle: build en tests draaien. Faalt de build, dan wordt de service overgeslagen
# en komt er geen PR.
# Optioneel uit config.env: MVN_VERIFY_ARGS="-DskipITs"
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"

# Een controle wijzigt niets: alles wat de build aanmaakt of wijzigt (target/,
# dependency-reduced-pom.xml, node_modules/, ...) wordt na afloop teruggedraaid, ook
# als de build faalt. Leg daarom eerst de huidige stand vast in de index.
git add -A
herstel() {
  git clean -fdq
  git checkout -q -- . 2>/dev/null || true
  git reset -q
}
trap herstel EXIT

# shellcheck disable=SC2086
"$(mvn_cmd)" -B ${MVN_VERIFY_ARGS:-} verify
