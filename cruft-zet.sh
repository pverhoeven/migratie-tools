#!/usr/bin/env bash
# Zet een variabele van het template om in één template-service, bv. een flag als
# liquibase=true, en voert het effect daarvan door. Het template blijft op dezelfde
# commit; alleen de context verandert: de service krijgt het verschil tussen het
# template met de oude en met de nieuwe waarde, met een 3-way-merge (zoals de cruft
# update). Werkt in een bestaande clone en pusht nooit.
#
# Gebruik: ./cruft-zet.sh [--zonder-verify] <variabele>=<waarde> [<repo>]
#          ./cruft-zet.sh --verder [--zonder-verify] [<repo>]
#   waarde  JSON (true, false, 3) of anders tekst
#
# Alleen variabelen die veilig om te zetten zijn: geen private (_...), geen afgeleide
# (standaardwaarde met {{ }}) en geen variabelen waar andere van afgeleid zijn.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/migratie.sh"
. "$ROOT/lib/template.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi
vereist git jq

zonder_verify=0
verder=0
while [ $# -gt 0 ]; do
  case "$1" in
    --zonder-verify) zonder_verify=1 ;;
    --verder) verder=1 ;;
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
    if ! "$ROOT/controles/verify.sh"; then
      echo "--- de build is rood; repareer het en draai daarna: $0 --verder" >&2
      exit 20
    fi
  fi
  basis="$(git config "branch.$branch.migratiebasis" || git rev-parse HEAD~1)"
  echo "--- commits op $branch:"
  git log --oneline "$basis..HEAD"
  echo "--- push en open de MR zelf (labels: migratie, cruft-zet):"
  echo "    git push -u origin $branch"
}

if [ "$verder" -eq 1 ]; then
  [ $# -le 1 ] || gebruik
  cd "$(git -C "${1:-.}" rev-parse --show-toplevel)"
  branch="$(git branch --show-current)"
  case "$branch" in
    migratie/cruft-zet-*) MIGRATIE="${branch#migratie/}" ;;
    *) echo "je staat niet op een cruft-zet-branch (migratie/cruft-zet-...)" >&2; exit 2 ;;
  esac
  hervat "$PWD" || exit 20
  afronden
  exit 0
fi

[ $# -ge 1 ] && [ $# -le 2 ] && [[ "$1" == *=* ]] || gebruik
naam="${1%%=*}"; waarde="${1#*=}"
cd "$(git -C "${2:-.}" rev-parse --show-toplevel)" || { echo "${2:-.} is geen git-repo" >&2; exit 2; }
[ -f .cruft.json ] || { echo "geen template-service: .cruft.json ontbreekt" >&2; exit 2; }

# Waarde als JSON als dat kan (true, false, 3), anders als tekst.
if waarde_json="$(jq -c . <<< "$waarde" 2>/dev/null)" && [ -n "$waarde_json" ]; then :; else
  waarde_json="$(jq -cn --arg v "$waarde" '$v')"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone --quiet "$(jq -r .template .cruft.json)" "$tmp/template"
commit="$(jq -r .commit .cruft.json)"
git -C "$tmp/template" cat-file -e "$commit^{commit}" 2>/dev/null \
  || { echo "de template-commit ${commit:0:7} uit .cruft.json bestaat niet (meer) in het template" >&2; exit 2; }
map="$(jq -r '.directory // ""' .cruft.json)"
git -C "$tmp/template" show "$commit:${map:+$map/}cookiecutter.json" > "$tmp/cookiecutter.json"

# Is de variabele veilig om om te zetten?
fout="$(jq -r --arg k "$naam" --argjson v "$waarde_json" '
  if ($k | startswith("_")) then "\($k) is een private variabele"
  elif has($k) | not then "\($k) bestaat niet in het template (variabelen: \(keys | map(select(startswith("_") | not)) | join(", ")))"
  elif (.[$k] | type) == "string" and (.[$k] | contains("{{")) then "\($k) is afgeleid van andere variabelen"
  elif [to_entries[] | select(.key != $k) | .value | tostring | test("cookiecutter\\.\($k)\\b")] | any
    then "andere variabelen zijn afgeleid van \($k)"
  elif (.[$k] | type) == "boolean" and ($v | type) != "boolean" then "\($k) is een boolean: gebruik true of false"
  elif (.[$k] | type) == "array" and (.[$k] | index([$v]) | not) then "\($v) is geen keuze voor \($k) (keuzes: \(.[$k] | join(", ")))"
  else empty end' "$tmp/cookiecutter.json")"
[ -z "$fout" ] || { echo "kan $naam niet omzetten: $fout" >&2; exit 2; }

if [ "$(jq -c --arg k "$naam" '.context.cookiecutter[$k]' .cruft.json)" = "$waarde_json" ]; then
  echo "$naam staat al op $waarde_json; niets te doen"
  exit 0
fi

MIGRATIE="cruft-zet-$naam"
branch="migratie/$MIGRATIE"
start_branch "$branch"

# Het template op dezelfde commit, met de oude en met de nieuwe waarde.
jq --arg k "$naam" --argjson v "$waarde_json" '.context.cookiecutter[$k] = $v' .cruft.json > "$tmp/cruft-nieuw.json"
echo ">> $naam: $(jq -c --arg k "$naam" '.context.cookiecutter[$k]' .cruft.json) -> $waarde_json (template ${commit:0:7})"
render_template .cruft.json "$tmp/template" "$commit" "$tmp/oud" "$tmp/oud.json"
render_template "$tmp/cruft-nieuw.json" "$tmp/template" "$commit" "$tmp/nieuw" "$tmp/nieuw.json"
merge_renders "$tmp/oud" "$tmp/nieuw" "template $naam=$(jq -c --arg k "$naam" '.context.cookiecutter[$k]' .cruft.json)" "template $naam=$waarde_json"
jq --slurpfile ctx "$tmp/nieuw.json" '.context = $ctx[0]' .cruft.json > "$tmp/cruft.json"
cp "$tmp/cruft.json" .cruft.json

case "$waarde_json" in
  true) bericht="feat(cruft): $naam aangezet" ;;
  false) bericht="feat(cruft): $naam uitgezet" ;;
  *) bericht="feat(cruft): $naam = $waarde_json" ;;
esac
if [ ${#MERGE_CONFLICTEN[@]} -gt 0 ]; then
  echo "$bericht" > "$(git rev-parse --git-dir)/MIGRATIE_MSG"
  echo "--- conflicten:" >&2
  printf '    %s\n' "${MERGE_CONFLICTEN[@]}" >&2
  echo "--- los ze op (bv. in IntelliJ: Git > Resolve Conflicts) en draai daarna: $0 --verder" >&2
  exit 20
fi
commit_alles "$bericht"
afronden
