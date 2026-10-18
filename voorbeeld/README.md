# Voorbeeld

Een cruft-template voor een Spring Boot-service met Helm-chart, en twee services die
eruit gegenereerd zijn, om migraties lokaal mee te oefenen. Alles draait lokaal: er is
geen GitLab nodig. Draai de commando's vanuit de map van migratie-tools.

## Overzicht

### Bestanden in deze map

| Bestand | Wat het is |
|---|---|
| `opzetten.sh` | Zet het voorbeeld op in `work/voorbeeld/`: de template-repo en de twee services. Gooit een vorige opzet weg, dus oude clones van het voorbeeld werken daarna niet meer |
| `wijzig-template.sh` | Voert de template-commits uit `wijzigingen/` door in de template-repo (één commit per patch, geen tags) |
| `template/` | Het cookiecutter-template: Spring Boot-service met Helm-chart, variabelen `db` en `liquibase` |
| `wijzigingen/` | Acht patches op het template, als conventional commits (zie hieronder); de laatste voegt de variabele `gedeelde_jar` toe |
| `gedeelde-jar/` | Een kleine jar (`nl.voorbeeld:gedeelde-jar`) die services gebruiken; `opzetten.sh` installeert hem in `~/.m2` |
| `cruft-update.env` | Voorbeeldmigratie: cruft update naar de nieuwste stand van het template |
| `gedeelde-jar.env` | Voorbeeldmigratie van een feature: gedeelde jar via een init container, alleen voor afnemers |
| `debug-opruimen.env` | Voorbeeldmigratie: recept `OpruimenDebugOutput` |
| `opschoning.env` | Voorbeeldmigratie: recept `WekelijkseOpschoning` |

### Wat `opzetten.sh` aanmaakt

| In `work/voorbeeld/` | Wat het is |
|---|---|
| `template/` | Git-repo van het template (branch `main`), zoals jullie centrale template-repo |
| `services/bestel-service` | Gegenereerd met `db`, met eigen aanpassingen die niet botsen met het template, en rommel voor de opschoning |
| `services/klant-service` | Gegenereerd met `db` en `liquibase`, met eigen aanpassingen die wél botsen met het template; afnemer van de gedeelde jar |
| `services/losse-service` | Geen template-service (geen `.cruft.json`), wel afnemer van de gedeelde jar |

### De services

| Service | Variabelen | Eigen aanpassingen | Bij de cruft update |
|---|---|---|---|
| bestel-service | `db` | `max-items`, 3 replica's, validation-dependency, klasse `Bestellingen` met `System.out.println`, `BestelService` en `BestelServiceTest` met rommel | Gaat zonder handwerk door alle acht template-commits; build groen |
| klant-service | `db`, `liquibase` | logging op `DEBUG`, eigen databasehost `klant-db`, dependency `gedeelde-jar` | Stopt bij "logging op warn" met een conflict in `application.properties`; daarna gaan de rest en de eigen databasehost goed samen |
| losse-service | – (geen template) | dependency `gedeelde-jar` | Niet van toepassing |

### De template-commits (`wijzigingen/`)

| Patch | Wat het template verandert | bestel-service | klant-service |
|---|---|---|---|
| `01-feat-actuator-en-health-probes` | actuator-dependency, management-properties, liveness- en readiness-probes | ✓ | ✓ |
| `02-chore-spring-boot-3.5.7` | Spring Boot 3.5.6 → 3.5.7 | ✓ | ✓ |
| `03-fix-logging-op-warn` | `logging.level.root` INFO → WARN | ✓ | conflict |
| `04-feat-resources-in-de-chart` | resources in `values.yaml` en `deployment.yaml` | ✓ | ✓ |
| `05-fix-datasource-pool-begrenzen` | `maximumPoolSize` in de datasource (alleen met `db`) | ✓ | ✓ |
| `06-feat-liquibase-gebruikt-de-datasource-url` | env van de liquibase-init container (alleen met `liquibase`) | alleen `.cruft.json` | ✓ |
| `07-feat-jib-voor-het-container-image` | jib-maven-plugin in de `pom.xml` | ✓ | ✓ |
| `08-feat-gedeelde-jar-via-een-init-container` | nieuwe variabele `gedeelde_jar` (standaard uit): Helm-helper, init container, volume, `extraClasspath` in jib | alleen `.cruft.json` | alleen `.cruft.json` (tot de variabele aangaat) |

### Oefeningen

| # | Wat | Commando | Wat je ziet |
|---|---|---|---|
| 1 | Opzetten | `voorbeeld/opzetten.sh && voorbeeld/wijzig-template.sh` | template met acht nieuwe commits, drie services op de eerste stand |
| 2 | Achterstand bekijken | `./achterstand.sh work/voorbeeld/services/*` | bestel- en klant-service acht template-commits achter (losse-service is geen template-service) |
| 3 | Cruft update uitproberen | `./uitproberen.sh voorbeeld/cruft-update.env work/voorbeeld/services/bestel-service work/voorbeeld/services/klant-service` | bestel-service "Gewijzigd" (acht commits), klant-service "Handwerk nodig" |
| 4 | Het conflict afmaken | zie "Een conflict afmaken" hieronder | het script wacht, jij lost op in IntelliJ, Enter, klaar |
| 5 | Een recept | `./uitproberen.sh voorbeeld/debug-opruimen.env work/voorbeeld/services/bestel-service` | de `println` in `Bestellingen` is weg |
| 6 | Wekelijkse opschoning | `./uitproberen.sh voorbeeld/opschoning.env work/voorbeeld/services/bestel-service` | tien soorten rommel opgeruimd (zie hieronder); een tweede keer: "Ongewijzigd" |
| 7 | Een variabele omzetten | zie "Een template-variabele omzetten" hieronder | init container en liquibase-sectie erbij |
| 8 | Een feature voor alle afnemers | zie "Een feature: de gedeelde jar" hieronder | alleen klant-service doet mee; bestel- en losse-service "Niet van toepassing" |
| 9 | Een eigen template-wijziging | pas `work/voorbeeld/template` aan, commit op `main`, herhaal 3 | jouw wijziging als extra commit per service |
| 10 | Alles via het menu | `./migratie.sh` | dezelfde acties, met keuzes in plaats van commando's |

