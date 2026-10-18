# migratie-tools

Rolt migraties uit over de services in een GitLab-groep: eerst lokaal op een paar
services, daarna met multi-gitter over de hele groep, met per service een eigen PR.
Begrippen staan in [GLOSSARY.md](GLOSSARY.md), besluiten in [docs/adr](docs/adr).

## Structuur

```
migratie.sh            menu: kies een actie en een migratie, of maak een nieuwe
run.sh                 één migratie over een GitLab-groep (standaard dry-run)
local.sh               lokaal: kloont services naar ./work en draait de migratie
in-repo.sh             lokaal: draait de migratie in een bestaande clone
cruft-zet.sh           lokaal: zet een template-variabele om in één service (bv. liquibase=true)
achterstand.sh         per template-service: template-commit en achterstand
repo-runner.sh         draait één migratie binnen één service
migraties/<naam>.env   de migraties; <naam> wordt de branch migratie/<naam>
transformaties/        cruft-update.sh, recept.sh
recepten/              Maven-module met de OpenRewrite-recepten (YAML en Java)
controles/             verify.sh
lib/                   hulpfuncties
voorbeeld/             een voorbeeld-template met twee services om mee te oefenen
```

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

Kopieer `migraties/_voorbeeld.env` naar `migraties/<naam>.env`:

```bash
CRUFT_UPDATE=ja                                  # naar de nieuwste stand van het template
RECEPT=local.migratietools.SpringBoot35          # en/of één recept uit recepten/
BRANCH=migratie/spring-boot-3.5                  # optioneel, standaard migratie/<naam>
PR_TITEL='chore(deps): Spring Boot 3.5'          # optioneel, standaard chore(migratie): <naam>
```

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

Voor een wekelijkse opschoning maak je elke week een migratiebestand, bv.
`migraties/opschoning-2026-w42.env` met `RECEPT=local.migratietools.WekelijkseOpschoning`.
Een service waarin niets op te ruimen valt, krijgt geen MR. Grotere of opiniërende
recepten (Spring Boot-upgrades, AssertJ, `CommonStaticAnalysis`, `AutoFormat`) draai je
als losse migratie; een Spring Boot-upgrade bij template-services samen met
`CRUFT_UPDATE=ja` (het template hoogt de parent op, het recept past de code aan).

## Lokaal draaien

```bash
./local.sh migraties/template-2026-10.env ~/code/service-a ~/code/service-b
git -C work/service-a log -p origin/HEAD..HEAD
```

`local.sh` werkt op een verse clone in `./work/<naam>` op de branch
`migratie/<naam>` en pusht nooit. Niet-gecommitte wijzigingen in je eigen repo worden
niet meegenomen. Met `--zonder-verify` (vóór het migratiebestand) sla je de build over.

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
Maak hem lokaal af, in je eigen clone met `in-repo.sh` (zie hierboven) of in een verse
clone met `local.sh`:

```bash
./local.sh migraties/template-2026-10.env <git-url-van-de-service>   # stopt bij het conflict
# los de conflicten op in work/<service> (of repareer de build), zie hieronder
./local.sh --verder migraties/template-2026-10.env <service>          # commit en gaat verder
git -C work/<service> push -u origin migratie/template-2026-10
```

Open daarna zelf de MR, met de labels `migratie` en `<naam van de migratie>`.
`--verder` weigert zolang er nog conflicten of conflictmarkers in de service staan.

Conflicten oplossen in IntelliJ: open `work/<service>` en kies *Git → Resolve Conflicts…*
(de bestanden staan ook in het Commit-venster onder *Merge Conflicts*). In het
merge-venster is links de service (*Yours*), rechts het template (*Theirs*) en in het
midden het resultaat, met de vorige stand van het template als basis. Klaar met
*Apply*; daarna `./local.sh --verder …`. Op de commandoregel kan het ook, bv. met
`git checkout --theirs -- <bestand>` (template) of `--ours` (service) en `git add`.

## Over een hele GitLab-groep (multi-gitter)

```bash
./run.sh migraties/template-2026-10.env                                  # dry-run
./run.sh migraties/template-2026-10.env --go --repo-include 'service-(a|b)'
./run.sh migraties/template-2026-10.env --go                             # de rest
```

Een herhaalde run slaat services over die de branch van de migratie al hebben.
Extra multi-gitter-flags geef je achteraan mee (`--repo-include`, `--include-subgroups`, ...).

Vóór de run vraagt `run.sh` bij GitLab de open MR's met label `migratie` op. Een service
met een open MR van een *andere* migratie (herkend aan het label met de naam van de migratie) doet niet mee en krijgt de uitkomst
"Wacht op vorige migratie"; een latere run pakt hem op. Repo's op de `UITSLUITLIJST`
(`config.env`) doen nooit mee.

Elke run schrijft `runs/<migratie>-<tijd>/resultaten.tsv` en toont aan het eind de
uitkomst per service, met de werklijst (Handwerk nodig) bovenaan.

Om een (dry-)run na te kijken staat per service in `runs/<migratie>-<tijd>/debug/<service>/`:

| Bestand | Inhoud |
|---|---|
| `wijzigingen.patch` | de commits van de migratie, met boodschap (`git format-patch`; toe te passen met `git am`) |
| `onafgemaakt.diff`, `status.txt` | bij Handwerk nodig: de stand waarin de migratie stopte, met de conflictmarkers |
| `uitvoer.log` | de volledige uitvoer van de migratie voor die service (multi-gitter toont die niet) |

Dat geldt voor `run.sh` (ook de dry-run) en `local.sh`.

## Achterstand

```bash
./achterstand.sh                       # alle template-services in GITLAB_GROUP
./achterstand.sh ~/code/service-a      # of lokale repo's
```

Toont per template-service op welke template-commit hij zit en hoeveel commits van het
template hij achterloopt, de grootste achterstand bovenaan. Handig vóór je een nieuwe
template-migratie start: services die ver achterlopen krijgen meer kans op conflicten.

## Tips

- Begin met `--go` op twee of drie services, merge die, en draai daarna de hele groep.
- Gedeelde Maven-cache (`~/.m2`) of een Nexus-mirror scheelt veel tijd bij 60 services.
