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
  local kandidaat venvs map py=() kandidaten=()
  if [ -n "${CRUFT_PYTHON:-}" ]; then
    py=("$CRUFT_PYTHON")
  else
    vereist cruft
    if [ "$(head -c2 "$(command -v cruft)")" = "#!" ]; then
      read -r -a py <<< "$(head -1 "$(command -v cruft)" | sed 's/^#! *//')"
    else
      # Op Windows is cruft een .exe zonder #!-regel: zoek een Python die cruft kent,
      # eerst naast cruft.exe (venv: Scripts/python.exe, pip: <python>/Scripts/cruft.exe).
      map="$(dirname "$(command -v cruft)")"
      kandidaten+=("$map/python.exe" "$map/../python.exe")
      if type -P pipx >/dev/null && venvs="$(pipx environment --value PIPX_LOCAL_VENVS 2>/dev/null | tr -d '\r')"; then
        kandidaten+=("$venvs/cruft/Scripts/python.exe" "$venvs/cruft/bin/python")
      fi
      kandidaten+=(python3 python py)
      for kandidaat in "${kandidaten[@]}"; do
        if "$kandidaat" -c 'import cruft' >/dev/null 2>&1; then py=("$kandidaat"); break; fi
      done
      [ ${#py[@]} -gt 0 ] || { echo "geen Python met cruft gevonden; zet CRUFT_PYTHON in config.env" >&2; exit 1; }
    fi
  fi
  "${py[@]}" "$@"
}

# Het commando van IntelliJ, in IDEA (array). Eerst IDEA_CMD, dan de IntelliJ die nu
# draait (zo komt de vergelijking in het venster dat je open hebt, ook als er meer versies
# zijn geïnstalleerd), dan het PATH, dan de gebruikelijke installatieplekken. Geeft 1 als
# er geen is.
intellij_cmd() {
  local p kandidaten=() lad=""
  IDEA=()
  if [ -n "${IDEA_CMD:-}" ]; then IDEA=("$IDEA_CMD"); return 0; fi
  # De draaiende IntelliJ: macOS (.app), Windows in Git Bash (ps -W toont het Windows-pad)
  # en Linux.
  p="$(ps -axo comm= 2>/dev/null | grep -m1 -E '/IntelliJ IDEA[^/]*\.app/Contents/MacOS/idea$' || true)"
  if [ -z "$p" ] && type -P cygpath >/dev/null; then
    p="$(ps -W 2>/dev/null | grep -m1 -oiE '[a-z]:\\.*\\idea64\.exe' || true)"
    [ -z "$p" ] || p="$(cygpath -u "$p")"
  fi
  [ -n "$p" ] || p="$(ps -eo args= 2>/dev/null | grep -m1 -oE '^/[^ ]*/bin/idea(\.sh)?( |$)' | tr -d ' ' || true)"
  if [ -n "$p" ] && [ -x "$p" ]; then IDEA=("$p"); return 0; fi
  for p in idea idea.cmd idea64.exe idea.sh; do
    if type -P "$p" >/dev/null; then IDEA=("$p"); return 0; fi
  done
  # Geïnstalleerd maar niet gestart: de nieuwste versie op een van de gebruikelijke plekken.
  if [ -n "${LOCALAPPDATA:-}" ] && type -P cygpath >/dev/null; then lad="$(cygpath -u "$LOCALAPPDATA")"; fi
  shopt -s nullglob
  kandidaten=(
    /Applications/IntelliJ\ IDEA*.app/Contents/MacOS/idea "$HOME"/Applications/IntelliJ\ IDEA*.app/Contents/MacOS/idea
    /c/Program\ Files/JetBrains/IntelliJ\ IDEA*/bin/idea64.exe
    "$HOME"/.local/share/JetBrains/Toolbox/apps/intellij-idea*/bin/idea.sh /opt/idea*/bin/idea.sh /snap/bin/intellij-idea*
  )
  if [ -n "$lad" ]; then   # Windows: Toolbox (nieuw en oud)
    kandidaten+=("$lad"/Programs/IntelliJ\ IDEA*/bin/idea64.exe "$lad"/JetBrains/Toolbox/apps/*/ch-0/*/bin/idea64.exe)
  fi
  shopt -u nullglob
  for p in "${kandidaten[@]}"; do [ -x "$p" ] && IDEA=("$p"); done   # de laatste: de nieuwste
  [ ${#IDEA[@]} -gt 0 ]
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

# Meld iets wat een transformatie heeft overgeslagen en wat iemand moet nakijken: op het
# scherm en (via WAARSCHUWINGEN en SERVICE, gezet door de scripts en repo-runner.sh) per
# service in een bestand, zodat het in de MR-beschrijving komt.
waarschuwing() {
  echo "let op: $*" >&2
  if [ -n "${WAARSCHUWINGEN:-}" ] && [ -n "${SERVICE:-}" ]; then
    printf '%s\t%s\n' "$SERVICE" "$*" >> "$WAARSCHUWINGEN"
  fi
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
  # Per service wat er is overgeslagen en nagekeken moet worden (zie waarschuwing).
  WAARSCHUWINGEN="$map/waarschuwingen.tsv"
  : > "$WAARSCHUWINGEN"
  export RESULTATEN DEBUG_MAP WAARSCHUWINGEN
}

# Regex die eindigt op één van de gegeven repo-namen of -paden (voor --repo-exclude).
repo_regex() {  # <naam-of-pad>...
  local r="" n
  for n in "$@"; do
    r+="${r:+|}$(printf '%s' "$n" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
  done
  [ -n "$r" ] && printf '(^|/)(%s)$' "$r"
}
