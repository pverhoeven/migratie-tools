#!/usr/bin/env bash
# Draait een migratie in een bestaande lokale clone, bv. het project dat je al in
# IntelliJ open hebt. Maakt de branch migratie/<naam> vanaf de huidige commit; er wordt
# nooit gepusht. Conflicten los je op in je IDE (Git > Resolve Conflicts) en daarna:
# --verder.
#
# Gebruik: ./in-repo.sh [--zonder-verify] <migratie> [<repo>]
#          ./in-repo.sh --verder [--zonder-verify] <migratie> [<repo>]
#   migratie  naam (migraties/<naam>.env) of pad naar een migratiebestand
#   repo      pad naar de repo (standaard: de huidige map)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/migratie.sh"
. "$ROOT/lib/recepten.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi

ZONDER_VERIFY=0
verder=0
while [ $# -gt 0 ]; do
  case "$1" in
    --zonder-verify) ZONDER_VERIFY=1 ;;
    --verder) verder=1 ;;
    *) break ;;
  esac
  shift
done
export ZONDER_VERIFY

if [ $# -lt 1 ]; then
  echo "gebruik: $0 [--verder] [--zonder-verify] <migratie> [<repo>]" >&2
  exit 2
fi
laad_migratie "$1"
repo="$(git -C "${2:-.}" rev-parse --show-toplevel)" || { echo "${2:-.} is geen git-repo" >&2; exit 2; }
branch="migratie/$MIGRATIE"
cd "$repo"
echo "=== $MIGRATIE in $repo ==="

if [ "$verder" -eq 1 ]; then
  hervat "$repo" || exit 20
else
  start_branch "$branch"
fi

if [ -n "${RECEPT:-}" ]; then
  controleer_recept "$ROOT" "$RECEPT"
  bouw_recepten "$ROOT"
fi

basis="$(git config "branch.$branch.migratiebasis" || git rev-parse HEAD)"
status=0
REPOSITORY="$(basename "$repo")" BASIS="$basis" "$ROOT/repo-runner.sh" || status=$?

case "$status" in
  0)
    echo "--- commits op $branch:"
    git log --oneline "$basis..HEAD"
    echo "--- push en open de MR zelf (labels: migratie, $MIGRATIE):"
    echo "    git push -u origin $branch" ;;
  20)
    if [ -n "$(git ls-files -u)" ]; then
      echo "--- los de conflicten op (bv. in IntelliJ: Git > Resolve Conflicts) en draai daarna:"
    else
      echo "--- los het probleem hierboven op en draai daarna:"
    fi
    echo "    $0 --verder $1${2:+ $2}"
    echo "--- of begin opnieuw: git switch - && git branch -D $branch" ;;
esac
exit "$status"
