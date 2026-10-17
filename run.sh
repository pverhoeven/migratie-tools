#!/usr/bin/env bash
# Draait dezelfde stappen over alle repo's in een GitLab-groep via multi-gitter.
# Standaard een DRY RUN (geen push, geen PR's). Voeg --go toe om echt PR's aan te maken.
#
# Gebruik: ./run.sh <stappen> [--go] [extra multi-gitter flags]
# Voorbeelden:
#   ./run.sh cruft-update
#   ./run.sh cruft-update,openrewrite,verify --repo-include 'payments-.*'
#   ./run.sh openrewrite,verify --go --labels migratie
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi

if [ $# -lt 1 ]; then
  echo "gebruik: $0 <stappen> [--go] [multi-gitter flags]" >&2
  echo "stappen: $(cd "$ROOT/steps" && ls *.sh | grep -v '^_' | sed 's/\.sh$//' | paste -sd, -)" >&2
  exit 2
fi

STEPS="$1"; shift
STEPS_DIR="$ROOT/steps"

IFS=',' read -ra list <<< "$STEPS"
for s in "${list[@]}"; do
  [ -f "$STEPS_DIR/$s.sh" ] || { echo "onbekende stap: $s" >&2; exit 2; }
done

: "${GITLAB_TOKEN:?zet GITLAB_TOKEN (in config.env of je shell)}"
: "${GITLAB_GROUP:?zet GITLAB_GROUP (in config.env of je shell)}"
export STEPS STEPS_DIR

go=0
extra=()
for a in "$@"; do
  if [ "$a" = "--go" ]; then go=1; else extra+=("$a"); fi
done

BRANCH="migratie-${STEPS//,/-}"

args=(run "$ROOT/repo-runner.sh"
  --platform gitlab
  --group "$GITLAB_GROUP"
  --branch "$BRANCH"
  --commit-message "chore: ${STEPS//,/ + }"
  --pr-title "Automatische update: ${STEPS//,/ + }"
  --pr-body "Automatisch aangemaakt door migratie-tools (stappen: ${STEPS}). Controleer de diff en merge."
  --conflict-strategy replace
  --concurrent "${CONCURRENT:-4}")

if [ -n "${GITLAB_BASE_URL:-}" ]; then
  args+=(--base-url "$GITLAB_BASE_URL")
fi
if [ "$go" -eq 0 ]; then
  echo "DRY RUN: er wordt niets gepusht. Gebruik --go om PR's aan te maken."
  args+=(--dry-run --print-output)
fi

exec multi-gitter "${args[@]}" ${extra[@]+"${extra[@]}"}
