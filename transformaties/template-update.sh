#!/usr/bin/env bash
# Transformatie: een template-service bijwerken naar de nieuwste commit van het
# template, zoals `cruft update` dat doet, maar commit voor commit (docs/adr/0004).
# Uitgangspunt is de commit in .cruft.json; het doel is de standaardbranch van het
# template. Per commit op de hoofdlijn van het template:
#   - de vorige en de volgende stand genereren met de context uit .cruft.json
#   - elk bestand 3-way mergen (basis = vorige stand, ours = service, theirs = volgende)
#   - .cruft.json bijwerken en committen ("template: <commit> <onderwerp>")
# Bij het eerste conflict stopt de update, met diff3-conflictmarkers in de bestanden.
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
  || { reden "de template-commit $huidig van de service bestaat niet in het template"; exit 1; }

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
echo "template: ${#stappen[@]} commit(s) achter, naar $(tpl rev-parse --short "$doel")"

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
      git merge-file --diff3 -L service -L "template $van" -L "template $naar" "$f" "$o" "$n" \
        || conflicten+=("$f")
    elif [ -f "$n" ]; then                          # nieuw in het template
      if [ ! -e "$f" ]; then
        mkdir -p "$(dirname "$f")"; cp "$n" "$f"
      elif ! cmp -s "$f" "$n"; then
        git merge-file --diff3 -L service -L "(nieuw)" -L "template $naar" "$f" "$tmp/leeg" "$n" \
          || conflicten+=("$f")
      fi
    elif [ -e "$f" ]; then                          # verwijderd uit het template
      if cmp -s "$f" "$o"; then rm "$f"; else conflicten+=("$f (verwijderd uit het template, aangepast in de service)"); fi
    fi
  done < <({ (cd "$tmp/oud" && find . -type f -print0); (cd "$tmp/nieuw" && find . -type f -print0); } | sort -zu)

  # Zoals cruft update: nieuwe commit en context; checkout blijft leeg (standaardbranch).
  jq --arg commit "$stap" --slurpfile ctx "$tmp/nieuw.json" \
    '.commit = $commit | .checkout = null | .context = $ctx[0]' .cruft.json > "$tmp/cruft.json"
  cp "$tmp/cruft.json" .cruft.json

  if [ ${#conflicten[@]} -gt 0 ]; then
    reden "conflict bij template $naar ($onderwerp): $(printf '%s, ' "${conflicten[@]}" | sed 's/, $//')"
    exit 1
  fi
  commit_alles "template: $naar $onderwerp"
  vorige="$stap"
done
