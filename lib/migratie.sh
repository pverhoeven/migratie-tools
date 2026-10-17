#!/usr/bin/env bash
# Laadt een migratie (wordt gesourced door run.sh, local.sh en in-repo.sh). Een migratie
# geef je op als pad naar een migratiebestand of als naam uit migraties/.
#
# Een migratiebestand migraties/<naam>.env bevat (minstens één transformatie):
#   CRUFT_UPDATE=ja     cruft update: de template-service bijwerken naar de nieuwste
#                       stand van het template (de commits leggen vast welke)
#   RECEPT              naam van één OpenRewrite-recept uit recepten/; vastgepind door
#                       de commit van migratie-tools (docs/adr/0002)
# De naam van het bestand is de naam van de migratie en van de branch.

laad_migratie() {  # <naam of pad>
  local bestand="$1" root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [ ! -f "$bestand" ] && [ -f "$root/migraties/${1%.env}.env" ]; then
    bestand="$root/migraties/${1%.env}.env"
  fi
  if [ ! -f "$bestand" ]; then
    echo "migratie niet gevonden: $1" >&2
    echo "geef een pad naar een migratiebestand, of een naam uit migraties/:" >&2
    find "$root/migraties" -name '*.env' ! -name '_*' -exec basename {} .env \; | sort | sed 's/^/  /' >&2
    echo "  (de voorbeeldmigraties staan in voorbeeld/, bv. $root/voorbeeld/cruft-update.env)" >&2
    exit 2
  fi

  MIGRATIE="$(basename "$bestand" .env)"
  if ! [[ "$MIGRATIE" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    echo "ongeldige migratienaam '$MIGRATIE' (alleen a-z, 0-9, . _ -)" >&2; exit 2
  fi

  # Waarden horen uit het migratiebestand te komen, niet uit config.env of de shell.
  unset CRUFT_UPDATE TEMPLATE_UPDATE TEMPLATE_VERSION RECEPT
  set -a; . "$bestand"; set +a
  export MIGRATIE

  if [ -n "${TEMPLATE_VERSION:-}${TEMPLATE_UPDATE:-}" ]; then
    echo "$bestand: gebruik CRUFT_UPDATE=ja (altijd de nieuwste stand van het template)" >&2; exit 2
  fi
  case "${CRUFT_UPDATE:-}" in
    ""|ja) ;;
    *) echo "$bestand: CRUFT_UPDATE moet 'ja' zijn of ontbreken" >&2; exit 2 ;;
  esac
  if [ -z "${CRUFT_UPDATE:-}" ] && [ -z "${RECEPT:-}" ]; then
    echo "$bestand: zet CRUFT_UPDATE=ja en/of RECEPT" >&2; exit 2
  fi
}

# Commit het handwerk (opgeloste conflicten of een gerepareerde build) in de repo <dir>,
# zodat de migratie verder kan. Gebruikt door local.sh en in-repo.sh met --verder.
hervat() {  # <dir>
  local dest="$1" bericht
  if ! git -C "$dest" rev-parse --git-dir >/dev/null 2>&1; then
    echo "$dest is geen git-repo; draai de migratie eerst zonder --verder" >&2; return 1
  fi
  if [ "$(git -C "$dest" branch --show-current)" != "migratie/$MIGRATIE" ]; then
    echo "$dest staat niet op de branch migratie/$MIGRATIE" >&2; return 1
  fi
  if [ -n "$(git -C "$dest" ls-files -u)" ]; then
    echo "er zijn nog onopgeloste conflicten in $dest:" >&2
    git -C "$dest" diff --name-only --diff-filter=U | sed 's/^/  /' >&2
    echo "los ze op (bv. in IntelliJ: Git > Resolve Conflicts) of markeer ze met git add" >&2
    return 1
  fi
  if git -C "$dest" grep -qE '^(<<<<<<<|>>>>>>>)( |$)' -- .; then
    echo "er staan nog conflictmarkers in $dest:" >&2
    git -C "$dest" grep -lE '^(<<<<<<<|>>>>>>>)( |$)' -- . | sed 's/^/  /' >&2
    return 1
  fi
  [ -n "$(git -C "$dest" status --porcelain)" ] || return 0
  if ! git -C "$dest" diff --quiet HEAD -- .cruft.json 2>/dev/null; then
    bericht="cruft update: $(jq -r '.commit[0:7]' "$dest/.cruft.json") (conflict opgelost)"
  else
    bericht="handmatige aanpassing"
  fi
  (cd "$dest" && commit_alles "$bericht")
  echo "gecommit: $bericht"
}
