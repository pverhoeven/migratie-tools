#!/usr/bin/env bash
# Verwijdert build-output (target/ naast een pom.xml) als die niet getrackt is, voor
# het geval target/ niet in .gitignore staat. Laat bv. een Java-package "target" staan.
# Draait alleen in wegwerp-clones.
set -euo pipefail

find . -path ./.git -prune -o -name pom.xml -print | while IFS= read -r pom; do
  t="$(dirname "$pom")/target"
  [ -d "$t" ] || continue
  git ls-files --error-unmatch -- "$t" >/dev/null 2>&1 && continue
  rm -rf "$t"
done
