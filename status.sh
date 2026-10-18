#!/usr/bin/env bash
# Hoe staat een migratie ervoor na de uitrol? Per service de MR van de migratie
# (gemerged, open of gesloten), bij open MR's de pipeline en hoelang ze al open staan, en
# de services zonder MR volgens de laatste run (runs/<migratie>-*/resultaten.tsv).
# Wijzigt niets.
#
# Gebruik: ./status.sh <migratie>
#   migratie  naam van de migratie (het label op de MR's) of pad naar het migratiebestand
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/gitlab.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi
vereist curl jq

if [ $# -ne 1 ]; then
  echo "gebruik: $0 <migratie>" >&2
  exit 2
fi
naam="$(basename "$1" .env)"
if ! [[ "$naam" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
  echo "ongeldige migratienaam '$naam' (alleen a-z, 0-9, . _ -)" >&2; exit 2
fi
: "${GITLAB_TOKEN:?zet GITLAB_TOKEN (in config.env of je shell)}"
: "${GITLAB_GROUP:?zet GITLAB_GROUP (in config.env of je shell)}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

migratie_mrs "$naam" > "$tmp/alle.tsv" || { echo "kon de MR's niet opvragen bij GitLab" >&2; exit 2; }
# Per project alleen de nieuwste MR (bv. na een gesloten MR een nieuwe ronde).
sort -t $'\t' -k5,5r "$tmp/alle.tsv" | awk -F'\t' '!gezien[$2]++' > "$tmp/mrs.tsv"

# Indelen: "<groep><TAB><service><TAB><regel>"; open MR's met hun pipeline.
: > "$tmp/status.tsv"
while IFS=$'\t' read -r id pad iid state _ dagen conflict url; do
  case "$state" in
    merged) groep="Gemerged"; regel="!$iid" ;;
    closed|locked) groep="Gesloten zonder merge"; regel="!$iid  $url" ;;
    *)
      pipeline="$(mr_pipeline "$id" "$iid")" || pipeline="?"
      [ "$dagen" = 1 ] && open="1 dag open" || open="$dagen dagen open"
      regel="!$iid  $open  pipeline $pipeline  $url"
      if [ "$conflict" = "true" ]; then groep="Open, conflict met de doelbranch"
      else
        case "$pipeline" in
          failed|canceled) groep="Open, pipeline rood" ;;
          success) groep="Open, pipeline groen" ;;
          *) groep="Open, pipeline loopt of ontbreekt" ;;
        esac
      fi ;;
  esac
  printf '%s\t%s\t%s\n' "$groep" "$pad" "$regel" >> "$tmp/status.tsv"
done < "$tmp/mrs.tsv"

# Services zonder MR: handwerk of wachtend volgens de laatste run van deze migratie.
laatste="$(ls -d "$ROOT"/runs/"$naam"-*/resultaten.tsv 2>/dev/null | sort | tail -1 || true)"
if [ -n "$laatste" ]; then
  while IFS=$'\t' read -r service uitkomst reden _; do
    case "$uitkomst" in "Handwerk nodig"|"Wacht op vorige migratie") ;; *) continue ;; esac
    # Een service met een MR (pad of naam) telt hier niet mee.
    awk -F'\t' -v s="$service" '$2 == s || $2 ~ ("/" s "$")' "$tmp/mrs.tsv" | grep -q . && continue
    printf '%s\t%s\t%s\n' "Geen MR" "$service" "$uitkomst: $reden" >> "$tmp/status.tsv"
  done < "$laatste"
fi

echo
echo "=== status $naam ==="
totaal="$(wc -l < "$tmp/mrs.tsv" | tr -d ' ')"
gemerged="$(awk -F'\t' '$1 == "Gemerged"' "$tmp/status.tsv" | wc -l | tr -d ' ')"
echo "Gemerged: $gemerged van $totaal MR('s)"
for g in "Open, conflict met de doelbranch" "Open, pipeline rood" "Geen MR" \
         "Open, pipeline loopt of ontbreekt" "Open, pipeline groen" "Gesloten zonder merge"; do
  n="$(awk -F'\t' -v g="$g" '$1 == g' "$tmp/status.tsv" | wc -l | tr -d ' ')"
  [ "$n" -gt 0 ] || continue
  case "$g" in "Open, conflict"*|"Open, pipeline rood"|"Geen MR") echo "$g ($n), de werklijst:" ;; *) echo "$g ($n):" ;; esac
  awk -F'\t' -v g="$g" '$1 == g { printf "  %-30s %s\n", $2, $3 }' "$tmp/status.tsv" | sort
done
if [ -n "$laatste" ]; then
  echo "services zonder MR volgens: $laatste"
else
  echo "geen run van $naam in runs/; services zonder MR zijn niet bekend"
fi
