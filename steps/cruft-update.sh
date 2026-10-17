#!/usr/bin/env bash
# Stap: template-wijzigingen uit cruft toepassen.
# Optioneel: TEMPLATE_VERSION=v1.4.0 om een specifieke tag/commit uit te rollen.
set -euo pipefail

if [ ! -f .cruft.json ]; then
  echo "geen .cruft.json, overgeslagen"
  exit 1
fi

args=(-y)
if [ -n "${TEMPLATE_VERSION:-}" ]; then
  args+=(-c "$TEMPLATE_VERSION")
fi

cruft update "${args[@]}"

# Conflicten: niet doorzetten, hier moet een mens naar kijken.
leftovers="$(find . -path ./.git -prune -o \( -name '*.rej' -o -name '*.orig' \) -print)"
if [ -n "$leftovers" ]; then
  echo "conflicten bij cruft update (.rej/.orig gevonden), overgeslagen:"
  echo "$leftovers"
  exit 1
fi
if git grep -lE '^(<<<<<<<|>>>>>>>) ' -- . >/dev/null 2>&1; then
  echo "conflictmarkers in bestanden gevonden, overgeslagen"
  exit 1
fi
