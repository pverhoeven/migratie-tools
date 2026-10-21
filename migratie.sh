#!/usr/bin/env bash
# Interactief menu voor migratie-tools: kies wat je wilt doen en welke migratie (of maak
# er een), bevestig de branch en de PR-titel, en het menu start het bijbehorende script.
# De losse scripts (in-repo.sh, uitproberen.sh, run.sh, cruft-zet.sh, achterstand.sh, status.sh) blijven
# gewoon bruikbaar; het menu toont aan het eind het commando dat het uitvoert.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/migratie.sh"
. "$ROOT/lib/recepten.sh"
if [ -f "$ROOT/config.env" ]; then
  set -a; . "$ROOT/config.env"; set +a
fi

# --- invoer -----------------------------------------------------------------------

vraag() {  # <tekst> <standaard>; het antwoord komt in ANTWOORD
  local a
  read -r -p "$1${2:+ [$2]}: " a
  ANTWOORD="${a:-$2}"
}

ja() {  # <tekst> <standaard j|n>; geeft 0 bij ja
  local a standaard="$2" hint="[j/N]"
  [ "$standaard" = j ] && hint="[J/n]"
  read -r -p "$1 $hint " a
  a="${a:-$standaard}"
  [[ "$a" == [jJyY]* ]]
}

kies() {  # <vraag> <optie>...; het nummer (1..n) komt in KEUZE
  local tekst="$1" i n
  shift
  echo "$tekst"
  i=1
  for o in "$@"; do printf '  %d) %s\n' "$i" "$o"; i=$((i + 1)); done
  n=$#
  while :; do
    read -r -p "keuze: " KEUZE
    [[ "$KEUZE" =~ ^[0-9]+$ ]] && [ "$KEUZE" -ge 1 ] && [ "$KEUZE" -le "$n" ] && break
    echo "kies een nummer van 1 tot en met $n"
  done
  echo
}

# Zet KEY=waarde in een env-bestand (vervangt een bestaande regel, anders erbij).
zet_in_bestand() {  # <bestand> <key> <waarde>
  local regel
  regel="$2='${3//\'/\'\\\'\'}'"
  if grep -q "^$2=" "$1"; then
    REGEL="$regel" awk -v k="$2" 'index($0, k "=") == 1 { print ENVIRON["REGEL"]; next } { print }' "$1" > "$1.tmp"
    mv "$1.tmp" "$1"
  else
    printf '%s\n' "$regel" >> "$1"
  fi
}

# --- migraties en recepten -----------------------------------------------------------

beschrijf() {  # <migratiebestand>: korte omschrijving van wat de migratie doet
  local d=() w
  w="$(bash -c 'set -a; . "$1"; printf "%s|%s|%s|%s|%s" "${CRUFT_UPDATE:-}" "${CRUFT_ZET:-}" "${RECEPT:-}" "${ALLEEN_MET_DEPENDENCY:-}" "${DEPENDENCY_VERSIE:-}"' _ "$1")"
  IFS='|' read -r cruft zet recept alleen deps <<< "$w"
  [ -n "$cruft" ] && d+=("cruft update")
  [ -n "$zet" ] && d+=("$zet")
  [ -n "$recept" ] && d+=("recept ${recept##*.}")
  [ -n "$deps" ] && d+=("versie $(for x in $deps; do printf '%s ' "$(cut -d: -f2- <<< "$x")"; done | sed 's/ $//')")
  local IFS=,
  echo "$(echo "${d[*]:-?}" | sed 's/,/ + /g')${alleen:+ (alleen met $alleen)}"
}

recepten() {  # alle recepten uit recepten/ en RECEPTEN_MAP (YAML-namen en Java-klassen)
  local m
  while IFS= read -r m; do
    grep -rhE '^name: ' "$m/src/main/resources/META-INF/rewrite" 2>/dev/null | sed 's/^name: *//'
    (cd "$m/src/main/java" 2>/dev/null && grep -rlE 'extends Recipe\b' . | sed 's|^\./||; s|\.java$||; s|/|.|g')
  done < <(recepten_modules "$ROOT")
}

