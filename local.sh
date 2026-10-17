#!/usr/bin/env bash
# Lokaal uitvoeren: kloont elke repo naar ./work/<naam> en draait daar de stappen.
# Je eigen werkmap blijft onaangeroerd; bekijk het resultaat met git diff in work/<naam>.
#
# Gebruik: ./local.sh <stappen> <repo> [<repo> ...]
#   stappen  bv. cruft-update,openrewrite,verify
#   repo     pad naar een lokale repo of een git-URL
#            (let op: een lokale repo wordt gekloond, niet-gecommitte wijzigingen worden dus niet meegenomen)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi

if [ $# -lt 2 ]; then
  echo "gebruik: $0 <stappen> <repo> [<repo> ...]" >&2
  echo "stappen: $(cd "$ROOT/steps" && ls *.sh | grep -v '^_' | sed 's/\.sh$//' | paste -sd, -)" >&2
  exit 2
fi

STEPS="$1"; shift
STEPS_DIR="$ROOT/steps"
WORK_DIR="${WORK_DIR:-$ROOT/work}"
export STEPS STEPS_DIR

IFS=',' read -ra list <<< "$STEPS"
for s in "${list[@]}"; do
  [ -f "$STEPS_DIR/$s.sh" ] || { echo "onbekende stap: $s" >&2; exit 2; }
done

mkdir -p "$WORK_DIR"
ok=(); skipped=()

for repo in "$@"; do
  name="$(basename "${repo%/}")"; name="${name%.git}"
  dest="$WORK_DIR/$name"
  echo
  echo "=== $name ==="
  patch="$WORK_DIR/$name.rewrite.patch"
  rm -rf "$dest" "$patch"
  git clone --quiet "$repo" "$dest"

  if (cd "$dest" && REWRITE_PATCH_OUT="$patch" "$ROOT/repo-runner.sh"); then
    ok+=("$name")
    echo "--- wijzigingen in $dest:"
    git -C "$dest" status --short
    git -C "$dest" diff --stat
    if [ -s "$patch" ]; then echo "--- OpenRewrite dryRun-patch: $patch"; fi
  else
    skipped+=("$name")
    echo "--- overgeslagen (een stap faalde, zie hierboven)"
  fi
done

echo
echo "=== samenvatting ==="
echo "geslaagd:    ${ok[*]-geen}"
echo "overgeslagen: ${skipped[*]-geen}"
echo "resultaten in: $WORK_DIR"
