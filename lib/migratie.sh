#!/usr/bin/env bash
# Laadt een migratiebestand (wordt gesourced door run.sh en local.sh).
#
# Een migratiebestand migraties/<naam>.env bevat (minstens één transformatie):
#   CRUFT_UPDATE=ja     cruft update: de template-service bijwerken naar de nieuwste
#                       stand van het template (de commits leggen vast welke)
#   RECEPT              naam van één OpenRewrite-recept uit recepten/; vastgepind door
#                       de commit van migratie-tools (docs/adr/0002)
# De naam van het bestand is de naam van de migratie en van de branch.

laad_migratie() {
  local bestand="$1"
  [ -f "$bestand" ] || { echo "migratiebestand niet gevonden: $bestand" >&2; exit 2; }

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
