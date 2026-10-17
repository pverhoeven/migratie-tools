# migratie-tools

Rolt migraties uit over de services in een GitLab-groep: eerst lokaal op een paar
services, daarna met multi-gitter over de hele groep, met per service een eigen PR.
Begrippen staan in [GLOSSARY.md](GLOSSARY.md), besluiten in [docs/adr](docs/adr).

## Structuur

```
run.sh                 één migratie over een GitLab-groep (standaard dry-run)
local.sh               lokaal: kloont services naar ./work en draait de migratie
achterstand.sh         per template-service: template-commit en achterstand
repo-runner.sh         draait één migratie binnen één service
migraties/<naam>.env   de migraties; <naam> wordt de branch migratie/<naam>
transformaties/        template-update.sh, recept.sh
recepten/              Maven-module met de OpenRewrite-recepten (YAML en Java)
controles/             verify.sh
lib/                   hulpfuncties
voorbeeld/             een voorbeeld-template met twee services om mee te oefenen
```

Een migratie bestaat uit een template-update en/of één OpenRewrite-recept, gevolgd
door de controle `verify` (build en tests). Elke transformatie commit haar eigen
wijzigingen; de template-update maakt één commit per template-commit.

## Voorbereiding

Nodig: `git`, `jq`, [cruft](https://cruft.github.io/cruft/) 2.16.0, Java en Maven
(of een `mvnw` in de service). Voor `run.sh` ook
[multi-gitter](https://github.com/lindell/multi-gitter).

```bash
pipx install cruft==2.16.0
```

Gebruik precies deze cruft-versie: de template-update gebruikt een interne functie van
cruft (`lib/render-template.py`) en is alleen met 2.16.0 getest. Test een nieuwere versie
eerst met het voorbeeld (`voorbeeld/README.md`) voordat je hem ophoogt.

```bash
cp config.env.example config.env   # GitLab- en Maven-instellingen
```

## Een migratie maken

Kopieer `migraties/_voorbeeld.env` naar `migraties/<naam>.env`:

```bash
TEMPLATE_UPDATE=ja                               # naar de nieuwste stand van het template
RECEPT=local.migratietools.SpringBoot35          # en/of één recept uit recepten/
```

Commit het bestand: een echte run draait alleen vanaf een schone werkmap en zet de
commit van migratie-tools in de PR. Geef de migratie een naam die past bij wat er
gebeurt, bv. `template-2026-10` of `spring-boot-3.5`.

## Recepten

Recepten staan in de module `recepten/`: YAML in `src/main/resources/META-INF/rewrite/`,
Java in `src/main/java/`. Een migratie verwijst naar precies één recept uit deze module;
publieke recepten (bv. uit `rewrite-spring`, als dependency in `recepten/pom.xml`) roep
je aan vanuit een YAML-recept. Elk recept heeft minstens één before/after-test
(`RewriteTest`). Aan het begin van een run met een recept wordt de module gebouwd en
lokaal geïnstalleerd, mét tests; een rode test stopt de run.

De versie van `rewrite-maven-plugin` staat in `recepten/pom.xml` en moet bij de
`rewrite-recipe-bom` passen (zelfde rewrite-versie).

## Lokaal draaien

```bash
./local.sh migraties/template-2026-10.env ~/code/service-a ~/code/service-b
git -C work/service-a log -p origin/HEAD..HEAD
```

`local.sh` werkt op een verse clone in `./work/<naam>` op de branch
`migratie/<naam>` en pusht nooit. Niet-gecommitte wijzigingen in je eigen repo worden
niet meegenomen. Met `--zonder-verify` (vóór het migratiebestand) sla je de build over.

## Template-updates en conflicten

De template-update doet hetzelfde als `cruft update`: van de template-commit in
`.cruft.json` naar de nieuwste commit van het template, met de context van de service.
Alleen loopt hij de commits van het template één voor één af en merget hij elk bestand
3-way (basis = vorige stand van het template, ours = de service, theirs = de volgende
stand). Bij een conflict stopt hij bij die template-commit, met conflictmarkers in de
bestanden (inclusief de basis). De conflicten staan ook als echte git-conflicten in de
index (basis, service, template), zodat je ze in je IDE 3-way kunt mergen. Elke
template-commit wordt een eigen commit in de service.

## Handwerk nodig

Een service met de uitkomst "Handwerk nodig" (conflict of rode build) krijgt geen PR.
Maak hem lokaal af:

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

Een herhaalde run slaat services over die al een branch `migratie/<naam>` hebben.
Extra multi-gitter-flags geef je achteraan mee (`--repo-include`, `--include-subgroups`, ...).

Vóór de run vraagt `run.sh` bij GitLab de open MR's met label `migratie` op. Een service
met een open MR van een *andere* migratie doet niet mee en krijgt de uitkomst
"Wacht op vorige migratie"; een latere run pakt hem op. Repo's op de `UITSLUITLIJST`
(`config.env`) doen nooit mee.

Elke run schrijft `runs/<migratie>-<tijd>/resultaten.tsv` en toont aan het eind de
uitkomst per service, met de werklijst (Handwerk nodig) bovenaan.

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
