# migratie-tools

Rolt migraties uit over de services in een GitLab-groep: eerst lokaal op een paar
services, daarna met multi-gitter over de hele groep, met per service een eigen PR.
Begrippen staan in [GLOSSARY.md](GLOSSARY.md), besluiten in [docs/adr](docs/adr).

## Structuur

```
run.sh                 één migratie over een GitLab-groep (standaard dry-run)
local.sh               lokaal: kloont services naar ./work en draait de migratie
repo-runner.sh         draait één migratie binnen één service
migraties/<naam>.env   de migraties; <naam> wordt de branch migratie/<naam>
transformaties/        template-update.sh, recept.sh
controles/             verify.sh
lib/                   hulpfuncties
voorbeeld/             een voorbeeld-template met twee services om mee te oefenen
```

Een migratie bestaat uit een template-update en/of één OpenRewrite-recept, gevolgd
door de controle `verify` (build en tests). Elke transformatie commit haar eigen
wijzigingen; de template-update maakt één commit per template-versie.

## Voorbereiding

Nodig: `git`, `jq`, [cruft](https://cruft.github.io/cruft/) (`pipx install cruft`),
Java en Maven (of een `mvnw` in de service). Voor `run.sh` ook
[multi-gitter](https://github.com/lindell/multi-gitter).

```bash
cp config.env.example config.env   # GitLab- en Maven-instellingen
```

## Een migratie maken

Kopieer `migraties/_voorbeeld.env` naar `migraties/<naam>.env` en pin alles vast:

```bash
TEMPLATE_VERSION=v1.4.0            # template-versie (tag)
# RECEPT=...                       # en/of één OpenRewrite-recept
```

Commit het bestand: een echte run draait alleen vanaf een schone werkmap en zet de
commit van migratie-tools in de PR.

## Lokaal draaien

```bash
./local.sh migraties/template-v1.4.0.env ~/code/service-a ~/code/service-b
git -C work/service-a log -p origin/HEAD..HEAD
```

`local.sh` werkt op een verse clone in `./work/<naam>` op de branch
`migratie/<naam>` en pusht nooit. Niet-gecommitte wijzigingen in je eigen repo worden
niet meegenomen. Met `--zonder-verify` (vóór het migratiebestand) sla je de build over.

## Template-updates en conflicten

De template-update loopt de template-versies één voor één af en merget elk bestand
3-way (basis = vorige template-versie, ours = de service, theirs = de volgende
template-versie). Bij een conflict stopt hij bij die versie, met conflictmarkers in de
bestanden (inclusief de basis), zodat je ze in je IDE kunt oplossen.

## Over een hele GitLab-groep (multi-gitter)

```bash
./run.sh migraties/template-v1.4.0.env                                  # dry-run
./run.sh migraties/template-v1.4.0.env --go --repo-include 'service-(a|b)'
./run.sh migraties/template-v1.4.0.env --go                             # de rest
```

Een herhaalde run slaat services over die al een branch `migratie/<naam>` hebben.
Extra multi-gitter-flags geef je achteraan mee (`--repo-include`, `--include-subgroups`, ...).

## Tips

- Begin met `--go` op twee of drie services, merge die, en draai daarna de hele groep.
- Gedeelde Maven-cache (`~/.m2`) of een Nexus-mirror scheelt veel tijd bij 60 services.
