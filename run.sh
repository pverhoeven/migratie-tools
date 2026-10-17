#!/usr/bin/env bash
# Draait één migratie over alle services in een GitLab-groep via multi-gitter.
# Standaard een DRY RUN (geen push, geen PR's). Voeg --go toe om echt PR's aan te maken.
#
# Gebruik: ./run.sh <migratiebestand> [--go] [--zonder-verify] [extra multi-gitter flags]
# Voorbeelden:
#   ./run.sh migraties/template-2026-10.env
#   ./run.sh migraties/template-2026-10.env --repo-include 'payments-.*'
#   ./run.sh migraties/template-2026-10.env --go
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/migratie.sh"
. "$ROOT/lib/recepten.sh"
. "$ROOT/lib/gitlab.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi

if [ $# -lt 1 ]; then
  echo "gebruik: $0 <migratiebestand> [--go] [--zonder-verify] [multi-gitter flags]" >&2
  exit 2
fi
laad_migratie "$1"; shift
vereist multi-gitter curl jq

: "${GITLAB_TOKEN:?zet GITLAB_TOKEN (in config.env of je shell)}"
: "${GITLAB_GROUP:?zet GITLAB_GROUP (in config.env of je shell)}"

go=0
ZONDER_VERIFY=0
extra=()
uitsluiten=()
while [ $# -gt 0 ]; do
  case "$1" in
    --go) go=1 ;;
    --zonder-verify) ZONDER_VERIFY=1 ;;
    # wordt samengevoegd met de uitsluitlijst en de wachtende services
    --repo-exclude) uitsluiten+=("$2"); shift ;;
    --repo-exclude=*) uitsluiten+=("${1#*=}") ;;
    *) extra+=("$1") ;;
  esac
  shift
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
[ -n "${CRUFT_UPDATE:-}" ] && transformaties+="- cruft update naar de nieuwste stand van het template (één commit per template-commit)"$'\n'
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

if [ -n "${RECEPT:-}" ]; then
  controleer_recept "$ROOT" "$RECEPT"
  bouw_recepten "$ROOT"
fi

nieuwe_run "$ROOT" "$MIGRATIE"

# Uitsluitlijst (config.env): repo's die nooit een service zijn.
# shellcheck disable=SC2086
if [ -n "${UITSLUITLIJST:-}" ]; then uitsluiten+=("$(repo_regex $UITSLUITLIJST)"); fi

# Per service hooguit één open migratie-PR (docs/adr/0001): services met een open MR
# van een andere migratie doen nu niet mee en krijgen "Wacht op vorige migratie".
echo ">> open MR's van andere migraties opvragen"
mrs="$(open_migratie_mrs)" || { echo "kon de open MR's niet opvragen bij GitLab" >&2; exit 2; }
wachtend=()
while IFS=$'\t' read -r project andere; do
  [ -n "$project" ] && [ "$andere" != "$MIGRATIE" ] || continue
  printf '%s\tWacht op vorige migratie\topen MR van migratie %s\n' "$project" "$andere" >> "$RESULTATEN"
  wachtend+=("$project")
done <<< "$mrs"
if [ ${#wachtend[@]} -gt 0 ]; then
  uitsluiten+=("$(printf '^(%s)$' "$(printf '%s\n' "${wachtend[@]}" | sort -u | sed 's/[][\.*^$+?(){}|]/\\&/g' | paste -sd'|' -)")")
fi
if [ ${#uitsluiten[@]} -gt 0 ]; then
  args+=(--repo-exclude "$(printf '%s\n' "${uitsluiten[@]}" | paste -sd'|' -)")
fi

status=0
multi-gitter "${args[@]}" ${extra[@]+"${extra[@]}"} || status=$?
"$ROOT/lib/samenvatting.sh" "$RESULTATEN"
exit "$status"
