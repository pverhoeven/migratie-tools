#!/usr/bin/env bash
# Transformatie: een template-variabele omzetten in een template-service (cwd = de
# service), bv. liquibase=true, en het effect daarvan doorvoeren (docs/adr/0005). Het
# template blijft op de commit uit .cruft.json; de service krijgt het verschil tussen het
# template met de oude en met de nieuwe waarde, 3-way gemerged. Commit als
# "feat(cruft): <variabele> aangezet" (of uitgezet). Staat de variabele al goed, dan
# gebeurt er niets.
#
# Gebruik: transformaties/cruft-zet.sh [--controleer] <variabele>=<waarde>
#   --controleer  alleen nagaan of de variabele om te zetten is; niets wijzigen
#   waarde        JSON (true, false, 3) of anders tekst
# Exit: 0 = klaar of niets te doen, 1 = conflict (handwerk), 2 = kan niet omzetten.
# Alleen variabelen die veilig om te zetten zijn: geen private (_...), geen afgeleide
# (standaardwaarde met {{ }}) en geen variabelen waar andere van afgeleid zijn.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/template.sh"
vereist git jq

controleer=0
if [ "${1:-}" = "--controleer" ]; then controleer=1; shift; fi
[[ "${1:-}" == *=* ]] || { reden "gebruik <variabele>=<waarde>, niet '${1:-}'"; exit 2; }
naam="${1%%=*}"; waarde="${1#*=}"
[ -f .cruft.json ] || { reden "geen template-service: .cruft.json ontbreekt"; exit 2; }

# Waarde als JSON als dat kan (true, false, 3), anders als tekst.
if waarde_json="$(jq -c . <<< "$waarde" 2>/dev/null)" && [ -n "$waarde_json" ]; then :; else
  waarde_json="$(jq -cn --arg v "$waarde" '$v')"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone --quiet "$(jq -r .template .cruft.json)" "$tmp/template"
commit="$(jq -r .commit .cruft.json)"
git -C "$tmp/template" cat-file -e "$commit^{commit}" 2>/dev/null \
  || { reden "de template-commit ${commit:0:7} uit .cruft.json bestaat niet (meer) in het template"; exit 2; }
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
[ -z "$fout" ] || { reden "kan $naam niet omzetten: $fout"; exit 2; }

huidig="$(jq -c --arg k "$naam" '.context.cookiecutter[$k]' .cruft.json)"
if [ "$huidig" = "$waarde_json" ]; then
  echo "$naam staat al op $waarde_json; niets te doen"
  exit 0
fi
[ "$controleer" -eq 0 ] || exit 0

# Het template op dezelfde commit, met de oude en met de nieuwe waarde.
jq --arg k "$naam" --argjson v "$waarde_json" '.context.cookiecutter[$k] = $v' .cruft.json > "$tmp/cruft-nieuw.json"
echo ">> $naam: $huidig -> $waarde_json (template ${commit:0:7})"
render_template .cruft.json "$tmp/template" "$commit" "$tmp/oud" "$tmp/oud.json"
render_template "$tmp/cruft-nieuw.json" "$tmp/template" "$commit" "$tmp/nieuw" "$tmp/nieuw.json"
merge_renders "$tmp/oud" "$tmp/nieuw" "template $naam=$huidig" "template $naam=$waarde_json"
jq --slurpfile ctx "$tmp/nieuw.json" '.context = $ctx[0]' .cruft.json > "$tmp/cruft.json"
cp "$tmp/cruft.json" .cruft.json

case "$waarde_json" in
  true) bericht="feat(cruft): $naam aangezet" ;;
  false) bericht="feat(cruft): $naam uitgezet" ;;
  *) bericht="feat(cruft): $naam = $waarde_json" ;;
esac
if [ ${#MERGE_CONFLICTEN[@]} -gt 0 ]; then
  # Zoals bij de cruft update: --verder commit de opgeloste stap met deze boodschap.
  echo "$bericht" > "$(git rev-parse --git-dir)/MIGRATIE_MSG"
  reden "conflict bij het omzetten van $naam: $(printf '%s, ' "${MERGE_CONFLICTEN[@]}" | sed 's/, $//')"
  exit 1
fi
commit_alles "$bericht"
