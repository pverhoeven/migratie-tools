#!/usr/bin/env bash
# Voert de voorbeeldwijzigingen door in het template: elke voorbeeld/wijzigingen/*.patch
# wordt één commit op main, in volgorde (actuator en health-probes, Spring Boot 3.5.7,
# logging op WARN, resources in de chart, datasource-pool begrenzen, liquibase krijgt de
# datasource-URL, jib, de gedeelde jar via een init container), als conventional commit.
# Geen tags.
# Je kunt het template in work/voorbeeld/template ook zelf wijzigen en committen.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$HIER/../work/voorbeeld/template"
[ -d "$TEMPLATE/.git" ] || { echo "draai eerst voorbeeld/opzetten.sh" >&2; exit 1; }

for patch in "$HIER"/wijzigingen/*.patch; do
  # 03-fix-logging-op-warn.patch -> "fix: logging op warn" (conventional commits)
  onderwerp="$(basename "$patch" .patch | sed -E 's/^[0-9]+-([a-z]+)-/\1: /; s/-/ /g')"
  if grep -qxF "$onderwerp" <(git -C "$TEMPLATE" log --format=%s); then
    echo "al doorgevoerd: $onderwerp"; continue
  fi
  git -C "$TEMPLATE" apply "$patch"
  git -C "$TEMPLATE" add -A
  git -C "$TEMPLATE" -c user.name=voorbeeld -c user.email=voorbeeld@localhost commit -q -m "$onderwerp"
  echo "template gewijzigd: $onderwerp"
done
