#!/usr/bin/env bash
# Draait één migratie over alle services in een GitLab-groep via multi-gitter.
# Standaard een DRY RUN (geen push, geen PR's). Voeg --go toe om echt PR's aan te maken.
#
# Gebruik: ./run.sh <migratiebestand> [--go] [--zonder-verify] [extra multi-gitter flags]
# Voorbeelden:
#   ./run.sh migraties/template-v1.4.0.env
#   ./run.sh migraties/template-v1.4.0.env --repo-include 'payments-.*'
#   ./run.sh migraties/template-v1.4.0.env --go
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/migratie.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi

if [ $# -lt 1 ]; then
  echo "gebruik: $0 <migratiebestand> [--go] [--zonder-verify] [multi-gitter flags]" >&2
  exit 2
fi
laad_migratie "$1"; shift

: "${GITLAB_TOKEN:?zet GITLAB_TOKEN (in config.env of je shell)}"
: "${GITLAB_GROUP:?zet GITLAB_GROUP (in config.env of je shell)}"

go=0
ZONDER_VERIFY=0
extra=()
for a in "$@"; do
  case "$a" in
    --go) go=1 ;;
    --zonder-verify) ZONDER_VERIFY=1 ;;
    *) extra+=("$a") ;;
  esac
done
export ZONDER_VERIFY

# Een echte run is vastgepind op een commit van deze repo (docs/adr/0002).
versie="$(git -C "$ROOT" rev-parse --short HEAD)"
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  if [ "$go" -eq 1 ]; then
    echo "--go vereist een schone werkmap in migratie-tools: commit eerst je wijzigingen" >&2
    exit 2
  fi
  versie="$versie (met lokale wijzigingen)"
fi
if [ "$go" -eq 1 ] && [ "$ZONDER_VERIFY" = "1" ]; then
  echo "--zonder-verify mag alleen bij een dry-run" >&2
  exit 2
fi

transformaties=""
[ -n "${TEMPLATE_VERSION:-}" ] && transformaties+="- template-update naar \`$TEMPLATE_VERSION\`"$'\n'
[ -n "${RECEPT:-}" ] && transformaties+="- recept \`$RECEPT\`"$'\n'

args=(run "$ROOT/repo-runner.sh"
  --platform gitlab
  --group "$GITLAB_GROUP"
  --branch "migratie/$MIGRATIE"
  --manual-commit
  --pr-title "Migratie: $MIGRATIE"
  --pr-body "Automatisch aangemaakt door migratie-tools, migratie \`$MIGRATIE\` (migratie-tools $versie).

${transformaties}
Elke transformatie is een eigen commit. Controleer de diff en merge."
  --labels "migratie,$MIGRATIE"
  --conflict-strategy skip
  --concurrent "${CONCURRENT:-4}")

if [ -n "${GITLAB_BASE_URL:-}" ]; then
  args+=(--base-url "$GITLAB_BASE_URL")
fi
if [ "$go" -eq 0 ]; then
  echo "DRY RUN: er wordt niets gepusht. Gebruik --go om PR's aan te maken."
  args+=(--dry-run)
fi

exec multi-gitter "${args[@]}" ${extra[@]+"${extra[@]}"}
