#!/usr/bin/env bash
# Laat per template-service zien op welke template-commit hij zit en hoeveel commits
# op de hoofdlijn van het template hij achterloopt (de achterstand). Wijzigt niets.
#
# Gebruik: ./achterstand.sh                  alle services in GITLAB_GROUP (GitLab-API)
#          ./achterstand.sh --repo-include <regex>
#                                             alleen projecten waarvan het pad matcht,
#                                             bv. 'backend/' of '-api$'
#          ./achterstand.sh <repo> [<repo>...] lokale repo's
#   --uitgebreid  meld ook projecten zonder .cruft.json (404), met de reden van GitLab
#                 (bv. File Not Found, of Project Not Found bij te weinig rechten)
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

# Eén clone per template, bewaard in work/.templates (of TEMPLATE_CACHE) zodat een
# volgende run alleen de nieuwe commits ophaalt. Per run wordt elk template één keer
# bijgewerkt, ook als services de URL verschillend schrijven (zie template_sleutel).
cache="${TEMPLATE_CACHE:-$ROOT/work/.templates}"
mkdir -p "$cache"
template_clone() {  # <url>
  local url="$1" naam sleutel dir filter=()
  naam="$(basename "$url" .git)"
  sleutel="$(template_sleutel "$url" | cksum | cut -d' ' -f1)"
  dir="$cache/$sleutel.git"
  if [ ! -e "$tmp/bijgewerkt-$sleutel" ]; then
    # Alleen de commits (geen bestanden of mappen): genoeg om de achterstand te tellen.
    # Een lokaal pad (bv. het voorbeeld) kent geen filter.
    case "$url" in *://*|*@*:*) filter=(--filter=tree:0) ;; esac
    # De uitvoer van git (ondanks --quiet soms voortgang) alleen tonen als het misgaat.
    if [ -d "$dir" ]; then
      voortgang "template bijwerken: $naam"
      git -C "$dir" remote set-url origin "$url"
      git -C "$dir" fetch --quiet --prune origin '+refs/heads/*:refs/heads/*' > "$tmp/clone.log" 2>&1
    else
      voortgang "template clonen: $naam"
      rm -rf "$dir.nieuw"
      git clone --quiet --bare ${filter[@]+"${filter[@]}"} "$url" "$dir.nieuw" > "$tmp/clone.log" 2>&1 \
        && mv "$dir.nieuw" "$dir"
    fi || {
      voortgang_klaar
      echo "let op: template $naam niet te clonen of bij te werken:" >&2
      sed 's/^/  /' "$tmp/clone.log" >&2
      return 1
    }
    touch "$tmp/bijgewerkt-$sleutel"
  fi
  echo "$dir"
}

# Templates op de GitLab van GITLAB_BASE_URL clonen met GITLAB_TOKEN, zonder inlogvenster
# van een credential helper. Het token gaat alleen naar die host, en via de omgeving,
# niet als argument (dan staat het in de proceslijst). Werkt het token niet, dan faalt
# de clone met een melding in plaats van een popup.
git_met_token() {
  local basis="${GITLAB_BASE_URL:-https://gitlab.com}"
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="http.${basis%/}/.extraHeader"
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "$GITLAB_TOKEN" | base64 | tr -d '\n\r')"
  export GIT_CONFIG_VALUE_0
  export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never
}

# Schrijft "<service><TAB><template-commit><TAB><achterstand><TAB><nieuwste>" voor één .cruft.json.
meet() {  # <service> <.cruft.json>
  local service="$1" url commit tpl versie nieuwste achter
  url="$(template_url "$2")"; commit="$(jq -r .commit "$2")"
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
uitgebreid=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-include) include="${2:?--repo-include heeft een regex nodig}"; shift 2 ;;
    --repo-include=*) include="${1#*=}"; shift ;;
    --uitgebreid) uitgebreid=1; shift ;;
    *) break ;;
  esac
done

if [ $# -gt 0 ]; then
  for repo in "$@"; do
    name="$(basename "${repo%/}")"
    if [ -f "$repo/.cruft.json" ]; then meet "$name" "$repo/.cruft.json"; fi
  done
else
  : "${GITLAB_TOKEN:?zet GITLAB_TOKEN (in config.env of je shell)}"
  : "${GITLAB_GROUP:?zet GITLAB_GROUP (in config.env of je shell)}"
  vereist curl
  git_met_token
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
  i=0; fouten=0
  while IFS=$'\t' read -r id pad ref; do
    [ -n "$id" ] || continue
    i=$((i + 1))
    if [ -n "$uitsluit" ] && [[ "$pad" =~ $uitsluit ]]; then continue; fi
    voortgang "[$i/$totaal] $pad"
    # Zonder default branch (een lege repo) is er niets op te halen.
    if [ -z "$ref" ]; then
      if [ "$uitgebreid" -eq 1 ]; then voortgang_klaar; echo "$pad: lege repo (geen default branch)" >&2; fi
      continue
    fi
    # Geen .cruft.json (404) = geen template-service; die tellen hier niet mee. Een
    # andere fout (rechten, netwerk) melden we, anders lijkt het alsof er niets is.
    code="$(gitlab_bestand "$id" .cruft.json "$ref" "$tmp/cruft.json" 2>"$tmp/curl.err")" || code="${code:-000}"
    case "$code" in
      200) meet "$pad" "$tmp/cruft.json" ;;
      404) if [ "$uitgebreid" -eq 1 ]; then
             voortgang_klaar
             echo "$pad: geen .cruft.json op $ref (HTTP 404$(head -c 200 "$tmp/cruft.json" 2>/dev/null | tr -d '\n' | sed 's/^/: /'))" >&2
           fi ;;
      *) voortgang_klaar
         echo "let op: $pad: .cruft.json niet op te halen (HTTP $code$(head -c 200 "$tmp/cruft.json" 2>/dev/null | tr -d '\n' | sed 's/^/: /')$(sed 's/^/; /' "$tmp/curl.err" | tr -d '\n'))" >&2
         fouten=$((fouten + 1)) ;;
    esac
  done <<< "$projecten"
  voortgang_klaar
  echo "$totaal project(en) bekeken, $(grep -c . "$uitvoer" || true) template-service(s)$([ "$fouten" -gt 0 ] && echo ", $fouten fout(en), zie hierboven")" >&2
fi

if [ ! -s "$uitvoer" ]; then
  echo "geen template-services gevonden"
  exit 0
fi
echo "Achterstand = het aantal commits van het template sinds de stand van de service;"
echo "zoveel stappen krijgt de service bij de volgende cruft update."
echo
# De eerste kolom zo breed als de langste service (paden in subgroepen zijn lang).
breed="$(awk -F'\t' 'length($1) > b { b = length($1) } END { print (b > 7 ? b : 7) }' "$uitvoer")"
printf '%-*s  %-18s  %11s  %s\n' "$breed" "service" "template-commit" "achterstand" "nieuwste"
sort -t$'\t' -k3,3nr -k1,1 "$uitvoer" | while IFS=$'\t' read -r s v a n; do
  printf '%-*s  %-18s  %11s  %s\n' "$breed" "$s" "$v" "$a" "$n"
done
