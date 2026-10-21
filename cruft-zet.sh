#!/usr/bin/env bash
# Zet een variabele van het template om in één template-service, bv. een flag als
# liquibase=true, en voert het effect daarvan door. Het template blijft op dezelfde
# commit; alleen de context verandert: de service krijgt het verschil tussen het
# template met de oude en met de nieuwe waarde, met een 3-way-merge (zoals de cruft
# update). Werkt in een bestaande clone en pusht nooit.
#
# Gebruik: ./cruft-zet.sh [--zonder-verify] [--niet-wachten] <variabele>=<waarde> [<repo>]
#          ./cruft-zet.sh --verder [--zonder-verify] [--niet-wachten] [<repo>]
#
# Bij handwerk (conflict, rode build) wacht het in de terminal tot je het hebt opgelost
# en op Enter drukt; met --niet-wachten (of zonder terminal) stopt het.
#   waarde  JSON (true, false, 3) of anders tekst
#
# Alleen variabelen die veilig om te zetten zijn: geen private (_...), geen afgeleide
# (standaardwaarde met {{ }}) en geen variabelen waar andere van afgeleid zijn.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/migratie.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi
vereist git jq

zonder_verify=0
verder=0
wachten=1
while [ $# -gt 0 ]; do
  case "$1" in
    --zonder-verify) zonder_verify=1 ;;
    --verder) verder=1 ;;
    --niet-wachten) wachten=0 ;;
    *) break ;;
  esac
  shift
done

gebruik() {
  echo "gebruik: $0 [--zonder-verify] <variabele>=<waarde> [<repo>]" >&2
  echo "         $0 --verder [--zonder-verify] [<repo>]" >&2
  exit 2
}

# Na de omzetting (of na --verder): build en tests, en de hint om te pushen.
afronden() {
  local basis
  if [ "$zonder_verify" -eq 0 ] && [ -f pom.xml ]; then
    echo ">> controle: verify"
    while ! "$ROOT/controles/verify.sh"; do
      if [ "$wachten" -eq 1 ] && wacht_op_handwerk "de build is rood (build of tests, zie hierboven)" "$0 --verder"; then
        echo ">> controle: verify"
        continue
      fi
      echo "--- de build is rood; repareer het en draai daarna: $0 --verder" >&2
      exit 20
    done
  fi
  basis="$(git config "branch.$branch.migratiebasis" || git rev-parse HEAD~1)"
  echo "--- commits op $branch:"
  git --no-pager log --oneline "$basis..HEAD"
  echo "--- push en open de MR zelf (labels: migratie, cruft-zet):"
  echo "    git push -u origin $branch"
  echo "--- titel: $(git log -1 --format=%s "$(git rev-list --max-count=1 --grep='^feat(cruft): ' HEAD)")"
  echo "--- beschrijving: template-variabele omgezet met cruft-zet.sh (migratie-tools $(tools_versie "$ROOT"))."
}

if [ "$verder" -eq 1 ]; then
  [ $# -le 1 ] || gebruik
  cd "$(git -C "${1:-.}" rev-parse --show-toplevel)"
  branch="$(git branch --show-current)"
  case "$branch" in
    "$(branch_prefix)"cruft-zet-*) MIGRATIE="${branch#"$(branch_prefix)"}"; BRANCH="$branch" ;;
    *) echo "je staat niet op een cruft-zet-branch ($(branch_prefix)cruft-zet-...)" >&2; exit 2 ;;
  esac
  hervat "$PWD" || exit 20
  afronden
  exit 0
fi

[ $# -ge 1 ] && [ $# -le 2 ] && [[ "$1" == *=* ]] || gebruik
naam="${1%%=*}"; waarde="${1#*=}"
cd "$(git -C "${2:-.}" rev-parse --show-toplevel)" || { echo "${2:-.} is geen git-repo" >&2; exit 2; }

# Eerst nagaan of de variabele om te zetten is (en of er iets te doen is), pas daarna
# een branch maken.
uitvoer="$("$ROOT/transformaties/cruft-zet.sh" --controleer "$1" 2>&1)" || { echo "$uitvoer" >&2; exit 2; }
if [ -n "$uitvoer" ]; then echo "$uitvoer"; exit 0; fi   # staat al goed

MIGRATIE="cruft-zet-$naam"
branch="$(branch_prefix)$MIGRATIE"
BRANCH="$branch"
start_branch "$branch"

status=0
"$ROOT/transformaties/cruft-zet.sh" "$1" || status=$?
case "$status" in
  0) afronden ;;
  1)
    if [ "$wachten" -eq 1 ] && wacht_op_handwerk "conflict bij het omzetten van $naam" "$0 --verder"; then
      afronden
      exit 0
    fi
    echo "--- los de conflicten op (bv. in IntelliJ: Git > Resolve Conflicts) en draai daarna: $0 --verder" >&2
    exit 20 ;;
  *) exit "$status" ;;
esac
