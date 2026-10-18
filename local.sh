#!/usr/bin/env bash
# Lokaal uitvoeren: kloont elke service naar ./work/<naam>, maakt de branch
# migratie/<naam> aan en draait daar de migratie. Er wordt nooit gepusht.
# Je eigen werkmap blijft onaangeroerd; bekijk het resultaat in work/<naam>.
#
# Gebruik: ./local.sh [--zonder-verify] <migratiebestand> <repo> [<repo> ...]
#          ./local.sh --verder [--zonder-verify] <migratiebestand> <service> [...]
#   repo     pad naar een lokale repo of een git-URL
#            (let op: een lokale repo wordt gekloond, niet-gecommitte wijzigingen
#            worden dus niet meegenomen)
#   --verder bij "Handwerk nodig": maak de migratie af in de bestaande work/<service>.
#            Los eerst de conflicten op of repareer de build; --verder commit dat en
#            draait de migratie vanaf daar verder. Pushen en de MR openen doe je zelf.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/migratie.sh"
. "$ROOT/lib/recepten.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi

ZONDER_VERIFY=0
verder=0
while [ $# -gt 0 ]; do
  case "$1" in
    --zonder-verify) ZONDER_VERIFY=1 ;;
    --verder) verder=1 ;;
    *) break ;;
  esac
  shift
done
export ZONDER_VERIFY

if [ $# -lt 2 ]; then
  echo "gebruik: $0 [--zonder-verify] <migratiebestand> <repo> [<repo> ...]" >&2
  echo "         $0 --verder [--zonder-verify] <migratiebestand> <service> [...]" >&2
  exit 2
fi
migratiebestand="$1"
laad_migratie "$1"; shift

if [ -n "${RECEPT:-}" ]; then
  controleer_recept "$ROOT" "$RECEPT"
  bouw_recepten "$ROOT"
fi

WORK_DIR="${WORK_DIR:-$ROOT/work}"
mkdir -p "$WORK_DIR"
nieuwe_run "$ROOT" "$MIGRATIE"

for repo in "$@"; do
  name="$(basename "${repo%/}")"; name="${name%.git}"
  dest="$WORK_DIR/$name"
  echo
  echo "=== $name ==="
  # shellcheck disable=SC2086
  if [ -n "${UITSLUITLIJST:-}" ] && [[ "$name" =~ $(repo_regex $UITSLUITLIJST) ]]; then
    echo "staat op de uitsluitlijst, geen service"
    continue
  fi
  if [ "$verder" -eq 1 ]; then
    if ! hervat "$dest"; then
      printf '%s\tHandwerk nodig\t%s\n' "$name" "nog niet klaar om verder te gaan" >> "$RESULTATEN"
      continue
    fi
  else
    rm -rf "$dest"
    if ! git clone --quiet "$repo" "$dest"; then
      printf '%s\tHandwerk nodig\tclonen mislukt\n' "$name" >> "$RESULTATEN"
      continue
    fi
    git -C "$dest" checkout -q -B "migratie/$MIGRATIE"
  fi

  basis="$(git -C "$dest" rev-parse origin/HEAD)"
  if (cd "$dest" && REPOSITORY="$name" BASIS="$basis" "$ROOT/repo-runner.sh"); then
    echo "--- commits op migratie/$MIGRATIE in $dest:"
    git -C "$dest" log --oneline origin/HEAD..HEAD
    if [ "$verder" -eq 1 ]; then
      echo "--- klaar; push en open de MR zelf (labels: migratie, $MIGRATIE):"
      echo "    git -C $dest push -u origin migratie/$MIGRATIE"
      echo "--- titel: chore(migratie): $MIGRATIE"
      echo "--- beschrijving:"
      pr_beschrijving "$ROOT" | sed 's/^/    /'
    fi
  else
    echo "--- de stand staat in $dest; los het op (conflicten: git status) en draai daarna:"
    echo "    $0 --verder $migratiebestand $name"
  fi
done

"$ROOT/lib/samenvatting.sh" "$RESULTATEN"
