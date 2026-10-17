#!/usr/bin/env bash
# De module recepten/ (wordt gesourced door run.sh en local.sh).

RECEPTEN_ARTEFACT="local.migratietools:recepten:1.0-SNAPSHOT"

# Een recept uit een migratie moet in recepten/ staan (YAML of Java) en een test hebben.
controleer_recept() {  # <root> <recept>
  local dir="$1/recepten/src" naam="$2" kort="${2##*.}"
  if ! grep -rqE "^name: *${naam//./\\.} *$" "$dir/main/resources/META-INF/rewrite" 2>/dev/null \
     && [ ! -f "$dir/main/java/${naam//.//}.java" ]; then
    echo "recept $naam staat niet in recepten/ (YAML of Java); publieke recepten roep je aan vanuit een YAML-recept" >&2
    exit 2
  fi
  if ! grep -rqE "\"$naam\"|new $kort\(" "$dir/test" 2>/dev/null; then
    echo "recept $naam heeft geen test in recepten/src/test" >&2
    exit 2
  fi
}

# Bouwt en installeert de recepten in de lokale Maven-repository, mét tests.
# Een rode test stopt de run voordat er een service is aangeraakt.
bouw_recepten() {  # <root>
  echo ">> recepten bouwen en testen"
  if ! mvn -B -q -f "$1/recepten/pom.xml" install; then
    echo "de recepten bouwen of testen niet; de run gaat niet door" >&2
    exit 2
  fi
}
