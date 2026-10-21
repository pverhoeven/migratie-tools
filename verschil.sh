#!/usr/bin/env bash
# Laat zien waar een template-service afwijkt van het template: het template op de commit
# uit .cruft.json, met de context uit .cruft.json, vergeleken met de bestanden van de
# service. Zo vind je template-wijzigingen die de service ooit gemist heeft (bv. een
# conflict dat naar de kant van de service is opgelost, of een bestand dat de service
# heeft hernoemd), naast de aanpassingen die de service bewust heeft gedaan. Bestanden
# die alleen in de service staan, horen niet bij het template en blijven buiten beeld.
# Wijzigt niets.
#
# Gebruik: ./verschil.sh [--lijst] [--intellij] [--bewaar <map>] [<repo> [<pad>...]]
#   --lijst          alleen de lijst met bestanden, zonder de diff
#   --intellij       opent de vergelijking in IntelliJ (idea diff): links de service,
#                    rechts het template, zodat je stukken direct kunt overnemen. Het
#                    template komt in work/verschil/<service> (of de map van --bewaar).
#                    Het commando van IntelliJ: 'idea' in het PATH, of IDEA_CMD.
#   --bewaar <map>   zet het gegenereerde template in <map> (buiten de repo), om het zelf
#                    met de service te vergelijken
#   <pad>            alleen deze bestanden of mappen, bv. src/main/resources
# In de diff is - de service en + het template: een +regel staat wel in het template
# en niet in de service.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/template.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi
vereist git jq

lijst=0
intellij=0
bewaar=""
while [ $# -gt 0 ]; do
  case "$1" in
    --lijst) lijst=1 ;;
    --intellij) intellij=1 ;;
    --bewaar)
      [ $# -ge 2 ] || { echo "--bewaar heeft een map nodig" >&2; exit 2; }
      # Een relatief pad geldt vanaf de map waar je het script start, niet vanaf de repo.
      bewaar="$(cd "$(dirname "$2")" 2>/dev/null && pwd)/$(basename "$2")" \
        || { echo "de map boven $2 bestaat niet" >&2; exit 2; }
      shift ;;
    -*) echo "gebruik: $0 [--lijst] [--intellij] [--bewaar <map>] [<repo> [<pad>...]]" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done

