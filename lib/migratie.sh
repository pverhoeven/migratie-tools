#!/usr/bin/env bash
# Laadt een migratie (wordt gesourced door run.sh, local.sh en in-repo.sh). Een migratie
# geef je op als pad naar een migratiebestand of als naam uit migraties/.
#
# Een migratiebestand migraties/<naam>.env bevat (minstens één transformatie):
#   CRUFT_UPDATE=ja     cruft update: de template-service bijwerken naar de nieuwste
#                       stand van het template (de commits leggen vast welke)
#   RECEPT              naam van één OpenRewrite-recept uit recepten/
# De PR-beschrijving bevat de inhoud van dit bestand (docs/adr/0002).
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
  MIGRATIE_BESTAND="$bestand"
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
  local dest="$1" bericht msg
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
  msg="$(git -C "$dest" rev-parse --absolute-git-dir)/MIGRATIE_MSG"
  if [ -f "$msg" ]; then
    bericht="$(cat "$msg")"$'\n\n'"Conflict handmatig opgelost."
  elif ! git -C "$dest" diff --quiet HEAD -- .cruft.json 2>/dev/null; then
    bericht="chore(cruft): conflict opgelost ($(jq -r '.commit[0:7]' "$dest/.cruft.json"))"
  else
    bericht="fix(migratie): handmatige aanpassing voor $MIGRATIE"
  fi
  (cd "$dest" && commit_alles "$bericht")
  rm -f "$msg"
  echo "gecommit: ${bericht%%$'\n'*}"
}

# Maakt in de huidige repo de branch <branch> vanaf de huidige commit en onthoudt dat
# beginpunt (voor --verder). Weigert bovenop een andere migratie, als de branch al
# bestaat en bij een vuile werkmap (de controle draait alles terug wat de build wijzigt).
# Gebruikt door in-repo.sh en cruft-zet.sh.
start_branch() {  # <branch>
  local branch="$1" huidige
  huidige="$(git branch --show-current || true)"
  case "$huidige" in
    migratie/*)
      echo "je staat op $huidige: start vanaf main, niet bovenop een andere migratie" >&2
      echo "ga eerst naar je hoofdbranch (bv. git switch main && git pull)" >&2
      exit 2 ;;
  esac
  if git rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    echo "de branch $branch bestaat al; gebruik --verder, of verwijder de branch om opnieuw te beginnen" >&2
    exit 2
  fi
  if [ -n "$(git status --porcelain)" ]; then
    echo "de werkmap is niet schoon; commit of stash eerst je wijzigingen" >&2
    exit 2
  fi
  echo "branch $branch vanaf ${huidige:-HEAD} ($(git rev-parse --short HEAD))"
  git config "branch.$branch.migratiebasis" "$(git rev-parse HEAD)"
  git switch -q -c "$branch"
}

# De commit van migratie-tools, met "(met lokale wijzigingen)" als de werkmap niet schoon is.
tools_versie() {  # <root>
  local v
  v="$(git -C "$1" rev-parse --short HEAD)"
  [ -z "$(git -C "$1" status --porcelain)" ] || v="$v (met lokale wijzigingen)"
  echo "$v"
}

# PR-beschrijving voor de geladen migratie: wat er gebeurt en de inhoud van het
# migratiebestand, zodat de PR zelf vastlegt wat er is uitgerold (docs/adr/0002).
pr_beschrijving() {  # <root>
  local inhoud
  inhoud="$(grep -vE '^[[:space:]]*(#|$)' "$MIGRATIE_BESTAND" || true)"
  printf 'Automatisch aangemaakt door migratie-tools, migratie `%s` (migratie-tools %s).\n\n' "$MIGRATIE" "$(tools_versie "$1")"
  [ -z "${CRUFT_UPDATE:-}" ] || printf -- '- cruft update naar de nieuwste stand van het template (één commit per template-commit)\n'
  [ -z "${RECEPT:-}" ] || printf -- '- recept `%s`\n' "$RECEPT"
  printf '\nMigratiebestand `%s.env`:\n\n```\n%s\n```\n\n' "$MIGRATIE" "$inhoud"
  printf 'Elke transformatie is een eigen commit. Controleer de diff en merge.\n'
}
