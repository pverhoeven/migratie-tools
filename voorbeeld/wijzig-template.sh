#!/usr/bin/env bash
# Voert de voorbeeldwijzigingen door in het template: elke voorbeeld/wijzigingen/<tag>.patch
# wordt een commit met die tag (v1.1.0: actuator en health-probes, v1.2.0: Spring Boot
# 3.5.7, logging op WARN en resources in de chart). Je kunt het template in
# work/voorbeeld/template natuurlijk ook zelf wijzigen: commit en tag het dan.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$HIER/../work/voorbeeld/template"
[ -d "$TEMPLATE/.git" ] || { echo "draai eerst voorbeeld/opzetten.sh" >&2; exit 1; }

for patch in "$HIER"/wijzigingen/*.patch; do
  tag="$(basename "$patch" .patch)"
  if git -C "$TEMPLATE" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "$tag bestaat al"; continue
  fi
  git -C "$TEMPLATE" apply "$patch"
  git -C "$TEMPLATE" add -A
  git -C "$TEMPLATE" -c user.name=voorbeeld -c user.email=voorbeeld@localhost commit -q -m "Template $tag"
  git -C "$TEMPLATE" tag "$tag"
  echo "template $tag aangemaakt"
done
