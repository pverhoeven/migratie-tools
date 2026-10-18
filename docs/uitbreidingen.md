# Uitbreidingen

Ideeën die migratie-tools bruikbaarder maken. Nu doet het vooral de uitrol: migraties
draaien, MR's aanmaken, achterstand tonen. De meeste winst zit in wat ervoor en erna
komt. De eerste drie hebben voorrang.

Houd de status bij in de tabel: Idee, Gepland, Bezig, Klaar of Afgewezen. Instellingen
die specifiek zijn voor de organisatie (groepen, kanalen, teams) horen in `config.env` of
in Jenkins, niet in deze repo.

| # | Uitbreiding | Prioriteit | Status |
|---|---|---|---|
| 1 | [Impactanalyse bij een template-MR](#1-impactanalyse-bij-een-template-mr) | hoog | Idee |
| 2 | [Opvolgen na de uitrol](#2-opvolgen-na-de-uitrol) | hoog | Idee |
| 3 | [Snel reageren op een kwetsbaarheid](#3-snel-reageren-op-een-kwetsbaarheid) | hoog | Idee |
| 4 | [Werk naar het juiste team](#4-werk-naar-het-juiste-team) | middel | Idee |
| 5 | [Automatisch mergen bij veilige migraties](#5-automatisch-mergen-bij-veilige-migraties) | middel | Idee |
| 6 | [Een nieuwe service starten](#6-een-nieuwe-service-starten) | middel | Idee |
| 7 | [Bestaande services onder het template](#7-bestaande-services-onder-het-template) | middel | Idee |
| 8 | [Inventaris van het template-gebruik](#8-inventaris-van-het-template-gebruik) | laag | Idee |
| 9 | [Meerdere recepten per migratie](#9-meerdere-recepten-per-migratie) | laag | Idee |

## 1. Impactanalyse bij een template-MR

Een proef-cruft-update van een template-wijziging op alle services, vóór het mergen. De
uitkomst komt als commentaar in de MR van het template. Dan ziet de template-beheerder
bijvoorbeeld dat een wijziging bij twaalf services botst, en niet pas bij de uitrol.

De templates staan in hun eigen git-repo's; `.cruft.json` van elke service wijst ernaar.
De analyse hoort bij een MR op zo'n template-repo en gebruikt migratie-tools alleen als
gereedschap. In deze repo komt niets van de templates.

### Wat het doet

1. Een MR op de template-repo start een pipeline (GitLab CI, of Jenkins via een
   webhook). Die checkt migratie-tools uit en roept het aan met de MR-branch, bv.
   `TEMPLATE_REF=<MR-branch>`.
2. Alleen services waarvan `.cruft.json` naar déze template-repo wijst, doen mee.
3. Per service: vers klonen, de cruft update draaien tot de laatste commit van de
   MR-branch in plaats van tot de standaardbranch, en daarna verify (build en tests).
   Er wordt niets gepusht en er komen geen MR's bij de services.
4. De samenvatting komt als commentaar in de template-MR, via de GitLab API:

```
Impact van deze MR op 40 template-services:
  Gewijzigd, build groen     31
  Handwerk nodig (conflict)   6   klant-service, ... : application.properties
  Build rood                  2   order-service: ApplicationTest faalt
  Al vast op main             1   (zie hieronder)
```

### Door de MR of al vast

Services lopen vaak al achter. De cruft update gaat commit voor commit en meldt bij
welke template-commit hij stopt. Zo houdt de analyse twee gevallen uit elkaar:

- **Hij stopt op een commit van de MR.** Deze wijziging veroorzaakt het probleem; dat
  wil de template-beheerder weten.
- **Hij stopt al op een commit van de standaardbranch.** De service zit al vast, los
  van deze MR, en wat de MR doet is niet te beoordelen. Die telt apart.

In het voorbeeld (`voorbeeld/README.md`): komt de shutdown-timeout als MR binnen, dan
wordt bestel-service "Gewijzigd, groen", en valt klant-service onder "al vast op main",
want die stopt al bij `fix: logging op warn`.

Met de uitkomst kan de template-beheerder de wijziging anders opzetten (een nieuwe
property in plaats van een bestaande veranderen, of de wijziging achter een
template-variabele zetten), de teams vooraf waarschuwen, of bewust mergen.

### Wat er al is en wat nodig is

- Er is al: `uitproberen.sh`, `transformaties/cruft-update.sh` (kloont het template via
  de URL in `.cruft.json`), `--zonder-verify` en `lib/samenvatting.sh`.
- Nodig:
  - `TEMPLATE_REF` in `cruft-update.sh`; het doel is nu altijd de standaardbranch van het
    template.
  - De template-commit waar een service stopt als apart veld in de resultaten; nu staat
    die alleen in de reden ("conflict bij template b9141e5 …").
  - Een filter op de template-URL in `.cruft.json`, als jullie meerdere templates
    hebben.
  - Een pipeline op de template-repo die migratie-tools aanroept en het MR-commentaar
    plaatst.

### Aandachtspunten

- **MR vanuit een fork:** de branch staat dan niet in de repo waar `.cruft.json` naar
  wijst; de job moet de ref dan uit de fork halen. Met branches in de template-repo zelf
  speelt dit niet.
- **Squash-merge:** de analyse ziet de losse MR-commits, de uitrol straks één commit.
  Welke bestanden botsen verandert zelden, maar een conflict kan bij een andere commit
  vallen.
- **Rekentijd:** bij elke push op de MR alle services klonen, mergen en bouwen. Maak
  verify optioneel, of draai de analyse alleen op verzoek.

## 2. Opvolgen na de uitrol

`run.sh` maakt de MR's aan, maar daarna is er geen overzicht. Een `status.sh <migratie>`
laat per service zien of de MR open, gemerged of gesloten is, of de pipeline rood is en
hoe lang de MR al open staat. Samen met de werklijst "Handwerk nodig" zie je zo wanneer
een migratie echt af is.

- Er is al: `lib/gitlab.sh`, de branch en de labels per migratie.
- Nodig: een script dat de MR's per label of branch ophaalt via de GitLab API.

## 3. Snel reageren op een kwetsbaarheid

Twee delen:

- een rapport, zonder iets te wijzigen, van welke services dependency X onder versie Y
  gebruiken;
- een migratie die de versie ophoogt, met een OpenRewrite-recept met parameters, zoals
  `UpgradeDependencyVersion`.

Bij een CVE heb je dan snel MR's bij precies de services die het nodig hebben.

- Er is al: `ALLEEN_MET_DEPENDENCY` filtert op een dependency.
- Nodig: filteren op versie, en recepten met parameters in het migratiebestand (nu
  draait een migratie één recept zonder parameters).

## 4. Werk naar het juiste team

Wijs MR's en "Handwerk nodig" toe aan de eigenaar, via CODEOWNERS of een toewijzing per
GitLab-subgroep. Stuur na een Jenkins-run de werklijst naar het teamkanaal of per mail, in
plaats van alleen naar `runs/`.

## 5. Automatisch mergen bij veilige migraties

Laat GitLab de MR mergen zodra de pipeline groen is, met een vlag in het migratiebestand.
Bij de wekelijkse opschoning of patch-updates scheelt dat veel reviewwerk.

## 6. Een nieuwe service starten

Doe `cruft create` en het aanmaken van de GitLab-repo in één stap, zodat een nieuwe
service meteen meedoet met de migraties.

## 7. Bestaande services onder het template

Services zonder `.cruft.json`, zoals `losse-service` in het voorbeeld, vallen nu buiten
de cruft update. Met `cruft link` en een begeleide eerste update sluit je ze stap voor
stap aan.

## 8. Inventaris van het template-gebruik

Toon per service welke template-variabelen aan staan (wie liquibase heeft, wie de
gedeelde jar) en hoe de achterstand zich in de tijd ontwikkelt, bijvoorbeeld wekelijks
via Jenkins. Zo zie je of services bijblijven.

- Er is al: `achterstand.sh` en de context in `.cruft.json`.

## 9. Meerdere recepten per migratie

Dat kan nu al met een eigen recept dat andere recepten aanroept (zie
`voorbeeld/intern`), maar `RECEPT='a b'` in het migratiebestand is eenvoudiger.