kebab() { sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' <<< "$1" | tr '[:upper:]' '[:lower:]'; }

nieuwe_migratie() {  # maakt migraties/<naam>.env aan; het pad komt in MIGRATIEBESTAND
  local cruft=0 zet="" alleen="" recept="" naam titel lijst=() delen=()
  ja "Cruft update meenemen (services bijwerken naar de nieuwste stand van het template)?" j && cruft=1
  vraag "Template-variabele omzetten? (bv. gedeelde_jar=true; leeg = nee)" ""
  zet="$ANTWOORD"
  if [ -n "$zet" ]; then
    [[ "$zet" == ?*=* ]] || { echo "gebruik <variabele>=<waarde>" >&2; exit 2; }
    vraag "Alleen services met deze dependency? (artifactId; leeg = alle services)" ""
    alleen="$ANTWOORD"
  fi
  while IFS= read -r r; do lijst+=("$r"); done < <(recepten | sort)
  kies "Recept (OpenRewrite)?" "geen" "${lijst[@]}"
  [ "$KEUZE" -gt 1 ] && recept="${lijst[$((KEUZE - 2))]}"
  if [ "$cruft" -eq 0 ] && [ -z "$zet" ] && [ -z "$recept" ]; then
    echo "een migratie heeft een cruft update, een variabele en/of een recept nodig" >&2; exit 2
  fi

  [ "$cruft" -eq 1 ] && delen+=("cruft-update")
  [ -n "$zet" ] && delen+=("$(tr '_=' '--' <<< "${zet%%=*}")")
  [ -n "$recept" ] && delen+=("$(kebab "${recept##*.}")")
  naam="$(IFS=-; echo "${delen[*]}")"
  while :; do
    vraag "Naam van de migratie" "$naam-$(date +%Y-%m-%d)"
    naam="$ANTWOORD"
    if ! [[ "$naam" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then echo "alleen a-z, 0-9, . _ -"
    elif [ -e "$(migratie_mappen | head -1)/$naam.env" ]; then echo "$naam.env bestaat al"
    else break; fi
  done
  if [ -n "$zet" ]; then titel="feat(cruft): ${zet%%=*}${alleen:+ voor services met $alleen}"
  elif [ "$cruft" -eq 1 ] && [ -n "$recept" ]; then titel="chore(migratie): cruft update en ${recept##*.}"
  elif [ "$cruft" -eq 1 ]; then titel="chore(cruft): bijwerken naar de nieuwste stand van het template"
  else titel="chore(recept): ${recept##*.}"; fi
  # Nieuwe migraties komen in de eerste map: MIGRATIES_MAP als die gezet is.
  MIGRATIEBESTAND="$(migratie_mappen | head -1)/$naam.env"
  {
    echo "# Aangemaakt met migratie.sh op $(date +%Y-%m-%d)."
    [ -n "$alleen" ] && echo "ALLEEN_MET_DEPENDENCY=$alleen"
    [ "$cruft" -eq 1 ] && echo "CRUFT_UPDATE=ja"
    [ -n "$zet" ] && echo "CRUFT_ZET='$zet'"
    [ -n "$recept" ] && echo "RECEPT=$recept"
  } > "$MIGRATIEBESTAND"
  NIEUWE_TITEL="$titel"
}

kies_migratie() {  # het pad komt in MIGRATIEBESTAND
  local bestanden=() opties=() f map
  while IFS= read -r map; do
    for f in "$map"/*.env; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in _*) continue ;; esac
      bestanden+=("$f")
      opties+=("$(printf '%-34s %s' "$(basename "$f" .env)" "$(beschrijf "$f")")")
    done
  done < <(migratie_mappen)
  NIEUWE_TITEL=""
  kies "Welke migratie?" ${opties[@]+"${opties[@]}"} "nieuwe migratie maken…" "ander migratiebestand (pad opgeven)…"
  if [ "$KEUZE" -le ${#bestanden[@]} ]; then
    MIGRATIEBESTAND="${bestanden[$((KEUZE - 1))]}"
  elif [ "$KEUZE" -eq $(( ${#bestanden[@]} + 1 )) ]; then
    nieuwe_migratie
  else
    vraag "Pad naar het migratiebestand" ""
    [ -f "$ANTWOORD" ] || { echo "niet gevonden: $ANTWOORD" >&2; exit 2; }
    MIGRATIEBESTAND="$(cd "$(dirname "$ANTWOORD")" && pwd)/$(basename "$ANTWOORD")"
  fi
}

# Stelt branch en PR-titel voor; wat afwijkt van wat er nu geldt, gaat het
# migratiebestand in, zodat elke run van deze migratie dezelfde branch en titel gebruikt.
branch_en_titel() {
  local naam huidig
  naam="$(basename "$MIGRATIEBESTAND" .env)"
  huidig="$(bash -c 'set -a; . "$1"; echo "${BRANCH:-}"' _ "$MIGRATIEBESTAND")"
  huidig="${huidig:-$(branch_prefix)$naam}"
  vraag "Branch" "$huidig"
  git check-ref-format --branch "$ANTWOORD" >/dev/null 2>&1 || { echo "ongeldige branchnaam: $ANTWOORD" >&2; exit 2; }
  [ "$ANTWOORD" = "$huidig" ] || zet_in_bestand "$MIGRATIEBESTAND" BRANCH "$ANTWOORD"

  huidig="$(bash -c 'set -a; . "$1"; echo "${PR_TITEL:-}"' _ "$MIGRATIEBESTAND")"
  huidig="${huidig:-chore(migratie): $naam}"
  vraag "PR-titel" "${NIEUWE_TITEL:-$huidig}"
  [ "$ANTWOORD" = "$huidig" ] || zet_in_bestand "$MIGRATIEBESTAND" PR_TITEL "$ANTWOORD"
  echo
}

uitvoeren() {  # <commando...>: tonen, bevestigen en starten
  echo "Uitvoeren: $*"
  ja "Doorgaan?" j || exit 0
  echo
  "$@"
}

# Bij een cruft update: alle template-commits in één keer of (standaard) één voor één.
# Geeft "env CRUFT_IN_EEN_KEER=ja" in EEN_KEER, om voor het commando te zetten.
in_een_keer() {  # <migratiebestand>
  EEN_KEER=()
  [ -n "$(bash -c 'set -a; . "$1"; echo "${CRUFT_UPDATE:-}"' _ "$1")" ] || return 0
  kies "Hoe de cruft update?" \
    "Commit voor commit (standaard)
       Elke template-commit een eigen commit; bij een conflict zie je precies welke
       template-wijziging botst." \
    "In één keer naar de nieuwste commit
       Eén merge en één commit, hooguit één conflictronde; sneller bij een grote
       achterstand."
  if [ "$KEUZE" -eq 2 ]; then EEN_KEER=(env CRUFT_IN_EEN_KEER=ja); fi
}

# --- menu ------------------------------------------------------------------------------

echo "migratie-tools: migraties (cruft update en/of OpenRewrite-recept) uitrollen over services"
echo
kies "Wat wil je doen?" \
  "Migratie in een repo draaien (in-repo.sh)
       In je eigen clone, bv. het project dat je in IntelliJ open hebt. Maakt een
       branch en commits; pushen en de MR openen doe je zelf." \
  "Migratie uitproberen op verse clones (uitproberen.sh)
       Zandbak: kloont services naar work/ en draait de migratie daar. Werkt
       zonder GitLab en pusht nooit; om te zien wat een migratie doet." \
  "Migratie over de hele GitLab-groep (run.sh)
       Draait de migratie op alle services en maakt per service een MR. Eerst
       een dry-run, daarna vraagt het menu of het echt moet." \
  "Template-variabele omzetten in een repo (cruft-zet.sh)
       Zet een keuze uit het template om voor één service, bv. liquibase aan
       of uit, en voert het effect daarvan door." \
  "Achterstand bekijken (achterstand.sh)
       Per template-service: op welke stand van het template hij zit en
       hoeveel template-commits hij achterloopt. Wijzigt niets." \
  "Status van een uitgerolde migratie (status.sh)
       Per service de MR: gemerged, open (met pipeline) of gesloten, en wie
       nog geen MR heeft. Wijzigt niets."

case "$KEUZE" in
  1)
    vraag "Pad naar de repo" "$PWD"; repo="$ANTWOORD"
    kies_migratie; branch_en_titel
    branch="$(bash -c '. "$1/lib/migratie.sh"; laad_migratie "$2" >/dev/null; echo "$BRANCH"' _ "$ROOT" "$MIGRATIEBESTAND")"
    if [ "$(git -C "$repo" branch --show-current 2>/dev/null)" = "$branch" ] && ja "Je staat al op $branch; verder na handwerk (--verder)?" j; then
      uitvoeren "$ROOT/in-repo.sh" --verder "$MIGRATIEBESTAND" "$repo"
    else
      in_een_keer "$MIGRATIEBESTAND"
      uitvoeren ${EEN_KEER[@]+"${EEN_KEER[@]}"} "$ROOT/in-repo.sh" "$MIGRATIEBESTAND" "$repo"
    fi ;;
  2)
    kies_migratie; branch_en_titel
    vraag "Welke services? (paden of git-URL's, gescheiden door spaties)" ""
    read -r -a repos <<< "$ANTWOORD"
    [ ${#repos[@]} -gt 0 ] || { echo "geen repo's opgegeven" >&2; exit 2; }
    in_een_keer "$MIGRATIEBESTAND"
    uitvoeren ${EEN_KEER[@]+"${EEN_KEER[@]}"} "$ROOT/uitproberen.sh" "$MIGRATIEBESTAND" "${repos[@]}" ;;
  3)
    kies_migratie; branch_en_titel
    vraag "Alleen services waarvan de naam matcht (regex, leeg = de hele groep)" ""
    extra=()
    [ -z "$ANTWOORD" ] || extra=(--repo-include "$ANTWOORD")
    echo "Eerst een dry-run: er wordt niets gepusht."
    uitvoeren "$ROOT/run.sh" "$MIGRATIEBESTAND" ${extra[@]+"${extra[@]}"}
    echo
    if ja "Nu echt uitvoeren en MR's aanmaken (--go)?" n; then
      uitvoeren "$ROOT/run.sh" "$MIGRATIEBESTAND" --go ${extra[@]+"${extra[@]}"}
    fi ;;
  4)
    vraag "Pad naar de repo" "$PWD"; repo="$ANTWOORD"
    if [[ "$(git -C "$repo" branch --show-current 2>/dev/null)" == "$(branch_prefix)"cruft-zet-* ]] \
       && ja "Je staat op een cruft-zet-branch; verder na handwerk (--verder)?" j; then
      uitvoeren "$ROOT/cruft-zet.sh" --verder "$repo"
    else
      [ -f "$repo/.cruft.json" ] || { echo "$repo is geen template-service (geen .cruft.json)" >&2; exit 2; }
      echo "Huidige waarden:"
      jq -r '.context.cookiecutter | to_entries[] | select(.key | startswith("_") | not)
             | select(.value | type == "boolean" or type == "number") | "  \(.key) = \(.value)"' "$repo/.cruft.json"
      vraag "Variabele=waarde (bv. liquibase=true)" ""
      [[ "$ANTWOORD" == *=* ]] || { echo "gebruik variabele=waarde" >&2; exit 2; }
      uitvoeren "$ROOT/cruft-zet.sh" "$ANTWOORD" "$repo"
    fi ;;
  5)
    vraag "Paden naar lokale repo's (leeg = alle template-services in de GitLab-groep)" ""
    read -r -a repos <<< "$ANTWOORD"
    uitvoeren "$ROOT/achterstand.sh" ${repos[@]+"${repos[@]}"} ;;
  6)
    vraag "Naam van de migratie (het label op de MR's, bv. opschoning-2026-w43)" ""
    [ -n "$ANTWOORD" ] || { echo "geen migratie opgegeven" >&2; exit 2; }
    uitvoeren "$ROOT/status.sh" "$ANTWOORD" ;;
esac
