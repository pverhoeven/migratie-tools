# Een migratie is een bestand; herhaalde runs raken bestaande branches niet

Elke migratie staat als bestand in deze repo; de bestandsnaam is de branchnaam. Zo is
achteraf uit git te herleiden wat er is uitgerold, en hoort een PR bij één concrete
migratie in plaats van bij een combinatie van stapnamen. Een herhaalde run slaat
services over die al een branch voor die migratie hebben (in plaats van die te
vervangen), omdat handwerk bij "Handwerk nodig" juist op die branch gebeurt: lokaal via
`local.sh`, er komt dan geen automatische PR. Opnieuw genereren betekent eerst de branch
verwijderen.

Recepten staan in deze repo zelf, dus de pin van een recept is de git-commit van
migratie-tools: die legt migratiebestand en receptcode samen vast. Een echte run weigert
daarom bij een vuile werkmap en zet de commit-hash in de PR; dry-runs mogen wel met een
vuile werkmap, om te kunnen itereren.

Het template pinnen we bewust niet: net als `cruft update` gaat een template-update altijd
naar de nieuwste stand van het template, want zo werken de teams al en de template-repo
heeft geen tags. Welke template-commit een service kreeg, staat in de commits van de PR en
in `.cruft.json`. Gevolg: services die later in een migratie aan de beurt komen (na de
eerste paar), kunnen een nieuwere template-stand krijgen.
