#!/usr/bin/env bash
# Gedeelde hulpfuncties voor de stappen (wordt gesourced, niet los uitgevoerd).

# Gebruik de Maven wrapper als de repo er een heeft, anders de globale mvn.
mvn_cmd() {
  if [ -x ./mvnw ]; then echo "./mvnw"; else echo "mvn"; fi
}

# Stop (exit 1 = repo overslaan) als het geen Maven-project is.
require_pom() {
  if [ ! -f pom.xml ]; then
    echo "geen pom.xml, overgeslagen"
    exit 1
  fi
}
