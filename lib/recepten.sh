#!/usr/bin/env bash
# De recepten (wordt gesourced door de scripts in de root en door transformaties/recept.sh).
#
# Er is altijd de ingebouwde module recepten/ van migratie-tools. Met RECEPTEN_MAP komt er
# een eigen Maven-module bij (bv. uit een interne repo van je organisatie); die wordt ook
# gebouwd en gaat ook naar de OpenRewrite-plugin, zodat eigen recepten de ingebouwde
# kunnen aanroepen. Gebruik in een eigen module dezelfde rewrite-recipe-bom als recepten/.

RECEPTEN_ARTEFACT="local.migratietools:recepten:1.0-SNAPSHOT"

recepten_modules() {  # <root>: de modules met recepten, één per regel
  echo "$1/recepten"
  if [ -n "${RECEPTEN_MAP:-}" ]; then echo "$RECEPTEN_MAP"; fi
}

# Een recept uit een migratie moet in een van de modules staan (YAML of Java) en daar een
# test hebben.
controleer_recept() {  # <root> <recept>
  local naam="$2" kort="${2##*.}" m
  if [ -n "${RECEPTEN_MAP:-}" ] && [ ! -f "$RECEPTEN_MAP/pom.xml" ]; then
    echo "RECEPTEN_MAP=$RECEPTEN_MAP is geen Maven-module (geen pom.xml)" >&2
    exit 2
  fi
  while IFS= read -r m; do
    if grep -rqE "^name: *${naam//./\\.} *$" "$m/src/main/resources/META-INF/rewrite" 2>/dev/null \
       || [ -f "$m/src/main/java/${naam//.//}.java" ]; then
      if ! grep -rqE "\"$naam\"|new $kort\(" "$m/src/test" 2>/dev/null; then
        echo "recept $naam heeft geen test in $m/src/test" >&2
        exit 2
      fi
      return 0
    fi
  done < <(recepten_modules "$1")
  echo "recept $naam staat niet in $(recepten_modules "$1" | paste -sd, - | sed 's/,/ of /g') (YAML of Java);" \
       "publieke recepten roep je aan vanuit een YAML-recept" >&2
  exit 2
}

mvn_waarde() {  # <module> <expressie>: één waarde uit het model van de module
  mvn -B -q -f "$1/pom.xml" help:evaluate -DforceStdout -Dexpression="$2"
}

# Bouwt en installeert de recepten in de lokale Maven-repository, mét tests, en zet in
# RECEPTEN_ARTEFACTEN welke artefacten de OpenRewrite-plugin moet laden. Een rode test
# stopt de run voordat er een service is aangeraakt.
bouw_recepten() {  # <root>
  local m coordinaat
  RECEPTEN_ARTEFACTEN=""
  while IFS= read -r m; do
    echo ">> recepten bouwen en testen: $m"
    if ! mvn -B -q -f "$m/pom.xml" install; then
      echo "de recepten in $m bouwen of testen niet; de run gaat niet door" >&2
      exit 2
    fi
    if [ "$m" = "$1/recepten" ]; then
      coordinaat="$RECEPTEN_ARTEFACT"
    else
      coordinaat="$(mvn_waarde "$m" project.groupId):$(mvn_waarde "$m" project.artifactId):$(mvn_waarde "$m" project.version)"
    fi
    RECEPTEN_ARTEFACTEN+="${RECEPTEN_ARTEFACTEN:+,}$coordinaat"
  done < <(recepten_modules "$1")
  export RECEPTEN_ARTEFACTEN
}
