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

Draai de cruft update van een template-wijziging op alle services, zonder iets te
pushen, en zet in de MR van het template hoeveel services "Gewijzigd" en hoeveel
"Handwerk nodig" worden, met de conflicten. Dan ziet de template-beheerder vóór het
mergen dat een wijziging bijvoorbeeld bij twaalf services botst.

- Er is al: `uitproberen.sh` en `lib/samenvatting.sh`.
- Nodig: een Jenkins-stap op de template-repo die de cruft update tegen de MR-branch
  draait en de samenvatting als MR-commentaar plaatst.

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
