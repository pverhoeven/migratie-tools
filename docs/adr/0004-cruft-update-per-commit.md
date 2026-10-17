# Cruft update commit voor commit, met een eigen 3-way-merge

De transformatie heet cruft update en doet wat het commando `cruft update` doet: zelfde
startpunt (de template-commit in `.cruft.json`), zelfde doel (de nieuwste stand van de
standaardbranch van het template), zelfde context. Maar we roepen het commando niet aan.
In plaats daarvan lopen we de commits op de hoofdlijn van het template één voor één af.
Per commit genereren we de vorige en de volgende stand, en werken we elk bestand bij met
een 3-way-merge (basis = vorige stand, ours = service, theirs = volgende stand). Elke
template-commit wordt een eigen commit in de service, met het onderwerp van de
template-commit erbij. Bij het eerste conflict stopt de update. De conflicterende
bestanden krijgen diff3-conflictmarkers en staan als echte git-conflicten in de index
(stage 1/2/3), zodat een IDE ze 3-way kan mergen. `.cruft.json` blijft de bron van de
waarheid, en cruft blijft nodig om te genereren.

## Waarom niet het commando `cruft update`

Er zijn twee problemen, en allebei worden ze erger naarmate een service verder
achterloopt.

- **Conflicten worden `.rej`-bestanden.** cruft maakt een patch en probeert eerst
  `git apply -3`. Daarvoor moet de oude versie van elk bestand in de git-database van de
  service staan. Daar staat alleen wat de service heeft gecommit, niet wat het template
  destijds genereerde. Zodra de service een bestand zelf heeft aangepast, valt cruft
  daarom terug op `git apply --reject`. Dat geeft losse `.rej`-brokken die met de hand
  overgetikt moeten worden en die geen merge-tool kan openen.
- **Alles gaat in één patch.** Bij tien template-commits achterstand zitten alle
  wijzigingen in één diff. Een conflict is dan niet aan één template-wijziging te
  koppelen. Wijzigingen die los wel schoon waren gegaan, raken elkaar in dezelfde patch,
  waardoor er meer en grotere conflicten ontstaan.

## Waarom commit voor commit

- Kleinere diffs per stap, dus minder conflicten.
- Een conflict hoort bij één template-wijziging, met haar onderwerp erbij, zodat duidelijk
  is wat het template wilde.
- De MR laat per template-commit zien wat er in de service veranderde.
- Omdat we per stap zelf de oude en de nieuwe stand genereren, hebben we de basis voor een
  echte 3-way-merge. Die basis ontbreekt bij cruft.

## Waarom cruft het zelf niet zo doet

Dit volgt uit de werking van cruft, niet uit een uitspraak van de makers. cruft ziet het
template als een momentopname, niet als historie: `.cruft.json` onthoudt één commit, en
een update is het verschil tussen twee keer genereren. Dat is eenvoudig en werkt voor
elke ref (branch, tag, commit), ook als de historie van het template niet recht is
(merges, force-pushes). Stapsgewijs bijwerken kost meer: twee keer genereren per
template-commit in plaats van twee keer in totaal, met de hooks van het template elke
keer erbij. Bovendien moet elke tussenliggende commit te genereren zijn. Echte
3-way-conflicten zitten er niet in, omdat cruft de oude gegenereerde bestanden niet als
basis in git zet.

## Gevolgen

- **Langzamer dan `cruft update`:** twee keer genereren per template-commit. Bij een
  klein template valt dat weg tegen de build.
- **Afhankelijk van een interne functie van cruft** (`lib/render-template.py`). Daarom
  pinnen we cruft op één versie (2.16.0, zie de README).
- **Een tussencommit van het template die niet te genereren is,** levert "Handwerk nodig"
  op, ook als de nieuwste stand wel goed is. Als dat in de praktijk voorkomt, kan de
  update zo'n commit overslaan en samenvoegen met de volgende stap.
- **Een service die ver achterloopt, krijgt veel commits in zijn MR.** Die kun je bij het
  mergen squashen.

## Overwogen

- **Het commando `cruft update`:** zie hierboven.
- **Stappen per tag:** de template-repo heeft geen tags.
- **Overstappen op copier,** dat bij een update zelf conflictmarkers in de bestanden zet:
  voor nu een te grote overstap voor het template en alle services.
