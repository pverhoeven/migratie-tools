#!/usr/bin/env bash
# Draait binnen één gekloonde repo (cwd = repo). Wordt gebruikt door zowel
# run.sh (via multi-gitter) als local.sh.
#
# STEPS      komma-gescheiden stappen, bv. cruft-update,openrewrite,verify
# STEPS_DIR  map met de stap-scripts
# Exit 0 = er is eventueel iets gewijzigd; non-zero = repo overslaan.
set -euo pipefail

: "${STEPS:?zet STEPS}"
: "${STEPS_DIR:?zet STEPS_DIR}"

# Het token is alleen voor multi-gitter zelf; de builds (tests, plugins) van
# de repo's hoeven het niet te zien.
unset GITLAB_TOKEN

IFS=',' read -ra list <<< "$STEPS"
for step in "${list[@]}"; do
  echo ">> stap: $step"
  "$STEPS_DIR/$step.sh"
done

# Build-output hoort niet in de commit (voor het geval target/ niet in .gitignore staat).
# Alleen target/ naast een pom.xml en zonder getrackte bestanden, zodat bv. een
# Java-package met de naam "target" blijft staan. Dit draait alleen in wegwerp-clones.
if [ "${CLEAN_TARGET:-1}" = "1" ]; then
  find . -path ./.git -prune -o -name pom.xml -print | while IFS= read -r pom; do
    t="$(dirname "$pom")/target"
    [ -d "$t" ] || continue
    git ls-files --error-unmatch -- "$t" >/dev/null 2>&1 && continue
    rm -rf "$t"
  done
fi
