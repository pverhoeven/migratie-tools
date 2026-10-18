#!/usr/bin/env bash
# Draait een migratie in een bestaande lokale clone, bv. het project dat je al in
# IntelliJ open hebt. Maakt de branch van de migratie (standaard migratie/<naam>) vanaf
# de huidige commit; er wordt
# nooit gepusht. Conflicten los je op in je IDE (Git > Resolve Conflicts) en daarna:
# --verder.
#
# Gebruik: ./in-repo.sh [--zonder-verify] [--niet-wachten] <migratie> [<repo>]
#          ./in-repo.sh --verder [--zonder-verify] [--niet-wachten] <migratie> [<repo>]
#
# Bij handwerk (conflict, rode build) wacht het in de terminal: los het op, druk op
# Enter en de migratie gaat verder. Met --niet-wachten (of zonder terminal) stopt het en
# ga je later verder met --verder.
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
wachten=1
while [ $# -gt 0 ]; do
  case "$1" in
    --zonder-verify) ZONDER_VERIFY=1 ;;
    --verder) verder=1 ;;
    --niet-wachten) wachten=0 ;;
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
branch="$BRANCH"
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
resultaat="$(mktemp)"
trap 'rm -f "$resultaat"' EXIT
draai() {
  status=0
  RESULTATEN="$resultaat" REPOSITORY="$(basename "$repo")" BASIS="$basis" "$ROOT/repo-runner.sh" || status=$?
}
draai
while [ "$status" -eq 20 ] && [ "$wachten" -eq 1 ]; do
  # De reden zonder de lijst met bestanden; die toont wacht_op_handwerk zelf.
  wacht_op_handwerk "$(tail -1 "$resultaat" | cut -f3 | sed 's/): .*/)/')" "$0 --verder $1${2:+ $2}" || break
  draai
done

case "$status" in
  0)
    if [ -z "$(git rev-list "$basis..HEAD")" ]; then
      echo "--- geen commits op $branch, niets te pushen; de branch weghalen:"
      echo "    git switch - && git branch -D $branch"
      exit 0
    fi
    echo "--- commits op $branch:"
    git --no-pager log --oneline "$basis..HEAD"
    echo "--- push en open de MR zelf (labels: migratie, $MIGRATIE):"
    echo "    git push -u origin $branch"
    echo "--- titel: $PR_TITEL"
    echo "--- beschrijving:"
    pr_beschrijving "$ROOT" | sed 's/^/    /' ;;
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
