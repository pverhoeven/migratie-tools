#!/usr/bin/env bash
# Laadt een migratiebestand (wordt gesourced door run.sh en local.sh).
#
# Een migratiebestand migraties/<naam>.env bevat (minstens één transformatie):
#   TEMPLATE_VERSION          template-versie (tag) waarnaar bijgewerkt wordt
#   RECEPT                    naam van één OpenRewrite-recept
#   REWRITE_PLUGIN_VERSION    versie van rewrite-maven-plugin (verplicht bij RECEPT)
#   REWRITE_RECIPE_ARTIFACTS  komma-gescheiden groupId:artifactId:version
# Alles is vastgepind: "laatste versie" mag niet (docs/adr/0002).
# De naam van het bestand is de naam van de migratie en van de branch.

laad_migratie() {
  local bestand="$1"
  [ -f "$bestand" ] || { echo "migratiebestand niet gevonden: $bestand" >&2; exit 2; }

  MIGRATIE="$(basename "$bestand" .env)"
  if ! [[ "$MIGRATIE" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    echo "ongeldige migratienaam '$MIGRATIE' (alleen a-z, 0-9, . _ -)" >&2; exit 2
  fi

  # Waarden horen uit het migratiebestand te komen, niet uit config.env of de shell.
  unset TEMPLATE_VERSION RECEPT REWRITE_PLUGIN_VERSION REWRITE_RECIPE_ARTIFACTS
  set -a; . "$bestand"; set +a
  export MIGRATIE

  if [ -z "${TEMPLATE_VERSION:-}" ] && [ -z "${RECEPT:-}" ]; then
    echo "$bestand: zet TEMPLATE_VERSION en/of RECEPT" >&2; exit 2
  fi
  case "${TEMPLATE_VERSION:-}" in
    main|master|HEAD) echo "$bestand: TEMPLATE_VERSION moet een vaste versie zijn, geen '$TEMPLATE_VERSION'" >&2; exit 2 ;;
  esac
  if [ -n "${RECEPT:-}" ]; then
    : "${REWRITE_PLUGIN_VERSION:?$bestand: zet REWRITE_PLUGIN_VERSION}"
    case ",${REWRITE_RECIPE_ARTIFACTS:-},${REWRITE_PLUGIN_VERSION}," in
      *LATEST*|*RELEASE*) echo "$bestand: gebruik vaste versies, geen LATEST/RELEASE" >&2; exit 2 ;;
    esac
  fi
}
