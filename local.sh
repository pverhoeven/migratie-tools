#!/usr/bin/env bash
# Lokaal uitvoeren: kloont elke service naar ./work/<naam>, maakt de branch
# migratie/<naam> aan en draait daar de migratie. Er wordt nooit gepusht.
# Je eigen werkmap blijft onaangeroerd; bekijk het resultaat in work/<naam>.
#
# Gebruik: ./local.sh [--zonder-verify] <migratiebestand> <repo> [<repo> ...]
#   repo  pad naar een lokale repo of een git-URL
#         (let op: een lokale repo wordt gekloond, niet-gecommitte wijzigingen
#         worden dus niet meegenomen)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/migratie.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi

ZONDER_VERIFY=0
if [ "${1:-}" = "--zonder-verify" ]; then ZONDER_VERIFY=1; shift; fi
export ZONDER_VERIFY

if [ $# -lt 2 ]; then
  echo "gebruik: $0 [--zonder-verify] <migratiebestand> <repo> [<repo> ...]" >&2
  exit 2
fi
laad_migratie "$1"; shift

WORK_DIR="${WORK_DIR:-$ROOT/work}"
mkdir -p "$WORK_DIR"
ok=(); skipped=()

for repo in "$@"; do
  name="$(basename "${repo%/}")"; name="${name%.git}"
  dest="$WORK_DIR/$name"
  echo
  echo "=== $name ==="
  rm -rf "$dest"
  git clone --quiet "$repo" "$dest"
  git -C "$dest" checkout -q -b "migratie/$MIGRATIE"

  if (cd "$dest" && "$ROOT/repo-runner.sh"); then
    ok+=("$name")
    echo "--- commits op migratie/$MIGRATIE in $dest:"
    git -C "$dest" log --oneline origin/HEAD..HEAD
    git -C "$dest" status --short
  else
    skipped+=("$name")
    echo "--- overgeslagen (zie hierboven); de stand staat in $dest"
  fi
done

echo
echo "=== samenvatting: $MIGRATIE ==="
echo "geslaagd:     ${ok[*]-geen}"
echo "overgeslagen: ${skipped[*]-geen}"
echo "resultaten in: $WORK_DIR"