cd "$(git -C "${1:-.}" rev-parse --show-toplevel)" || { echo "${1:-.} is geen git-repo" >&2; exit 2; }
[ $# -eq 0 ] || shift
paden=("$@")
[ -f .cruft.json ] || { echo "$PWD is geen template-service (geen .cruft.json)" >&2; exit 2; }
if [ -n "$bewaar" ]; then
  case "$bewaar/" in
    "$PWD"/*) echo "zet --bewaar buiten de repo, anders komt het template in de service terecht" >&2; exit 2 ;;
  esac
  [ ! -e "$bewaar" ] || [ -z "$(ls -A "$bewaar")" ] || { echo "$bewaar bestaat al en is niet leeg" >&2; exit 2; }
elif [ "$intellij" -eq 1 ]; then
  bewaar="$ROOT/work/verschil/$(basename "$PWD")"   # van ons, dus opnieuw te gebruiken
  rm -rf "$bewaar"
fi
if [ "$intellij" -eq 1 ]; then
  idea=()
  if [ -n "${IDEA_CMD:-}" ]; then idea=("$IDEA_CMD")
  elif type -P idea >/dev/null; then idea=(idea)
  elif type -P idea.cmd >/dev/null; then idea=(idea.cmd)        # Windows, via Toolbox
  elif type -P idea64.exe >/dev/null; then idea=(idea64.exe)
  else
    for a in "/Applications/IntelliJ IDEA.app" "/Applications/IntelliJ IDEA Ultimate.app" "/Applications/IntelliJ IDEA CE.app"; do
      [ -x "$a/Contents/MacOS/idea" ] && { idea=("$a/Contents/MacOS/idea"); break; }
    done
  fi
  [ ${#idea[@]} -gt 0 ] || { echo "IntelliJ niet gevonden: zet IDEA_CMD in config.env (het pad naar idea, idea64.exe of idea.cmd)" >&2; exit 2; }
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

commit="$(jq -r .commit .cruft.json)"
git clone --quiet "$(template_url .cruft.json)" "$tmp/repo"
git -C "$tmp/repo" cat-file -e "$commit^{commit}" 2>/dev/null \
  || { echo "de template-commit ${commit:0:7} uit .cruft.json bestaat niet (meer) in het template" >&2; exit 1; }
render_template .cruft.json "$tmp/repo" "$commit" "$tmp/template" "$tmp/context.json"

# Valt <pad> onder een van de opgegeven paden (of zijn er geen opgegeven)?
gevraagd() {  # <pad>
  local p
  [ ${#paden[@]} -gt 0 ] || return 0
  for p in "${paden[@]}"; do
    p="${p%/}"
    [ "$1" = "$p" ] || [[ "$1" == "$p"/* ]] && return 0
  done
  return 1
}

# Vergelijkt zonder verschil in regeleinden (core.autocrlf op Windows).
zelfde() {  # <service> <template>
  git diff --no-index --quiet --ignore-cr-at-eol -- "$1" "$2" >/dev/null 2>&1
}

ontbreekt=()
anders=()
while IFS= read -r -d '' f; do
  f="${f#./}"
  [ "$f" != .cruft.json ] && gevraagd "$f" || continue
  if [ ! -e "$f" ]; then
    ontbreekt+=("$f")
  elif ! zelfde "$f" "$tmp/template/$f"; then
    anders+=("$f")
  fi
done < <(cd "$tmp/template" && find . -type f -print0 | sort -z)

echo "template $(basename "$(template_url .cruft.json)" .git) op ${commit:0:7} (de stand in .cruft.json), met de context uit .cruft.json"
if [ ${#ontbreekt[@]} -eq 0 ] && [ ${#anders[@]} -eq 0 ]; then
  echo "de service is gelijk aan het template"
else
  if [ ${#ontbreekt[@]} -gt 0 ]; then
    echo "Ontbreekt in de service (${#ontbreekt[@]}):"
    printf '  %s\n' "${ontbreekt[@]}"
  fi
  if [ ${#anders[@]} -gt 0 ]; then
    echo "Anders dan het template (${#anders[@]}):"
    for f in "${anders[@]}"; do
      printf '  %s  %s\n' "$f" "$(git diff --no-index --ignore-cr-at-eol --numstat -- "$f" "$tmp/template/$f" | awk '{printf "(+%s -%s)", $1, $2}')"
    done
  fi
fi

if [ -n "$bewaar" ]; then
  mkdir -p "$bewaar"
  cp -R "$tmp/template/." "$bewaar/"
  echo
  echo "het gegenereerde template staat in $bewaar"
fi

[ $((${#ontbreekt[@]} + ${#anders[@]})) -gt 0 ] || exit 0

# In IntelliJ: één afwijkend bestand als bestandsdiff, anders de mappen (bij <pad> alleen
# die map). De servicebestanden links zijn de echte, dus wat je overneemt staat meteen in
# de service.
if [ "$intellij" -eq 1 ]; then
  if [ ${#anders[@]} -eq 1 ] && [ ${#ontbreekt[@]} -eq 0 ]; then
    links="$PWD/${anders[0]}"; rechts="$bewaar/${anders[0]}"
  elif [ ${#paden[@]} -eq 1 ] && [ -d "$bewaar/${paden[0]%/}" ]; then
    links="$PWD/${paden[0]%/}"; rechts="$bewaar/${paden[0]%/}"
  else
    links="$PWD"; rechts="$bewaar"
  fi
  echo "openen in IntelliJ: links de service, rechts het template"
  [ -f "$links" ] || echo "tip: zet in de vergelijking 'bestanden alleen links' uit; die horen niet bij het template"
  "${idea[@]}" diff "$links" "$rechts" >/dev/null 2>&1 &
  exit 0
fi

[ "$lijst" -eq 0 ] || exit 0

# De diff: - is de service, + het template. Vanuit de tijdelijke map met relatieve paden
# (service/<pad> en template/<pad>), zodat de koppen leesbaar zijn, ook in Git Bash.
for f in ${anders[@]+"${anders[@]}"}; do
  mkdir -p "$tmp/service/$(dirname "$f")"; cp "$f" "$tmp/service/$f"
done
kleur=never
[ -t 1 ] && kleur=always
toon_diff() {
  local f
  cd "$tmp"
  for f in ${ontbreekt[@]+"${ontbreekt[@]}"}; do
    git diff --no-index --no-prefix --color="$kleur" -- /dev/null "template/$f" || true
  done
  for f in ${anders[@]+"${anders[@]}"}; do
    git diff --no-index --no-prefix --ignore-cr-at-eol --color="$kleur" -- "service/$f" "template/$f" || true
  done
}
echo
if [ -t 1 ]; then
  toon_diff | ${PAGER:-less -R}
else
  toon_diff
fi
