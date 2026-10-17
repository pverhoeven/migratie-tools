# Template-updates per versie, met een eigen 3-way-merge

We gebruiken `cruft update` niet. Die past het verschil tot de doelversie toe als één
patch en valt bij conflicten terug op `.rej`-bestanden, die niet in een merge-tool te
openen zijn en bij een grote achterstand niet aan één versie te koppelen zijn. In plaats
daarvan loopt de template-update de template-versies één voor één af: per stap worden de
oude en de nieuwe versie gegenereerd met de context uit `.cruft.json`, en elk bestand
wordt met een 3-way-merge (basis = oude versie, ours = service, theirs = nieuwe versie)
bijgewerkt. Bij het eerste conflict stopt de update, met diff3-conflictmarkers in de
bestanden. `.cruft.json` blijft de bron van de waarheid en cruft blijft nodig om te
genereren.

Overwogen: overstappen op copier, dat dit zelf doet. Voor nu een te grote overstap voor
het template en alle services.
