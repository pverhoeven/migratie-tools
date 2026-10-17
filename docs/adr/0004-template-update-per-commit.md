# Template-updates commit voor commit, met een eigen 3-way-merge

We gebruiken `cruft update` niet zelf. Die past alles sinds de template-commit in
`.cruft.json` toe als één patch en valt bij conflicten terug op `.rej`-bestanden, die
niet in een merge-tool te openen zijn en bij een grote achterstand niet aan één
wijziging te koppelen zijn. In plaats daarvan doet de template-update hetzelfde als
`cruft update` (zelfde startpunt, zelfde doel: de nieuwste stand van de standaardbranch,
zelfde context), maar loopt hij de commits op de hoofdlijn van het template één voor één
af: per commit worden de vorige en de volgende stand gegenereerd en wordt elk bestand
met een 3-way-merge (basis = vorige stand, ours = service, theirs = volgende stand)
bijgewerkt. Bij het eerste conflict stopt de update, met diff3-conflictmarkers in de
bestanden. Elke template-commit wordt een eigen commit in de service, met het onderwerp
van de template-commit erbij. `.cruft.json` blijft de bron van de waarheid en cruft
blijft nodig om te genereren.

Overwogen: stappen per tag (de template-repo heeft geen tags) en overstappen op copier,
dat dit zelf doet (voor nu een te grote overstap voor het template en alle services).
