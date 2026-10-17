#!/usr/bin/env bash
# Zet een voorbeeld op in work/voorbeeld/:
#   template/            git-repo van het template, met tag v1.0.0
#   services/bestel-service, services/klant-service
#                        gegenereerd uit v1.0.0, elk met eigen aanpassingen erbovenop
# Daarna: voorbeeld/wijzig-template.sh en ./local.sh voorbeeld/template-v1.2.0.env ...
# (zie voorbeeld/README.md). Draai opnieuw om helemaal opnieuw te beginnen.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HIER/.." && pwd)"
. "$ROOT/lib/common.sh"
vereist git

DOEL="$ROOT/work/voorbeeld"
rm -rf "$DOEL"
mkdir -p "$DOEL/services"

git_v() { git -c user.name=voorbeeld -c user.email=voorbeeld@localhost "$@"; }
cruft_cmd() {
  if command -v cruft >/dev/null; then cruft "$@"; else cruft_python -m cruft "$@"; fi
}

# Het template als eigen git-repo, zoals jullie centrale template-repo.
cp -R "$HIER/template" "$DOEL/template"
git -C "$DOEL/template" init -q -b main
git -C "$DOEL/template" add -A
git_v -C "$DOEL/template" commit -q -m "Template v1.0.0"
git -C "$DOEL/template" tag v1.0.0

genereer() {  # <projectnaam>
  cruft_cmd create --no-input --checkout v1.0.0 --output-dir "$DOEL/services" \
    --extra-context "{\"project_name\": \"$1\"}" "$DOEL/template" >/dev/null
}
vervang() {  # <bestand> <oud> <nieuw>: eerste voorkomen, letterlijk
  python3 - "$@" <<'PY'
import sys
f, old, new = sys.argv[1:4]
s = open(f).read()
assert old in s, f"{old!r} niet gevonden in {f}"
open(f, "w").write(s.replace(old, new, 1))
PY
}

# bestel-service: aanpassingen die niet botsen met het template
genereer "Bestel Service"
s="$DOEL/services/bestel-service"
git -C "$s" init -q -b main && git -C "$s" add -A && git_v -C "$s" commit -q -m "Gegenereerd uit template v1.0.0"
printf 'bestel.max-items=10\n' >> "$s/src/main/resources/application.properties"
vervang "$s/chart/values.yaml" "replicaCount: 1" "replicaCount: 3"
vervang "$s/pom.xml" "    </dependencies>" "        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>
    </dependencies>"
git -C "$s" add -A && git_v -C "$s" commit -q -m "Eigen aanpassingen: max-items, 3 replica's, validation"

# klant-service: past de logging aan, die later ook in het template verandert
genereer "Klant Service"
s="$DOEL/services/klant-service"
git -C "$s" init -q -b main && git -C "$s" add -A && git_v -C "$s" commit -q -m "Gegenereerd uit template v1.0.0"
vervang "$s/src/main/resources/application.properties" "logging.level.root=INFO" "logging.level.root=DEBUG"
git -C "$s" add -A && git_v -C "$s" commit -q -m "Eigen aanpassing: debug-logging"

echo "voorbeeld opgezet in $DOEL"
echo "volgende stap: $HIER/wijzig-template.sh"
