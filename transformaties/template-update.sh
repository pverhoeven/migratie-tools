#!/usr/bin/env bash
# Transformatie: een template-service bijwerken naar TEMPLATE_VERSION, één
# template-versie per keer (docs/adr/0004). Per versie:
#   - de vorige en de volgende versie genereren met de context uit .cruft.json
#   - elk bestand 3-way mergen (basis = vorige versie, ours = service, theirs = volgende)
#   - .cruft.json bijwerken en committen ("template: <versie>")
# Bij het eerste conflict stopt de update, met diff3-conflictmarkers in de bestanden.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"

: "${TEMPLATE_VERSION:?zet TEMPLATE_VERSION}"
vereist git jq

if git grep -qE '^(<<<<<<<|>>>>>>>)( |$)' -- . 2>/dev/null; then
  reden "er staan nog conflictmarkers in de service; los die eerst op"
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --quiet "$(jq -r .template .cruft.json)" "$tmp/template"
tpl() { git -C "$tmp/template" "$@"; }
versienaam() { tpl describe --tags --exact-match "$1" 2>/dev/null || tpl rev-parse --short "$1"; }

huidig="$(jq -r .commit .cruft.json)"
doel="$(tpl rev-parse --verify --quiet "$TEMPLATE_VERSION^{commit}")" \
  || { reden "template-versie $TEMPLATE_VERSION bestaat niet"; exit 1; }
tpl cat-file -e "$huidig^{commit}" 2>/dev/null \
  || { reden "de template-commit $huidig van de service bestaat niet in het template"; exit 1; }

if [ "$huidig" = "$doel" ] || tpl merge-base --is-ancestor "$doel" "$huidig"; then
  echo "service zit al op $TEMPLATE_VERSION of verder"
  exit 0
fi

# De template-versies (tags) tussen huidig en doel, in volgorde, afgesloten met het doel.
versies=()
if tpl merge-base --is-ancestor "$huidig" "$doel"; then
  while IFS= read -r c; do
    if [ "$c" = "$doel" ] || [ -n "$(tpl tag --points-at "$c")" ]; then versies+=("$c"); fi
  done < <(tpl rev-list --reverse --ancestry-path "$huidig..$doel")
else
  versies=("$doel")  # geen rechte lijn tussen de twee (bv. andere branch): in één keer
fi

render() {  # <commit> <uitvoermap> <context.json>
  rm -rf "$2"
  cruft_python "$ROOT/lib/render-template.py" .cruft.json "$tmp/template" "$1" "$2" "$3" >/dev/null
}

: > "$tmp/leeg"
vorige="$huidig"
for versie in "${versies[@]}"; do
  van="$(versienaam "$vorige")"; naar="$(versienaam "$versie")"
  echo "-- template $van -> $naar"
  render "$vorige" "$tmp/oud" "$tmp/oud.json"
  render "$versie" "$tmp/nieuw" "$tmp/nieuw.json"

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

  jq --arg commit "$versie" --arg checkout "$naar" --slurpfile ctx "$tmp/nieuw.json" \
    '.commit = $commit | .checkout = $checkout | .context = $ctx[0]' .cruft.json > "$tmp/cruft.json"
  cp "$tmp/cruft.json" .cruft.json

  if [ ${#conflicten[@]} -gt 0 ]; then
    reden "conflict bij template $naar: $(printf '%s, ' "${conflicten[@]}" | sed 's/, $//')"
    exit 1
  fi
  commit_alles "template: $naar"
  vorige="$versie"
done
