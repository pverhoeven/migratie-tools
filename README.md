# migratie-tools

Rolt migraties uit over de services in een GitLab-groep: eerst lokaal op een paar
services, daarna met multi-gitter over de hele groep, met per service een eigen PR.
Begrippen staan in [GLOSSARY.md](GLOSSARY.md), besluiten in [docs/adr](docs/adr).

## Overzicht van de scripts

### Wat je zelf gebruikt

| Script | Waarvoor | Werkt in | Pusht / MR | GitLab nodig |
|---|---|---|---|---|
| `migratie.sh` | Menu: kies een actie en een migratie (of maak een nieuwe), bevestig branch en PR-titel; start daarna een van de scripts hieronder | – | via het gekozen script | alleen voor de groep en de achterstand |
| `in-repo.sh` | Een migratie in je eigen clone draaien, ook om handwerk af te maken; wacht bij een conflict of rode build tot je het hebt opgelost (Enter) | je eigen clone | nee, dat doe je zelf | nee |
| `uitproberen.sh` | Zandbak: zien wat een migratie doet op een of meer services | verse clones in `work/` | nooit | nee |
| `run.sh` | Een migratie over de hele GitLab-groep (via multi-gitter); standaard een dry-run, met `--go` echt | tijdelijke clones | met `--go`: per service een MR | ja |
| `cruft-zet.sh` | Een template-variabele omzetten in één service, bv. `liquibase=true`; wacht bij een conflict | je eigen clone | nee, dat doe je zelf | nee |
| `achterstand.sh` | Per template-service: op welke stand van het template hij zit en hoeveel template-commits hij achterloopt; wijzigt niets | – | nee | alleen voor de hele groep |
| `status.sh` | Na de uitrol: per service de MR van een migratie (gemerged, open met pipeline, gesloten) en wie nog geen MR heeft; wijzigt niets | – | nee | ja |

Wanneer welke:

1. Nieuwe migratie: eerst `uitproberen.sh` (of een dry-run van `run.sh`) om te zien wat
   ze doet; de patches staan per service in `runs/…/debug/`.
2. Uitrollen: `run.sh --go` op twee of drie services (`--repo-include`), mergen, dan de
   hele groep.
3. Handwerk op de werklijst: `in-repo.sh` in je eigen clone van die service.
4. Een service die een onderdeel van het template erbij wil (of kwijt): `cruft-zet.sh`.
5. Twijfel waar je staat: `achterstand.sh`.
6. Na de uitrol: `status.sh <migratie>` tot alles gemerged is.

Of start gewoon `migratie.sh`; dat vraagt het allemaal en toont het commando dat het draait.

### Bouwstenen (worden door de scripts hierboven aangeroepen)

| Bestand | Wat het doet |
|---|---|
| `repo-runner.sh` | Draait één migratie in één service: bepaalt of ze van toepassing is, draait de transformaties en de controle en geeft de uitkomst (Gewijzigd, Ongewijzigd, Niet van toepassing, Handwerk nodig) |
| `transformaties/cruft-update.sh` | De cruft update: bijwerken naar de nieuwste stand van het template, commit voor commit, met echte git-conflicten (ADR 0004) |
| `transformaties/cruft-zet.sh` | Een template-variabele omzetten in één service; gebruikt door `CRUFT_ZET` en door `cruft-zet.sh` (ADR 0005) |
| `transformaties/recept.sh` | Eén OpenRewrite-recept uit `recepten/` draaien via de Maven-plugin |
| `transformaties/dependency-versie.sh` | Dependency-versies ophogen met standaardrecepten van OpenRewrite (`DEPENDENCY_VERSIE`) |
| `controles/verify.sh` | Build en tests (`mvn verify`); draait daarna alles terug wat de build wijzigde |
| `lib/template.sh` | Het template genereren en 3-way mergen; gedeeld door de cruft update en `cruft-zet.sh` |
| `lib/render-template.py` | Genereert één stand van het template zoals cruft dat doet (gebruikt cruft 2.16.0) |
| `lib/migratie.sh` | Migratiebestand laden, branch starten, handwerk hervatten en erop wachten, PR-beschrijving |
| `lib/recepten.sh` | Recept controleren (bestaat, heeft een test) en `recepten/` bouwen en installeren |
| `lib/gitlab.sh` | GitLab-API: open MR's, de projecten van de groep, de MR's van een migratie en hun pipeline |
| `lib/samenvatting.sh` | Het overzicht per uitkomst aan het eind van een run |
| `lib/opruimen.sh`, `lib/common.sh` | `target/` opruimen; algemene hulpfuncties |
| `jenkins/gereedschap.sh` | Installeert cruft, multi-gitter en jq zonder Docker (voor de `Jenkinsfile`) |
| `Jenkinsfile` | Pipeline: `run.sh` in Jenkins, en optioneel wekelijks de opschoning |
| `voorbeeld/opzetten.sh`, `voorbeeld/wijzig-template.sh` | Het voorbeeld opzetten en het template laten veranderen (zie `voorbeeld/README.md`) |

