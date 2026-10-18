#!/usr/bin/env bash
# Transformatie cruft update: een template-service bijwerken naar de nieuwste commit
# van het template. Doet wat `cruft update` doet, maar commit voor commit en met echte
# git-conflicten; het commando `cruft update` zelf gebruiken we bewust niet (docs/adr/0004).
# Uitgangspunt is de commit in .cruft.json; het doel is de standaardbranch van het
# template. Per commit op de hoofdlijn van het template:
#   - de vorige en de volgende stand genereren met de context uit .cruft.json
#   - elk bestand 3-way mergen (basis = vorige stand, ours = service, theirs = volgende)
#   - .cruft.json bijwerken en committen als conventional commit: het type van de
#     template-commit met scope cruft, bv. "fix(cruft): logging op warn (777021d)"
# Met TEMPLATE_REF=<branch of commit> is het doel die ref in plaats van de standaardbranch:
# een template-wijziging uitproberen vóór die gemerged is (niet voor een echte run).
# Heeft het template van de service die ref niet (een ander template), dan exit 10:
# niet van toepassing.
# Bij het eerste conflict stopt de update, met diff3-conflictmarkers in de bestanden.
# De conflicten staan ook als echte git-conflicten in de index (basis, service,
# template), zodat een IDE (bv. IntelliJ: Git > Resolve Conflicts) ze 3-way kan mergen.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/template.sh"

vereist git jq

if git grep -qE '^(<<<<<<<|>>>>>>>)( |$)' -- . 2>/dev/null; then
  reden "er staan nog conflictmarkers in de service; los die eerst op"
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --quiet "$(jq -r .template .cruft.json)" "$tmp/template"
tpl() { git -C "$tmp/template" "$@"; }

huidig="$(jq -r .commit .cruft.json)"
if [ -n "${TEMPLATE_REF:-}" ]; then
  doel="$(tpl rev-parse -q --verify "origin/$TEMPLATE_REF^{commit}" || tpl rev-parse -q --verify "$TEMPLATE_REF^{commit}")" \
    || { naam="$(basename "$(jq -r .template .cruft.json)" .git)"
         reden "template $naam heeft geen $TEMPLATE_REF"; exit 10; }
  echo "template-ref $TEMPLATE_REF ($(tpl rev-parse --short "$doel")) in plaats van de standaardbranch"
else
  doel="$(tpl rev-parse HEAD)"
fi
tpl cat-file -e "$huidig^{commit}" 2>/dev/null \
  || { reden "de template-commit ${huidig:0:7} uit .cruft.json bestaat niet (meer) in het template; is de historie van het template herschreven?"; exit 1; }

if [ "$huidig" = "$doel" ] || tpl merge-base --is-ancestor "$doel" "$huidig"; then
  echo "service is al bij met het template ($(tpl rev-parse --short "$doel"))"
  exit 0
fi

# De commits op de hoofdlijn van het template sinds de huidige stand, oudste eerst.
stappen=()
while IFS= read -r c; do stappen+=("$c"); done < <(tpl rev-list --reverse --first-parent "$huidig..$doel")
if ! tpl merge-base --is-ancestor "$huidig" "$doel"; then
  stappen=("$doel")  # huidige stand ligt niet op de hoofdlijn: in één keer
fi
echo "${#stappen[@]} template-commit(s) achter, naar $(tpl rev-parse --short "$doel")"

# Commit-boodschap voor een template-commit: neemt het type over als de template-commit
# een conventional commit is (feat: ..., fix(x)!: ...), anders chore.
bericht_voor() {  # <commit>
  local onderwerp patroon='^([a-z]+)(\([^)]*\))?(!?): (.*)$'
  onderwerp="$(tpl log -1 --format=%s "$1")"
  if [[ "$onderwerp" =~ $patroon ]]; then
    printf '%s(cruft)%s: %s (%s)' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" "$(tpl rev-parse --short "$1")"
  else
    printf 'chore(cruft): %s (%s)' "$onderwerp" "$(tpl rev-parse --short "$1")"
  fi
}

# Bij een conflict bewaren we de commit-boodschap (zoals git dat met MERGE_MSG doet),
# zodat --verder de opgeloste stap met dezelfde boodschap commit.
MSG_BESTAND="$(git rev-parse --git-dir)/MIGRATIE_MSG"
rm -f "$MSG_BESTAND"

render() {  # <commit> <uitvoermap> <context.json>
  render_template .cruft.json "$tmp/template" "$1" "$2" "$3"
}

vorige="$huidig"
for stap in "${stappen[@]}"; do
  van="$(tpl rev-parse --short "$vorige")"; naar="$(tpl rev-parse --short "$stap")"
  onderwerp="$(tpl log -1 --format=%s "$stap")"
  echo "-- template $van -> $naar: $onderwerp"
  render "$vorige" "$tmp/oud" "$tmp/oud.json"
  render "$stap" "$tmp/nieuw" "$tmp/nieuw.json"

  merge_renders "$tmp/oud" "$tmp/nieuw" "template $van" "template $naar"

  # Zoals cruft update: nieuwe commit en context; checkout blijft leeg (standaardbranch).
  jq --arg commit "$stap" --slurpfile ctx "$tmp/nieuw.json" \
    '.commit = $commit | .checkout = null | .context = $ctx[0]' .cruft.json > "$tmp/cruft.json"
  cp "$tmp/cruft.json" .cruft.json

  if [ ${#MERGE_CONFLICTEN[@]} -gt 0 ]; then
    bericht_voor "$stap" > "$MSG_BESTAND"
    stop_commit "$stap"
    reden "conflict bij template $naar ($onderwerp): $(printf '%s, ' "${MERGE_CONFLICTEN[@]}" | sed 's/, $//')"
    exit 1
  fi
  commit_alles "$(bericht_voor "$stap")"
  vorige="$stap"
done
