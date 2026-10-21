#!/usr/bin/env bash
# Een migratie uitproberen: kloont elke service vers naar ./work/<naam>, maakt daar de
# branch van de migratie aan en draait de migratie. Werkt zonder GitLab (lokale paden of
# git-URL's) en pusht nooit: work/ is een zandbak die bij elke run opnieuw wordt
# gekloond. Bekijk het resultaat in work/<naam> of in runs/<migratie>-<tijd>/debug/.
#
# Echt uitrollen doe je met run.sh (MR's voor de groep) of in-repo.sh (in je eigen clone,
# ook voor handwerk).
#
# Gebruik: ./uitproberen.sh [--zonder-verify] <migratie> <repo> [<repo> ...]
#   migratie  naam (migraties/<naam>.env) of pad naar een migratiebestand
#   repo      pad naar een lokale repo of een git-URL (een lokale repo wordt gekloond,
#             niet-gecommitte wijzigingen worden dus niet meegenomen)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/migratie.sh"
. "$ROOT/lib/recepten.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi

ZONDER_VERIFY=0
if [ "${1:-}" = "--zonder-verify" ]; then ZONDER_VERIFY=1; shift; fi
export ZONDER_VERIFY

if [ $# -lt 2 ]; then
  echo "gebruik: $0 [--zonder-verify] <migratie> <repo> [<repo> ...]" >&2
  exit 2
fi
laad_migratie "$1"; shift

if [ -n "${RECEPT:-}" ]; then
  controleer_recept "$ROOT" "$RECEPT"
  bouw_recepten "$ROOT"
fi

WORK_DIR="${WORK_DIR:-$ROOT/work}"
mkdir -p "$WORK_DIR"
nieuwe_run "$ROOT" "$MIGRATIE"

for repo in "$@"; do
  if [ -d "$repo" ]; then repo="$(cd "$repo" && pwd)"; fi  # ook . of ../service
  name="$(basename "${repo%/}")"; name="${name%.git}"
  dest="$WORK_DIR/$name"
  echo
  echo "=== $name ==="
  # shellcheck disable=SC2086
  if [ -n "${UITSLUITLIJST:-}" ] && [[ "$name" =~ $(repo_regex $UITSLUITLIJST) ]]; then
    echo "staat op de uitsluitlijst, geen service"
    continue
  fi
  rm -rf "$dest"
  if ! git clone --quiet "$repo" "$dest"; then
    printf '%s\tHandwerk nodig\tclonen mislukt\n' "$name" >> "$RESULTATEN"
    continue
  fi
  git -C "$dest" checkout -q -B "$BRANCH"

  status=0
  (cd "$dest" && REPOSITORY="$name" "$ROOT/repo-runner.sh") || status=$?
  if [ "$status" -eq 0 ]; then
    echo "--- commits op $BRANCH in $dest:"
    git --no-pager -C "$dest" log --oneline origin/HEAD..HEAD
  elif [ "$status" -ne 10 ]; then  # 10: niet van toepassing, niets af te maken
    echo "--- de stand waarin de migratie stopte staat in $dest (git status);"
    echo "    afmaken doe je in je eigen clone met in-repo.sh"
  fi
done

"$ROOT/lib/samenvatting.sh" "$RESULTATEN"
