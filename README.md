# migratie-tools

Losse stappen (cruft, OpenRewrite, build-check) die je lokaal op één of meer repo's
kunt draaien, en later met multi-gitter over een hele GitLab-groep.

## Structuur

```
run.sh            multi-gitter over een GitLab-groep (standaard dry-run)
local.sh          lokaal: kloont repo's naar ./work en draait de stappen
repo-runner.sh    draait de gekozen stappen binnen één repo
steps/
  cruft-update.sh
  openrewrite.sh
  verify.sh
  _lib.sh         hulpfuncties (geen stap)
config.env.example
```

Een stap draait in de map van de repo. Exit 0 = goed, non-zero = repo overslaan
(multi-gitter maakt dan geen PR).

## Voorbereiding

Nodig: `git`, `cruft`, Java en Maven (of een `mvnw` in de repo). Voor `run.sh` ook
[multi-gitter](https://github.com/lindell/multi-gitter).

```bash
cp config.env.example config.env   # vul de OpenRewrite-instellingen in
```

## Lokaal draaien

```bash
# één stap op één repo (pad of git-URL)
./local.sh cruft-update ~/code/service-a

# alle stappen achter elkaar op meerdere repo's
./local.sh cruft-update,openrewrite,verify ~/code/service-a ~/code/service-b

# bekijk het resultaat
git -C work/service-a diff
```

`local.sh` werkt op een verse clone in `./work/<naam>`, dus je eigen werkmap blijft
ongemoeid. Niet-gecommitte wijzigingen in je lokale repo worden niet meegenomen.

Een stap direct in een repo draaien kan ook (let op: dit wijzigt de repo zelf):

```bash
cd ~/code/service-a
STEPS_DIR=~/migratie-tools/steps STEPS=cruft-update ~/migratie-tools/repo-runner.sh
```

## Over een hele GitLab-groep (multi-gitter)

```bash
export GITLAB_TOKEN=...            # of in config.env
./run.sh cruft-update              # dry-run: niets wordt gepusht
./run.sh cruft-update,openrewrite,verify --go   # echt PR's aanmaken
```

Extra multi-gitter-flags geef je gewoon achteraan mee (`--repo-include`, `--labels`,
`--reviewers`, ...). Controleer de exacte flags van jouw versie met
`multi-gitter run --help`.

## Tips

- Begin lokaal op 1 à 2 services en bekijk de diff voordat je naar de hele groep gaat.
- Grote migraties (Spring Boot-upgrade) als aparte run/PR; kleine template-bumps mag je bundelen.
- Pin `TEMPLATE_VERSION` bij grote template-wijzigingen.
- Gedeeld Maven-cache (`~/.m2`) of een Nexus-mirror scheelt veel tijd bij 60 services.