Bekijk het resultaat van `uitproberen.sh` in `work/<service>` (bv.
`git -C work/bestel-service log -p`) of in `runs/<migratie>-<tijd>/debug/<service>/`.

## Een feature: de gedeelde jar

Afnemers van de gedeelde jar krijgen die voortaan bij het draaien via een init container,
in plaats van dat ze hem zelf meeleveren. Dat raakt zowel het template (init container,
volume, `extraClasspath` in jib, onder de variabele `gedeelde_jar`) als de service zelf
(de dependency wordt `provided`). `voorbeeld/gedeelde-jar.env` doet het in één migratie:

```bash
ALLEEN_MET_DEPENDENCY=gedeelde-jar            # alleen services die de jar gebruiken
CRUFT_UPDATE=ja                               # het template met de nieuwe variabele
CRUFT_ZET='gedeelde_jar=true'                 # de variabele aan: init container, volume, jib
RECEPT=local.migratietools.GedeeldeJarProvided  # de dependency op provided
```

```bash
./uitproberen.sh voorbeeld/gedeelde-jar.env work/voorbeeld/services/*
```

bestel-service ("gebruikt gedeelde-jar niet") en losse-service ("afnemer zonder template")
doen niet mee. klant-service stopt eerst bij het bekende logging-conflict; maak hem af
zoals hieronder, dan volgen de template-commits, `feat(cruft): gedeelde_jar aangezet` en
`chore(recept): …GedeeldeJarProvided`, en een groene build. Services zonder de variabele
krijgen de Helm-helper `_gedeelde-jar.tpl` niet: een hook in het template haalt hem weg.

## Een conflict afmaken

`uitproberen.sh` laat alleen zien waar het stopt (in `work/klant-service`). Afmaken doe
je in een eigen clone, zoals met een project in IntelliJ:

```bash
git clone work/voorbeeld/services/klant-service /tmp/klant-service
cd /tmp/klant-service
/pad/naar/migratie-tools/in-repo.sh /pad/naar/migratie-tools/voorbeeld/cruft-update.env
```

(Of met `voorbeeld/gedeelde-jar.env` voor de feature.) Het script wacht bij het conflict: open `/tmp/klant-service` in IntelliJ, kies *Git →
Resolve Conflicts…*, kies in `application.properties` een waarde, klik *Apply* en druk in
de terminal op Enter. De rest van de template-commits volgt; de eigen databasehost
(`klant-db`) blijft staan naast de nieuwe `maximumPoolSize`.

## De template-variabelen

Het template heeft twee variabelen die per service in `.cruft.json` staan:

| Variabele | Effect in de service |
|---|---|
| `db` | sectie `datasource` in `values.yaml`, datasource-env in `deployment.yaml` |
| `liquibase` | sectie `liquibase` in `values.yaml`, init container in `deployment.yaml` |
| `gedeelde_jar` | sectie `gedeeldeJar` in `values.yaml`, init container, volume en mount in `deployment.yaml`, Helm-helper `_gedeelde-jar.tpl`, `extraClasspath` in jib (vanaf template-commit 08) |

Cookiecutter rendert de if-blokken weg: in de services staat gewone YAML, zonder Jinja en
zonder Helm-`if`'s voor dingen die ze niet hebben. Daarom wordt `deployment.yaml` wél door
cookiecutter gerenderd; de Helm-expressies staan in het template tussen `{% raw %}`.
De andere Helm-templates in `chart/templates/` worden niet gerenderd
(`_copy_without_render`), omdat ze zelf `{{ }}` gebruiken.

## Een template-variabele omzetten

Een variabele achteraf omzetten doe je met `cruft-zet.sh`, niet door `.cruft.json` met de
hand aan te passen (dan voegt de cruft update niets toe). Bijvoorbeeld liquibase aanzetten
bij bestel-service:

```bash
git clone work/voorbeeld/services/bestel-service /tmp/bestel-service && cd /tmp/bestel-service
/pad/naar/migratie-tools/cruft-zet.sh liquibase=true
git show    # liquibase-sectie in values.yaml en de init container in deployment.yaml
```

Uitzetten geeft een conflict als de service de init container zelf heeft aangepast; dat
los je op zoals bij de cruft update: oplossen in IntelliJ en Enter in de terminal.

## De rommel voor de wekelijkse opschoning

bestel-service heeft rommel in `BestelService` en `BestelServiceTest`:

| Rommel in de service | Recept |
|---|---|
| ongebruikte imports (`Map`, en `Autowired` na het weghalen) | `RemoveUnusedImports` |
| ongebruikt privéveld `teller` | `RemoveUnusedPrivateFields` |
| `@Autowired` op de enige constructor | `NoAutowiredOnConstructor` |
| `new ArrayList<String>(…)` | `UseDiamondOperator` |
| ongebruikte variabele `ongebruikt` | `RemoveUnusedLocalVariables` |
| `LOG.info("regels: " + …)` | `ParameterizedLogging` |
| `if (…) return true; else return false;` | `SimplifyBooleanReturn` |
| `toString()` zonder `@Override` | `MissingOverrideAnnotation` |
| `e.printStackTrace()` | `PrintStackTraceToLogError` |
| `public` testklasse en testmethodes | `JUnit5BestPractices` |