### Mappen

| Map | Inhoud |
|---|---|
| `migraties/` | De migraties, één bestand per migratie (`<naam>.env`); `_voorbeeld.env` legt elke regel uit; `cruft-update.env` en `opschoning.env` zijn sjablonen voor terugkerende Jenkins-jobs |
| `recepten/` | Maven-module met de OpenRewrite-recepten (YAML en Java) en hun tests |
| `runs/` | Per run de resultaten en de debug-uitvoer (niet in git) |
| `work/` | De clones van `uitproberen.sh` en het voorbeeld (niet in git) |
| `docs/adr/` | De besluiten; begrippen staan in `GLOSSARY.md` |
| `docs/uitbreidingen.md` | Ideeën voor uitbreidingen, met hun status |
| `voorbeeld/` | Een voorbeeld-template (Spring Boot met Helm-chart) en twee services om mee te oefenen |

Een migratie bestaat uit een cruft update en/of één OpenRewrite-recept, gevolgd
door de controle `verify` (build en tests). Elke transformatie commit haar eigen
wijzigingen; de cruft update maakt één commit per template-commit. Alle commits zijn
[conventional commits](https://www.conventionalcommits.org/): een template-commit
`fix: logging op warn` wordt in de service `fix(cruft): logging op warn (777021d)`
(geen conventional commit in het template: `chore(cruft): …`), een recept wordt
`chore(recept): <recept>` en de PR-titel `chore(migratie): <migratie>`.

## Voorbereiding

Nodig: `git`, `jq`, [cruft](https://cruft.github.io/cruft/) 2.16.0, Java en Maven
(of een `mvnw` in de service). Voor `run.sh` ook
[multi-gitter](https://github.com/lindell/multi-gitter).

```bash
pipx install cruft==2.16.0
```

Gebruik precies deze cruft-versie: de cruft update gebruikt een interne functie van
cruft (`lib/render-template.py`) en is alleen met 2.16.0 getest. Test een nieuwere versie
eerst met het voorbeeld (`voorbeeld/README.md`) voordat je hem ophoogt.

```bash
cp config.env.example config.env   # GitLab- en Maven-instellingen
```

## Het menu

```bash
./migratie.sh
```

Het menu vraagt wat je wilt doen (migratie in een repo, lokaal op clones, over de hele
groep, een template-variabele omzetten of de achterstand bekijken) en welke migratie: een
bestaande uit `migraties/`, een nieuwe (cruft update en/of een recept uit `recepten/`) of
een ander migratiebestand. Daarna stelt het de branch en de PR-titel voor; wat je
aanpast, komt in het migratiebestand. Het toont het commando dat het uitvoert, zodat je
het ook zonder menu kunt draaien. Bij de hele groep doet het eerst een dry-run en vraagt
het daarna of het echt moet (`--go`).

## Een migratie maken

Kopieer `migraties/_voorbeeld.env` naar `migraties/<naam>.env` (of gebruik het menu).
Elke regel betekent één ding:

| Regel | Betekenis |
|---|---|
| `ALLEEN_MET_DEPENDENCY=gedeelde-jar` | optioneel: alleen services met deze dependency (artifactId) in een `pom.xml` doen mee; de rest krijgt "Niet van toepassing". Zonder deze regel: alle services |
| `CRUFT_UPDATE=ja` | het template bijwerken naar de nieuwste stand (cruft update) |
| `CRUFT_ZET='gedeelde_jar=true'` | een of meer template-variabelen omzetten (zoals `cruft-zet.sh`), gescheiden door spaties |
| `RECEPT=local.migratietools.…` | één OpenRewrite-recept uit `recepten/` |
| `DEPENDENCY_VERSIE='groep:artifact:versie'` | dependency-versies ophogen, direct en indirect, bv. bij een kwetsbaarheid (zie "Een kwetsbaarheid"); een of meer, gescheiden door spaties |
| `BRANCH=…`, `PR_TITEL='…'` | optioneel; standaard `migratie/<naam>` en `chore(migratie): <naam>` |

Minstens één van `CRUFT_UPDATE`, `CRUFT_ZET`, `RECEPT` en `DEPENDENCY_VERSIE`; ze draaien in deze volgorde, met
daarna de controle `verify`. Een feature die zowel het template als de code van de
services raakt, is zo één migratie, bv. (zie `voorbeeld/gedeelde-jar.env`):

```bash
# Gedeelde jar via een init container, voor alle services die hem gebruiken.
ALLEEN_MET_DEPENDENCY=gedeelde-jar
CRUFT_UPDATE=ja
CRUFT_ZET='gedeelde_jar=true'
RECEPT=local.migratietools.GedeeldeJarProvided
```

Een afnemer die geen template-service is, krijgt hierbij "Niet van toepassing" met de
reden "afnemer zonder template"; die werk je met de hand af.

De PR-beschrijving bevat de inhoud van het migratiebestand en de commit van
migratie-tools, dus de PR legt zelf vast wat er is uitgerold; committen hoeft niet.
Commit het bestand wel als de migratie later (door iemand anders) herhaald wordt. Geef de
migratie een naam die past bij wat er gebeurt, bv. `cruft-update-2026-10` of
`spring-boot-3.5`.

## Recepten

Recepten staan in de module `recepten/`: YAML in `src/main/resources/META-INF/rewrite/`,
Java in `src/main/java/`. Een migratie verwijst naar precies één recept uit deze module;
publieke recepten (bv. uit `rewrite-spring`, als dependency in `recepten/pom.xml`) roep
je aan vanuit een YAML-recept. Elk recept heeft minstens één before/after-test
(`RewriteTest`). Aan het begin van een run met een recept wordt de module gebouwd en
lokaal geïnstalleerd, mét tests; een rode test stopt de run.

De versie van `rewrite-maven-plugin` staat in `recepten/pom.xml` en moet bij de
`rewrite-recipe-bom` passen (zelfde rewrite-versie). De publieke receptmodules
(`rewrite-spring`, `rewrite-static-analysis`, `rewrite-logging-frameworks`,
`rewrite-testing-frameworks`) vallen onder de Moderne Source Available License.

Beschikbare recepten:

| Recept | Waarvoor |
|---|---|
| `local.migratietools.WekelijkseOpschoning` | kleine, idempotente opschoning om wekelijks te draaien: ongebruikte imports, velden, methodes en variabelen, omslachtige booleans, diamond-operator, `@Override`, geparametriseerde SLF4J-logregels, `printStackTrace` naar de logger, JUnit 5-opschoning, overbodige `@Autowired` op constructors |
| `local.migratietools.OpruimenDebugOutput` | voorbeeld: `System.out.println` weg |
| `local.migratietools.GedeeldeJarProvided` | voorbeeld van een feature: de dependency `nl.voorbeeld:gedeelde-jar` op `provided` (samen met `CRUFT_ZET='gedeelde_jar=true'`) |
| `local.migratietools.VoorbeeldKwetsbaarheidTomcat` | voorbeeld van een kwetsbaarheid als vast recept: `tomcat-embed-core` naar 10.1.61, direct en indirect (zie "Een kwetsbaarheid") |

Recepten en migraties van je eigen organisatie (eigen groupId's, interne namen) horen
niet in deze publieke repo; zie "Eigen migraties en recepten".

Voor een wekelijkse opschoning maak je elke week een migratiebestand, bv.
`migraties/opschoning-2026-w42.env` met `RECEPT=local.migratietools.WekelijkseOpschoning`.
Een service waarin niets op te ruimen valt, krijgt geen MR. Grotere of opiniërende
recepten (Spring Boot-upgrades, AssertJ, `CommonStaticAnalysis`, `AutoFormat`) draai je
als losse migratie; een Spring Boot-upgrade bij template-services samen met
`CRUFT_UPDATE=ja` (het template hoogt de parent op, het recept past de code aan).

## Een kwetsbaarheid

Bij een kwetsbaarheid in een dependency hoog je de versie op met één regel in een
migratie, zonder eigen recept:

```bash
# migraties/cve-2026-12345.env
DEPENDENCY_VERSIE='org.apache.tomcat.embed:tomcat-embed-core:10.1.61'
PR_TITEL='fix(deps): tomcat-embed-core naar 10.1.61 (CVE-2026-12345)'
```

Per dependency draaien twee standaardrecepten van OpenRewrite: `UpgradeDependencyVersion`
als de service de dependency zelf noemt (ook met een versie uit een property,
`dependencyManagement` of een parent of BOM, die dan een eigen `<version>` krijgt) en
`UpgradeTransitiveDependencyVersion` als hij er indirect in komt (de versie komt dan in
`dependencyManagement`, met de naam van de migratie erbij). Beide doen alleen iets waar de
versie lager is. Daarna draait verify; elke service krijgt één commit
`fix(deps): tomcat-embed-core naar 10.1.61`.

1. **Wie is geraakt?** Een dry-run (`run.sh` zonder `--go`, of in Jenkins met GO uit) is
   het rapport: Gewijzigd = geraakt (de patch in `runs/…/debug/` toont de oude versie),
   Ongewijzigd = niet geraakt of al veilig, Handwerk nodig = geraakt, maar de build is rood
   na het ophogen (bv. een major-versie).
2. **Repareren:** dezelfde migratie met `--go`.
3. **Opvolgen:** `status.sh <migratie>` tot alles gemerged is.

Komt de versie uit het template (bv. de Spring Boot-parent), dan is een template-wijziging
met een cruft update de nette oplossing; een versie die in de service vastligt, kan bij
een latere cruft update botsen. Voor een spoedgeval is de migratie prima, de fix hoort
daarna in het template.

### Als vast recept

Wil je de oplossing vastleggen met een test, of combineren met andere stappen (bv. een
API die verandert met de nieuwe versie), maak dan een recept in `recepten/` met dezelfde
twee standaardrecepten en gebruik dat met `RECEPT=`. Het voorbeeld staat in
`recepten/src/main/resources/META-INF/rewrite/kwetsbaarheden.yml`
(`local.migratietools.VoorbeeldKwetsbaarheidTomcat`) met de test
`VoorbeeldKwetsbaarheidTomcatTest`; kopieer het en zet het CVE-nummer in de naam. Voor
spoed is `DEPENDENCY_VERSIE` sneller: geen recept en geen test. Een kwetsbaarheid in een
interne library hoort in je eigen receptenmodule (`RECEPTEN_MAP`), niet in deze repo.

## Eigen migraties en recepten

Migraties en recepten van je eigen organisatie zet je in een eigen (interne) repo, naast
migratie-tools, zonder een kopie van de tool te onderhouden:

```
intern/
  migraties/<naam>.env   eigen migraties
  recepten/              eigen Maven-module met recepten (eigen groupId)
```

In `config.env`:

```bash
MIGRATIES_MAP=/pad/naar/intern/migraties
RECEPTEN_MAP=/pad/naar/intern/recepten
```

Een naam van een migratie wordt dan eerst in `MIGRATIES_MAP` gezocht en daarna in
`migraties/`; het menu toont beide en zet nieuwe migraties in `MIGRATIES_MAP`. Bij een run
met een recept worden beide modules gebouwd (mét tests) en krijgt de OpenRewrite-plugin ze
allebei, zodat een eigen recept ook de ingebouwde kan aanroepen (bv.
`local.migratietools.WekelijkseOpschoning`). Voor de eigen module:

- gebruik dezelfde `rewrite-recipe-bom` als `recepten/` (de plugin-versie komt uit
  `recepten/pom.xml`);
- wil je ingebouwde recepten gebruiken in je tests, neem dan
  `local.migratietools:recepten:1.0-SNAPSHOT` op als dependency (wordt vóór je eigen
  module gebouwd en lokaal geïnstalleerd);
- geef elk recept een test; voor een dependency die niet in Maven Central staat, met een
  eigen mini-repository in de testresources (zie `GedeeldeJarProvidedTest`).

In Jenkins zet je `MIGRATIE_EIGEN_REPO` (en eventueel `MIGRATIE_EIGEN_BRANCH` en
`MIGRATIE_EIGEN_CREDENTIALS`); de pipeline checkt die repo uit en stelt beide mappen in.

## Uitproberen

```bash
./uitproberen.sh cruft-update-2026-10 ~/code/service-a ~/code/service-b
git -C work/service-a log -p origin/HEAD..HEAD
```

`uitproberen.sh` is een zandbak: het kloont elke service vers naar `./work/<naam>`,
draait de migratie op de branch van de migratie en pusht nooit. Het werkt zonder
GitLab (lokale paden of git-URL's), dus ook voordat je een token hebt. `work/` wordt bij
elke run opnieuw gekloond. Niet-gecommitte wijzigingen in je eigen repo worden niet
meegenomen. Met `--zonder-verify` (vóór de migratie) sla je de build over. Echt
uitrollen doe je met `run.sh` (MR's voor de groep) of `in-repo.sh` (je eigen clone).

## cruft update en conflicten

De transformatie cruft update doet wat `cruft update` doet: van de template-commit in
`.cruft.json` naar de nieuwste commit van het template, met de context van de service.
Alleen loopt hij de commits van het template één voor één af en merget hij elk bestand
3-way (basis = vorige stand van het template, ours = de service, theirs = de volgende
stand). Het commando `cruft update` zelf gebruiken we niet: dat past alles als één
patch toe en geeft bij conflicten `.rej`-bestanden (zie docs/adr/0004). Bij een
conflict stopt hij bij die template-commit, met conflictmarkers in de
bestanden (inclusief de basis). De conflicten staan ook als echte git-conflicten in de
index (basis, service, template), zodat je ze in je IDE 3-way kunt mergen. Elke
template-commit wordt een eigen commit in de service.

### Een template-branch uitproberen

Een wijziging in het template probeer je uit vóór die gemerged is: push hem naar een
branch van de template-repo en geef die mee als `TEMPLATE_REF` (een branch of commit).
De cruft update gaat dan naar die branch in plaats van naar de standaardbranch:

```bash
TEMPLATE_REF=feature/mijn-wijziging ./uitproberen.sh cruft-update ~/code/service-a ~/code/service-b
```

Stopt een service op een commit van jouw branch, dan veroorzaakt jouw wijziging het
conflict; stopt hij eerder, dan zat de service al vast. Services van een ander template
(waar jouw branch niet in staat) krijgen "Niet van toepassing", dus je kunt over alle
services draaien. Doet er geen enkele service mee, controleer dan de branchnaam. `run.sh --go` weigert
`TEMPLATE_REF`: MR's horen bij de standaardbranch van het template.

## In je eigen clone

Heb je de service al als project open, draai de migratie dan direct in die clone:

```bash
cd ~/code/service-a                        # schone werkmap, bijgewerkte main
~/migratie-tools/in-repo.sh cruft-update   # naam (migraties/<naam>.env) of pad
git push -u origin migratie/cruft-update   # en open de MR zelf
```

`in-repo.sh` maakt de branch van de migratie vanaf je huidige commit en weigert bij
een vuile werkmap (de controle draait alles terug wat de build wijzigt). Er wordt nooit
gepusht.

Bij handwerk wacht het in de terminal. Het laat zien wat er aan de hand is (welke
bestanden een conflict hebben, of dat de build rood is) en wat je moet doen. Los het op,
bv. in IntelliJ met *Git → Resolve Conflicts…*, en druk op Enter: het controleert of het
echt opgelost is (geen conflicten of conflictmarkers meer; bij een rode build: er is iets
aangepast), commit je oplossing en gaat verder, tot het volgende conflict of tot het
klaar is. Met `q` stop je; later ga je verder met `in-repo.sh --verder <migratie>`.
Met `--niet-wachten` (of zonder terminal, bv. op Jenkins) stopt het meteen bij handwerk.
`cruft-zet.sh` werkt hetzelfde.

Conflicten los je op in IntelliJ (*Git → Resolve Conflicts…*); het script draai je gewoon
in de terminal, bv. die van IntelliJ (⌥F12). Met een alias in je shell-profiel hoef je het
pad niet te typen:

```bash
alias migratie=~/Developer/code/migratie-tools/in-repo.sh
migratie cruft-update
```

## Een template-variabele omzetten

Template-variabelen (bv. `db`, `liquibase`) staan per service in `.cruft.json`. Een
variabele achteraf omzetten doe je in je eigen clone met `cruft-zet.sh`:

```bash
cd ~/code/klant-service                        # schone werkmap, bijgewerkte main
~/migratie-tools/cruft-zet.sh liquibase=true   # branch migratie/cruft-zet-liquibase
# conflict? los op in IntelliJ, daarna:
~/migratie-tools/cruft-zet.sh --verder
git push -u origin migratie/cruft-zet-liquibase # MR met labels migratie, cruft-zet
```

Het template blijft op dezelfde commit; de service krijgt alleen het effect van de
variabele (aan: de onderdelen erbij, uit: de onderdelen weg), met dezelfde 3-way-merge
als de cruft update. Heeft de service die onderdelen zelf aangepast, dan krijg je een
conflict. Private, afgeleide en "bron"-variabelen (zoals `project_name`) worden geweigerd;
een boolean accepteert alleen `true` of `false`. Zie docs/adr/0005.

## Handwerk nodig

Een service met de uitkomst "Handwerk nodig" (conflict of rode build) krijgt geen PR.
Maak hem af in je eigen clone met `in-repo.sh` (zie "In je eigen clone"): het stopt bij
het conflict, wacht tot je het hebt opgelost en gaat na Enter verder. Push daarna en open
zelf de MR, met de labels `migratie` en `<naam van de migratie>`.

Conflicten oplossen in IntelliJ: kies *Git → Resolve Conflicts…* (de bestanden staan ook
in het Commit-venster onder *Merge Conflicts*). In het merge-venster is links de service
(*Yours*), rechts het template (*Theirs*) en in het midden het resultaat, met de vorige
stand van het template als basis. Klaar met *Apply*, dan Enter in de terminal. Op de
commandoregel kan het ook, bv. met `git checkout --theirs -- <bestand>` (template) of
`--ours` (service) en `git add`.

## Over een hele GitLab-groep (multi-gitter)

```bash
./run.sh migraties/template-2026-10.env                                  # dry-run
./run.sh migraties/template-2026-10.env --go --repo-include 'service-(a|b)'
./run.sh migraties/template-2026-10.env --go                             # de rest
```

Een herhaalde run slaat services over die de branch van de migratie al hebben.
Subgroepen van de groep doen mee. Extra multi-gitter-flags geef je achteraan mee
(`--repo-include`, ...).

Vóór de run vraagt `run.sh` bij GitLab de open MR's met label `migratie` op. Een service
met een open MR van een *andere* migratie (herkend aan het label met de naam van de migratie) doet niet mee en krijgt de uitkomst
"Wacht op vorige migratie"; een latere run pakt hem op. Repo's op de `UITSLUITLIJST`
(`config.env`) doen nooit mee.

Elke run schrijft `runs/<migratie>-<tijd>/resultaten.tsv` en toont aan het eind de
uitkomst per service, met de werklijst (Handwerk nodig) bovenaan. Per service één regel,
met tabs: service, uitkomst, reden en stop-commit. De stop-commit is de volledige
template-commit waar de cruft update op een conflict stopte, en anders leeg; zo zie je
bij een [template-branch](#een-template-branch-uitproberen) of het conflict op jouw
branch zit of al op de standaardbranch.

Om een (dry-)run na te kijken staat per service in `runs/<migratie>-<tijd>/debug/<service>/`:

| Bestand | Inhoud |
|---|---|
| `wijzigingen.patch` | de commits van de migratie, met boodschap (`git format-patch`; toe te passen met `git am`) |
| `onafgemaakt.diff`, `status.txt` | bij Handwerk nodig: de stand waarin de migratie stopte, met de conflictmarkers |
| `uitvoer.log` | de volledige uitvoer van de migratie voor die service (multi-gitter toont die niet) |

Dat geldt voor `run.sh` (ook de dry-run) en `uitproberen.sh`.

## Achterstand

```bash
./achterstand.sh                       # alle template-services in GITLAB_GROUP
./achterstand.sh ~/code/service-a      # of lokale repo's
```

Toont per template-service op welke template-commit hij zit en hoeveel commits van het
template hij achterloopt, de grootste achterstand bovenaan. Handig vóór je een nieuwe
template-migratie start: services die ver achterlopen krijgen meer kans op conflicten.

## Status na de uitrol

```bash
./status.sh cruft-update-2026-10
```

Een migratie is pas klaar als alle MR's gemerged zijn. `status.sh` vraagt bij GitLab de
MR's van de migratie op (labels `migratie` en de naam van de migratie, in elke toestand;
per service de nieuwste) en toont ze per groep, de werklijst bovenaan:

| Groep | Wat te doen |
|---|---|
| Open, conflict met de doelbranch | de MR bijwerken (bv. rebasen) |
| Open, pipeline rood | de build van de service repareren |
| Geen MR | handwerk of wachtend volgens de laatste run in `runs/<migratie>-*/`; afmaken met `in-repo.sh` |
| Open, pipeline loopt of ontbreekt; Open, pipeline groen | reviewen en mergen; per MR staat erbij hoelang hij open is |
| Gesloten zonder merge | bewust afgewezen, of opnieuw uitrollen |

Bovenaan staat hoeveel MR's al gemerged zijn. Nodig: `GITLAB_TOKEN` en `GITLAB_GROUP`
(zoals bij `run.sh`). Services zonder MR kent het alleen als de run in deze map staat; in
Jenkins staat `runs/` in de artefacten van de build.

## Jenkins

De `Jenkinsfile` draait `run.sh` op een Linux-agent (`agent any`), zonder Docker. De
tools (cruft 2.16.0, multi-gitter, jq) installeert `jenkins/gereedschap.sh` in
`~/.cache/migratie-tools` op de agent, met vaste versies en gecontroleerde downloads;
daarna wordt er niets meer gedownload. De workspace wordt na elke build opgeruimd.

De `Jenkinsfile` bevat geen instellingen van een organisatie. Die zet je in Jenkins zelf,
bv. als *folder properties* op de map van de job of als globale eigenschappen:

| Variabele | Verplicht | Wat |
|---|---|---|
| `GITLAB_GROUP` | ja | GitLab-groep met de services |
| `GITLAB_BASE_URL` | bij self-hosted GitLab | URL van GitLab |
| `MIGRATIE_GITLAB_CREDENTIALS` | ja | id van een *Secret text*-credential: GitLab-token met api-rechten op de groep |
| `MIGRATIE_TEMPLATE_CREDENTIALS` | als de template-repo niet zonder inloggen te lezen is | id van een *Username with password*-credential met leesrechten op de template-repo (git via HTTPS) |
| `MIGRATIE_JDK`, `MIGRATIE_MAVEN` | nee | namen van JDK- en Maven-installaties in Jenkins (*Tools*); leeg: `java` en `mvn` uit het PATH. JDK 21 of nieuwer, want `recepten/` is voor Java 21 gebouwd |
| `MIGRATIE_SJABLOON` | nee | de migratie die deze job steeds opnieuw draait, als ronde (zie hieronder) |
| `MIGRATIE_RONDE` | nee | datumformaat van de ronde: standaard `%G-w%V` (per week), bv. `%Y-%m` voor maandelijks |
| `MIGRATIE_CRON` | nee | cron voor geplande builds, bv. `H 6 * * 1`; leeg: uit |
| `MIGRATIE_GIT_NAAM`, `MIGRATIE_GIT_EMAIL` | nee | auteur van de commits in de services |
| `MIGRATIE_EIGEN_REPO` | nee | git-URL van een eigen repo met `migraties/` en/of `recepten/` (zie "Eigen migraties en recepten") |
| `MIGRATIE_EIGEN_BRANCH`, `MIGRATIE_EIGEN_CREDENTIALS` | nee | branch van die repo (standaard `main`) en id van een credential om hem te lezen |
| `CONCURRENT`, `UITSLUITLIJST` | nee | zoals in `config.env.example` |
| `PIP_INDEX_URL`, `MULTI_GITTER_BASIS`, `JQ_BASIS` | achter een afgeschermd netwerk | downloads via een mirror (bv. Nexus), zie `jenkins/gereedschap.sh` |

Ontbreekt er iets verplichts, dan stopt de eerste stap met een lijst van wat er moet
worden ingesteld. De agent heeft verder nodig: bash, git, curl, tar en python3 met venv
(Debian/Ubuntu: `python3-venv`); de Maven-instellingen (bv. een Nexus-mirror) komen van
de agent, net als bij jullie andere Maven-builds.

Parameters: `MIGRATIE` (naam of pad), `GO` (uit = dry-run), `REPO_INCLUDE` en
`ZONDER_VERIFY`. De artefacten van een build zijn `runs/**`: resultaten.tsv en per
service de patches en de uitvoer. Is er handwerk nodig, dan wordt de build *unstable*;
de beschrijving van de build telt de uitkomsten. Bij *unstable* en *failure* is er een
plek voor een eigen melding (bv. naar een chatkanaal).

### Meerdere jobs

Alle jobs gebruiken dezelfde `Jenkinsfile`; per job (of per map) zet je in Jenkins welke
migratie hij draait. Bijvoorbeeld:

| Job | `MIGRATIE_SJABLOON` | `MIGRATIE_RONDE` | `MIGRATIE_CRON` |
|---|---|---|---|
| cruft update | `cruft-update` | `%Y-%m` | `H 6 1 * *` (maandelijks) |
| wekelijkse opschoning | `opschoning` | (standaard, per week) | `H 6 * * 1` |
| features, incidenteel | – | – | – (bij het starten `MIGRATIE` invullen) |

Een build van een job met een sjabloon maakt er een ronde van: een kopie met de ronde in
de naam, bv. `opschoning-2026-w43`, zodat elke ronde een eigen branch en eigen MR's krijgt
(een `BRANCH=` uit het sjabloon gaat er in de kopie uit). Een geplande build draait die
ronde met `--go`; een handmatige build draait `MIGRATIE` als die is ingevuld, anders de
ronde van het sjabloon, standaard als dry-run. `migraties/cruft-update.env` en
`migraties/opschoning.env` zijn de algemene sjablonen; eigen sjablonen zet je in
`MIGRATIES_MAP`.

## Tips

- Begin met `--go` op twee of drie services, merge die, en draai daarna de hele groep.
- Gedeelde Maven-cache (`~/.m2`) of een Nexus-mirror scheelt veel tijd bij 60 services.
