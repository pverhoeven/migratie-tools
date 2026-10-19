#!/usr/bin/env bash
# Laat per template-service zien op welke template-commit hij zit en hoeveel commits
# op de hoofdlijn van het template hij achterloopt (de achterstand). Wijzigt niets.
#
# Gebruik: ./achterstand.sh                  alle services in GITLAB_GROUP (GitLab-API)
#          ./achterstand.sh --repo-include <regex>
#                                             alleen projecten waarvan het pad matcht,
#                                             bv. 'backend/' of '-api$'
#          ./achterstand.sh <repo> [<repo>...] lokale repo's
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/gitlab.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi
vereist git jq

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
uitvoer="$tmp/uitvoer.tsv"
: > "$uitvoer"

# Voortgang op stderr, zodat de tabel op stdout schoon blijft. In een terminal steeds op
# dezelfde regel, anders (bv. in Jenkins) een regel per stap.
voortgang() {  # <tekst>
  if [ -t 2 ]; then printf '\r\033[K%s' "$1" >&2; else printf '%s\n' "$1" >&2; fi
}
voortgang_klaar() {
  if [ -t 2 ]; then printf '\r\033[K' >&2; fi
}

# Eén clone per template (gecachet op URL; cksum zit ook in Git Bash, shasum niet).
template_clone() {  # <url>
  local dir
  dir="$tmp/template-$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  if [ ! -d "$dir" ]; then
    voortgang "template clonen: $(basename "$1" .git)"
    git clone --quiet --bare "$1" "$dir"
  fi
  echo "$dir"
}

# Schrijft "<service><TAB><template-commit><TAB><achterstand><TAB><nieuwste>" voor één .cruft.json.
meet() {  # <service> <.cruft.json>
  local service="$1" url commit tpl versie nieuwste achter
  url="$(jq -r .template "$2")"; commit="$(jq -r .commit "$2")"
  if ! tpl="$(template_clone "$url")"; then
    printf '%s\t%s\t%s\t%s\n' "$service" "?" "?" "template niet te clonen" >> "$uitvoer"; return
  fi
  if ! git -C "$tpl" cat-file -e "$commit^{commit}" 2>/dev/null; then
    printf '%s\t%s\t%s\t%s\n' "$service" "${commit:0:7}" "?" "commit onbekend in template" >> "$uitvoer"; return
  fi
  versie="$(git -C "$tpl" log -1 --format='%h %cs' "$commit")"
  nieuwste="$(git -C "$tpl" log -1 --format='%h %cs' HEAD)"
  achter="$(git -C "$tpl" rev-list --count --first-parent "$commit..HEAD")"
  printf '%s\t%s\t%s\t%s\n' "$service" "$versie" "$achter" "$nieuwste" >> "$uitvoer"
}

include=""
case "${1:-}" in
  --repo-include) include="${2:?--repo-include heeft een regex nodig}"; shift 2 ;;
  --repo-include=*) include="${1#*=}"; shift ;;
esac

if [ $# -gt 0 ]; then
  for repo in "$@"; do
    name="$(basename "${repo%/}")"
    if [ -f "$repo/.cruft.json" ]; then meet "$name" "$repo/.cruft.json"; fi
  done
else
  : "${GITLAB_TOKEN:?zet GITLAB_TOKEN (in config.env of je shell)}"
  : "${GITLAB_GROUP:?zet GITLAB_GROUP (in config.env of je shell)}"
  vereist curl
  # shellcheck disable=SC2086
  uitsluit="$(repo_regex ${UITSLUITLIJST:-} || true)"
  voortgang "projecten van $GITLAB_GROUP opvragen bij GitLab"
  projecten="$(groep_projecten)" || { voortgang_klaar; echo "kon de projecten niet opvragen bij GitLab" >&2; exit 2; }
  if [ -n "$include" ]; then
    projecten="$(while IFS=$'\t' read -r id pad ref; do
      if [[ "$pad" =~ $include ]]; then printf '%s\t%s\t%s\n' "$id" "$pad" "$ref"; fi
    done <<< "$projecten")"
  fi
  totaal="$(grep -c . <<< "$projecten" || true)"
  i=0
  while IFS=$'\t' read -r id pad ref; do
    [ -n "$id" ] || continue
    i=$((i + 1))
    if [ -n "$uitsluit" ] && [[ "$pad" =~ $uitsluit ]]; then continue; fi
    voortgang "[$i/$totaal] $pad"
    # Geen .cruft.json = geen template-service; die tellen hier niet mee.
    gitlab_api "projects/$id/repository/files/.cruft.json/raw?ref=$ref" > "$tmp/cruft.json" 2>/dev/null || continue
    meet "$pad" "$tmp/cruft.json"
  done <<< "$projecten"
  voortgang_klaar
  echo "$totaal project(en) bekeken, $(grep -c . "$uitvoer" || true) template-service(s)" >&2
fi

if [ ! -s "$uitvoer" ]; then
  echo "geen template-services gevonden"
  exit 0
fi
echo "Achterstand = het aantal commits van het template sinds de stand van de service;"
echo "zoveel stappen krijgt de service bij de volgende cruft update."
echo
printf '%-40s %-20s %-11s %s\n' "service" "template-commit" "achterstand" "nieuwste"
sort -t$'\t' -k3,3nr -k1,1 "$uitvoer" | while IFS=$'\t' read -r s v a n; do
  printf '%-40s %-20s %-11s %s\n' "$s" "$v" "$a" "$n"
done
