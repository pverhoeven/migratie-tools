#!/usr/bin/env bash
# Toont het resultatenbestand van een run (service<TAB>uitkomst<TAB>reden<TAB>stop-commit),
# gegroepeerd per uitkomst, met de werklijst (Handwerk nodig) bovenaan.
set -euo pipefail
f="$1"

echo
echo "=== resultaten ==="
if [ ! -s "$f" ]; then
  echo "geen resultaten"
  exit 0
fi
for u in "Handwerk nodig" "Wacht op vorige migratie" "Gewijzigd" "Ongewijzigd" "Niet van toepassing"; do
  n="$(awk -F'\t' -v u="$u" '$2 == u' "$f" | wc -l | tr -d ' ')"
  [ "$n" -gt 0 ] || continue
  if [ "$u" = "Handwerk nodig" ]; then echo "$u ($n), de werklijst:"; else echo "$u ($n):"; fi
  awk -F'\t' -v u="$u" '$2 == u { printf "  %-30s %s\n", $1, $3 }' "$f" | sort
done
# Geen enkel template heeft de TEMPLATE_REF: waarschijnlijk een typfout in de branchnaam.
if [ -n "${TEMPLATE_REF:-}" ] && awk -F'\t' -v r="heeft geen $TEMPLATE_REF" 'index($3, r) { g = 1 }
     $2 == "Gewijzigd" || $2 == "Ongewijzigd" || $2 == "Handwerk nodig" { d = 1 } END { exit !(g && !d) }' "$f"; then
  echo "let op: geen enkel template heeft $TEMPLATE_REF; klopt de branchnaam, en is hij gepusht?"
fi
echo "resultaten in: $f"
if [ -d "$(dirname "$f")/debug" ]; then
  echo "per service (patches, uitvoer, stand bij handwerk): $(dirname "$f")/debug/"
fi
