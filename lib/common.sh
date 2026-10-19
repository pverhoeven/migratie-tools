#!/usr/bin/env bash
# Gedeelde hulpfuncties (wordt gesourced, niet los uitgevoerd).

# jq op Windows (Git Bash) schrijft regels met \r\n. In $(jq ...) blijft de \r dan aan de
# waarde hangen (bv. een branch "main\r", die niet bestaat); daarom altijd zonder \r.
jq() { command jq "$@" | tr -d '\r'; }

# De git-URL van het template uit een .cruft.json. cruft en cookiecutter accepteren ook
# git+https://..., git zelf niet.
template_url() {  # <.cruft.json>
  local u
  u="$(jq -r .template "$1")"
  printf '%s' "${u#git+}"
}

# Eén sleutel per template, hoe de URL ook geschreven is: git@host:g/t.git,
# https://host/g/t en git+https://host/g/t.git/ zijn allemaal host/g/t.
template_sleutel() {  # <url>
  printf '%s' "${1#git+}" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#^[a-z+]+://##; s#^[^@/]+@##; s#^([^/:]+):#\1/#; s#/+$##; s#\.git$##'
}

# Gebruik de Maven wrapper als de repo er een heeft, anders de globale mvn.
mvn_cmd() {
  if [ -x ./mvnw ]; then echo "./mvnw"; else echo "mvn"; fi
}

# Stop als een benodigd programma ontbreekt.
vereist() {
  local p
  for p in "$@"; do
    type -P "$p" >/dev/null || { echo "$p is nodig maar niet gevonden" >&2; exit 1; }  # het programma, niet een functie
  done
}

# Draai Python met de interpreter van cruft, zodat cruft en cookiecutter importeerbaar
# zijn (ook bij een pipx-installatie). Overschrijfbaar met CRUFT_PYTHON.
cruft_python() {
  local py
  if [ -n "${CRUFT_PYTHON:-}" ]; then
    py=("$CRUFT_PYTHON")
  else
    vereist cruft
    read -r -a py <<< "$(head -1 "$(command -v cruft)" | sed 's/^#! *//')"
  fi
  "${py[@]}" "$@"
}

# Commit alles; valt terug op een vaste auteur als git er geen kent.
commit_alles() {
  git add -A
  if [ -n "$(git config user.email || true)" ]; then
    git commit -q -m "$1"
  else
    git -c user.name=migratie-tools -c user.email=migratie-tools@localhost commit -q -m "$1"
  fi
}

# Meld waarom een transformatie of controle faalt: op het scherm en (via
# REDEN_BESTAND, gezet door repo-runner.sh) als reden in het resultatenbestand.
reden() {
  echo "$*"
  if [ -n "${REDEN_BESTAND:-}" ]; then echo "$*" > "$REDEN_BESTAND"; fi
}

# De template-commit waar een transformatie stopt; komt als stop-commit in de resultaten.
stop_commit() {  # <commit>
  if [ -n "${STOP_BESTAND:-}" ]; then echo "$1" > "$STOP_BESTAND"; fi
}

# Maak de map voor de resultaten van een run aan en exporteer RESULTATEN.
nieuwe_run() {  # <root> <migratie>
  local map
  map="$1/runs/$2-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$map"
  RESULTATEN="$map/resultaten.tsv"
  : > "$RESULTATEN"
  # Per service de patches, de stand bij handwerk en de uitvoer (zie repo-runner.sh).
  DEBUG_MAP="$map/debug"
  export RESULTATEN DEBUG_MAP
}

# Regex die eindigt op één van de gegeven repo-namen of -paden (voor --repo-exclude).
repo_regex() {  # <naam-of-pad>...
  local r="" n
  for n in "$@"; do
    r+="${r:+|}$(printf '%s' "$n" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
  done
  [ -n "$r" ] && printf '(^|/)(%s)$' "$r"
}
