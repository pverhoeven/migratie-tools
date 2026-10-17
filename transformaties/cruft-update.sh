#!/usr/bin/env bash
# Transformatie cruft update: een template-service bijwerken naar de nieuwste commit
# van het template. Doet wat `cruft update` doet, maar commit voor commit en met echte
# git-conflicten; het commando `cruft update` zelf gebruiken we bewust niet (docs/adr/0004).
# Uitgangspunt is de commit in .cruft.json; het doel is de standaardbranch van het
# template. Per commit op de hoofdlijn van het template:
#   - de vorige en de volgende stand genereren met de context uit .cruft.json
#   - elk bestand 3-way mergen (basis = vorige stand, ours = service, theirs = volgende)
#   - .cruft.json bijwerken en committen als conventional commit: het type van de
#     template-commit met scope cruft, bv. "fix(cruft): logging op warn (777021d)"
# Bij het eerste conflict stopt de update, met diff3-conflictmarkers in de bestanden.
# De conflicten staan ook als echte git-conflicten in de index (basis, service,
# template), zodat een IDE (bv. IntelliJ: Git > Resolve Conflicts) ze 3-way kan mergen.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"

vereist git jq

if git grep -qE '^(<<<<<<<|>>>>>>>)( |$)' -- . 2>/dev/null; then
  reden "er staan nog conflictmarkers in de service; los die eerst op"
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --quiet "$(jq -r .template .cruft.json)" "$tmp/template"
tpl() { git -C "$tmp/template" "$@"; }

huidig="$(jq -r .commit .cruft.json)"
doel="$(tpl rev-parse HEAD)"
tpl cat-file -e "$huidig^{commit}" 2>/dev/null \
  || { reden "de template-commit ${huidig:0:7} uit .cruft.json bestaat niet (meer) in het template; is de historie van het template herschreven?"; exit 1; }

if [ "$huidig" = "$doel" ] || tpl merge-base --is-ancestor "$doel" "$huidig"; then
  echo "service is al bij met het template ($(tpl rev-parse --short "$doel"))"
  exit 0
fi

# De commits op de hoofdlijn van het template sinds de huidige stand, oudste eerst.
stappen=()
while IFS= read -r c; do stappen+=("$c"); done < <(tpl rev-list --reverse --first-parent "$huidig..$doel")
if ! tpl merge-base --is-ancestor "$huidig" "$doel"; then
  stappen=("$doel")  # huidige stand ligt niet op de hoofdlijn: in één keer
fi
echo "${#stappen[@]} template-commit(s) achter, naar $(tpl rev-parse --short "$doel")"

# Zet een conflict in de index zoals git dat bij een merge doet: stage 1 = basis,
# 2 = service (ours), 3 = template (theirs). Een lege versie laat die stage weg.
markeer_conflict() {  # <pad> <basis> <service> <template>
  local pad="$1" mode=100644 info i=1 v
  [ -x "$pad" ] && mode=100755
  info="0 0000000000000000000000000000000000000000"$'\t'"$pad"$'\n'
  for v in "$2" "$3" "$4"; do
    [ -n "$v" ] && info+="$mode $(git hash-object -w "$v") $i"$'\t'"$pad"$'\n'
    i=$((i + 1))
  done
  printf '%s' "$info" | git update-index --index-info
}

# Commit-boodschap voor een template-commit: neemt het type over als de template-commit
# een conventional commit is (feat: ..., fix(x)!: ...), anders chore.
bericht_voor() {  # <commit>
  local onderwerp patroon='^([a-z]+)(\([^)]*\))?(!?): (.*)$'
  onderwerp="$(tpl log -1 --format=%s "$1")"
  if [[ "$onderwerp" =~ $patroon ]]; then
    printf '%s(cruft)%s: %s (%s)' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" "$(tpl rev-parse --short "$1")"
  else
    printf 'chore(cruft): %s (%s)' "$onderwerp" "$(tpl rev-parse --short "$1")"
  fi
}

# Bij een conflict bewaren we de commit-boodschap (zoals git dat met MERGE_MSG doet),
# zodat --verder de opgeloste stap met dezelfde boodschap commit.
MSG_BESTAND="$(git rev-parse --git-dir)/MIGRATIE_MSG"
rm -f "$MSG_BESTAND"

render() {  # <commit> <uitvoermap> <context.json>
  rm -rf "$2"
  cruft_python "$ROOT/lib/render-template.py" .cruft.json "$tmp/template" "$1" "$2" "$3" >/dev/null
}

: > "$tmp/leeg"
vorige="$huidig"
for stap in "${stappen[@]}"; do
  van="$(tpl rev-parse --short "$vorige")"; naar="$(tpl rev-parse --short "$stap")"
  onderwerp="$(tpl log -1 --format=%s "$stap")"
  echo "-- template $van -> $naar: $onderwerp"
  render "$vorige" "$tmp/oud" "$tmp/oud.json"
  render "$stap" "$tmp/nieuw" "$tmp/nieuw.json"

  conflicten=()
  while IFS= read -r -d '' f; do
    f="${f#./}"; o="$tmp/oud/$f"; n="$tmp/nieuw/$f"
    if [ -f "$o" ] && [ -f "$n" ]; then
      cmp -s "$o" "$n" && continue                  # niet gewijzigd in het template
      [ -e "$f" ] || continue                       # door de service verwijderd: zo laten
      if cmp -s "$f" "$o"; then cp "$n" "$f"; continue; fi
      cmp -s "$f" "$n" && continue
      cp "$f" "$tmp/service"
      if ! git merge-file --diff3 -L service -L "template $van" -L "template $naar" "$f" "$o" "$n"; then
        conflicten+=("$f"); markeer_conflict "$f" "$o" "$tmp/service" "$n"
      fi
    elif [ -f "$n" ]; then                          # nieuw in het template
      if [ ! -e "$f" ]; then
        mkdir -p "$(dirname "$f")"; cp "$n" "$f"
      elif ! cmp -s "$f" "$n"; then
        cp "$f" "$tmp/service"
        if ! git merge-file --diff3 -L service -L "(nieuw)" -L "template $naar" "$f" "$tmp/leeg" "$n"; then
          conflicten+=("$f"); markeer_conflict "$f" "" "$tmp/service" "$n"
        fi
      fi
    elif [ -e "$f" ]; then                          # verwijderd uit het template
      if cmp -s "$f" "$o"; then
        rm "$f"
      else
        conflicten+=("$f (verwijderd uit het template, aangepast in de service)")
        markeer_conflict "$f" "$o" "$f" ""
      fi
    fi
  done < <({ (cd "$tmp/oud" && find . -type f -print0); (cd "$tmp/nieuw" && find . -type f -print0); } | sort -zu)

  # Zoals cruft update: nieuwe commit en context; checkout blijft leeg (standaardbranch).
  jq --arg commit "$stap" --slurpfile ctx "$tmp/nieuw.json" \
    '.commit = $commit | .checkout = null | .context = $ctx[0]' .cruft.json > "$tmp/cruft.json"
  cp "$tmp/cruft.json" .cruft.json

  if [ ${#conflicten[@]} -gt 0 ]; then
    bericht_voor "$stap" > "$MSG_BESTAND"
    reden "conflict bij template $naar ($onderwerp): $(printf '%s, ' "${conflicten[@]}" | sed 's/, $//')"
    exit 1
  fi
  commit_alles "$(bericht_voor "$stap")"
  vorige="$stap"
done
