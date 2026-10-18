#!/usr/bin/env bash
# Het template genereren en de uitkomst 3-way in een service mergen (wordt gesourced
# door de transformaties cruft update en cruft-zet; cwd = de service). Nodig: ROOT en
# lib/common.sh.

# Genereert het template op <commit> met de context uit <cruft.json>, zoals cruft dat
# doet, en schrijft de gebruikte context naar <context.json>.
render_template() {  # <cruft.json> <template-clone> <commit> <uitvoermap> <context.json>
  rm -rf "$4"
  cruft_python "$ROOT/lib/render-template.py" "$1" "$2" "$3" "$4" "$5" >/dev/null
}

# Zet een conflict in de index zoals git dat bij een merge doet: stage 1 = basis,
# 2 = service (ours), 3 = template (theirs). Een lege versie laat die stage weg. Zo kan
# een IDE (bv. IntelliJ: Git > Resolve Conflicts) het 3-way mergen.
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

# Werkt de service bij met het verschil tussen twee renders van het template: per
# bestand een 3-way-merge (basis = <oud>, ours = de service, theirs = <nieuw>).
# Conflicten krijgen diff3-markers en staan in de index; hun paden komen in de array
# MERGE_CONFLICTEN.
merge_renders() {  # <oud> <nieuw> <label oud> <label nieuw>
  local oud="$1" nieuw="$2" van="$3" naar="$4" f o n tmp
  tmp="$(mktemp -d)"
  : > "$tmp/leeg"
  MERGE_CONFLICTEN=()
  while IFS= read -r -d '' f; do
    f="${f#./}"; o="$oud/$f"; n="$nieuw/$f"
    if [ -f "$o" ] && [ -f "$n" ]; then
      cmp -s "$o" "$n" && continue                  # niet gewijzigd in het template
      [ -e "$f" ] || continue                       # door de service verwijderd: zo laten
      if cmp -s "$f" "$o"; then cp "$n" "$f"; continue; fi
      cmp -s "$f" "$n" && continue
      cp "$f" "$tmp/service"
      if ! git merge-file --diff3 -L service -L "$van" -L "$naar" "$f" "$o" "$n"; then
        MERGE_CONFLICTEN+=("$f"); markeer_conflict "$f" "$o" "$tmp/service" "$n"
      fi
    elif [ -f "$n" ]; then                          # nieuw in het template
      if [ ! -e "$f" ]; then
        mkdir -p "$(dirname "$f")"; cp "$n" "$f"
      elif ! cmp -s "$f" "$n"; then
        cp "$f" "$tmp/service"
        if ! git merge-file --diff3 -L service -L "(nieuw)" -L "$naar" "$f" "$tmp/leeg" "$n"; then
          MERGE_CONFLICTEN+=("$f"); markeer_conflict "$f" "" "$tmp/service" "$n"
        fi
      fi
    elif [ -e "$f" ]; then                          # verwijderd uit het template
      if cmp -s "$f" "$o"; then
        rm "$f"
      else
        MERGE_CONFLICTEN+=("$f (verwijderd uit het template, aangepast in de service)")
        markeer_conflict "$f" "$o" "$f" ""
      fi
    fi
  done < <({ (cd "$oud" && find . -type f -print0); (cd "$nieuw" && find . -type f -print0); } | sort -zu)
  rm -rf "$tmp"
}
