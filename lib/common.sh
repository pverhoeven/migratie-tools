#!/usr/bin/env bash
# Gedeelde hulpfuncties (wordt gesourced, niet los uitgevoerd).

# Gebruik de Maven wrapper als de repo er een heeft, anders de globale mvn.
mvn_cmd() {
  if [ -x ./mvnw ]; then echo "./mvnw"; else echo "mvn"; fi
}

# Stop als een benodigd programma ontbreekt.
vereist() {
  local p
  for p in "$@"; do
    command -v "$p" >/dev/null || { echo "$p is nodig maar niet gevonden" >&2; exit 1; }
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
