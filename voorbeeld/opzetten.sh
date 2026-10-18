#!/usr/bin/env bash
# Zet een voorbeeld op in work/voorbeeld/:
#   template/            git-repo van het template (één commit op main, geen tags)
#   services/bestel-service, services/klant-service
#                        gegenereerd uit het template, elk met eigen aanpassingen erbovenop
#   services/losse-service
#                        geen template-service, wel afnemer van de gedeelde jar
# en installeert nl.voorbeeld:gedeelde-jar (voorbeeld/gedeelde-jar) in de lokale ~/.m2.
# Daarna: voorbeeld/wijzig-template.sh en ./uitproberen.sh voorbeeld/cruft-update.env ...
# (zie voorbeeld/README.md). Draai opnieuw om helemaal opnieuw te beginnen.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HIER/.." && pwd)"
. "$ROOT/lib/common.sh"
vereist git mvn

DOEL="$ROOT/work/voorbeeld"
rm -rf "$DOEL"
mkdir -p "$DOEL/services"

git_v() { git -c user.name=voorbeeld -c user.email=voorbeeld@localhost "$@"; }
cruft_cmd() {
  if command -v cruft >/dev/null; then cruft "$@"; else cruft_python -m cruft "$@"; fi
}

# De gedeelde jar die afnemers gebruiken (zie voorbeeld/gedeelde-jar.env).
mvn -B -q -f "$HIER/gedeelde-jar/pom.xml" install

# Het template als eigen git-repo, zoals jullie centrale template-repo.
cp -R "$HIER/template" "$DOEL/template"
git -C "$DOEL/template" init -q -b main
git -C "$DOEL/template" add -A
git_v -C "$DOEL/template" commit -q -m "feat: eerste versie van het template"

genereer() {  # <extra context als JSON>, bv. {"project_name": "Bestel Service", "db": true}
  cruft_cmd create --no-input --output-dir "$DOEL/services" \
    --extra-context "$1" "$DOEL/template" >/dev/null
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

# bestel-service: met database, zonder liquibase; aanpassingen die niet botsen met het template
genereer '{"project_name": "Bestel Service", "db": true}'
s="$DOEL/services/bestel-service"
git -C "$s" init -q -b main && git -C "$s" add -A && git_v -C "$s" commit -q -m "chore: gegenereerd uit het template"
printf 'bestel.max-items=10\n' >> "$s/src/main/resources/application.properties"
vervang "$s/chart/values.yaml" "replicaCount: 1" "replicaCount: 3"
vervang "$s/pom.xml" "    </dependencies>" "        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>
    </dependencies>"
cat > "$s/src/main/java/nl/voorbeeld/bestelservice/Bestellingen.java" <<'JAVA'
package nl.voorbeeld.bestelservice;

import java.util.List;

import org.springframework.stereotype.Component;

@Component
public class Bestellingen {

    public int aantalRegels(List<String> regels) {
        System.out.println("aantal regels: " + regels.size());
        return regels.size();
    }
}
JAVA
git -C "$s" add -A && git_v -C "$s" commit -q -m "feat: max-items, 3 replica's, validation en Bestellingen"

# Rommel voor de wekelijkse opschoning (voorbeeld/opschoning.env); de nummers staan
# in voorbeeld/README.md.
cat > "$s/src/main/java/nl/voorbeeld/bestelservice/BestelService.java" <<'JAVA'
package nl.voorbeeld.bestelservice;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class BestelService {

    private static final Logger LOG = LoggerFactory.getLogger(BestelService.class);

    private final Bestellingen bestellingen;
    private int teller;

    @Autowired
    public BestelService(Bestellingen bestellingen) {
        this.bestellingen = bestellingen;
    }

    public boolean isLeeg(List<String> regels) {
        List<String> kopie = new ArrayList<String>(regels);
        int ongebruikt = 3;
        LOG.info("regels: " + kopie.size());
        if (kopie.isEmpty()) {
            return true;
        } else {
            return false;
        }
    }

    public String toString() {
        try {
            return "BestelService " + bestellingen.aantalRegels(List.of());
        } catch (RuntimeException e) {
            e.printStackTrace();
            return "BestelService";
        }
    }
}
JAVA
cat > "$s/src/test/java/nl/voorbeeld/bestelservice/BestelServiceTest.java" <<'JAVA'
package nl.voorbeeld.bestelservice;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;

import org.junit.jupiter.api.Test;

public class BestelServiceTest {

    private final BestelService service = new BestelService(new Bestellingen());

    @Test
    public void legeLijstIsLeeg() {
        assertTrue(service.isLeeg(List.of()));
    }

    @Test
    public void lijstMetRegelIsNietLeeg() {
        assertFalse(service.isLeeg(List.of("regel")));
    }
}
JAVA
git -C "$s" add -A && git_v -C "$s" commit -q -m "feat: BestelService"

# klant-service: met database en liquibase; past de logging aan (die later ook in het
# template verandert) en gebruikt een eigen databasehost
genereer '{"project_name": "Klant Service", "db": true, "liquibase": true}'
s="$DOEL/services/klant-service"
git -C "$s" init -q -b main && git -C "$s" add -A && git_v -C "$s" commit -q -m "chore: gegenereerd uit het template"
vervang "$s/src/main/resources/application.properties" "logging.level.root=INFO" "logging.level.root=DEBUG"
git -C "$s" add -A && git_v -C "$s" commit -q -m "chore: debug-logging"
vervang "$s/chart/values.yaml" "jdbc:postgresql://postgres:5432/klantservice" "jdbc:postgresql://klant-db:5432/klantservice"
git -C "$s" add -A && git_v -C "$s" commit -q -m "chore: eigen databasehost"
# klant-service gebruikt de gedeelde jar (nog als gewone dependency)
vervang "$s/pom.xml" "    </dependencies>" "        <dependency>
            <groupId>nl.voorbeeld</groupId>
            <artifactId>gedeelde-jar</artifactId>
            <version>1.0.0</version>
        </dependency>
    </dependencies>"
git -C "$s" add -A && git_v -C "$s" commit -q -m "feat: gebruikt de gedeelde jar"

# losse-service: geen template-service, wel afnemer van de gedeelde jar
s="$DOEL/services/losse-service"
mkdir -p "$s"
cat > "$s/pom.xml" <<'POM'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>nl.voorbeeld</groupId>
    <artifactId>losse-service</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <dependencies>
        <dependency>
            <groupId>nl.voorbeeld</groupId>
            <artifactId>gedeelde-jar</artifactId>
            <version>1.0.0</version>
        </dependency>
    </dependencies>
</project>
POM
git -C "$s" init -q -b main && git -C "$s" add -A && git_v -C "$s" commit -q -m "feat: losse service zonder template"

echo "voorbeeld opgezet in $DOEL"
echo "volgende stap: $HIER/wijzig-template.sh"
