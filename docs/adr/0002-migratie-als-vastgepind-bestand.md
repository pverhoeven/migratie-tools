# Een migratie is een bestand; herhaalde runs raken bestaande branches niet

Elke migratie staat als bestand in deze repo; de bestandsnaam is de naam van de migratie
en het label op haar PR's. De branch (standaard `migratie/<naam>`) en de PR-titel kunnen
in het bestand worden aangepast (`BRANCH`, `PR_TITEL`); ze staan juist in het bestand
zodat elke run van de migratie dezelfde branch gebruikt. Open MR's van een migratie
herkennen we aan dat label, niet aan de branchnaam. Zo hoort een PR bij één concrete
migratie in plaats van bij een combinatie van stapnamen. Een herhaalde run slaat
services over die al een branch voor die migratie hebben (in plaats van die te
vervangen), omdat handwerk bij "Handwerk nodig" juist op die branch gebeurt: in de eigen clone via
`in-repo.sh`, er komt dan geen automatische PR. Opnieuw genereren betekent eerst de branch
verwijderen.

Wat er is uitgerold, legt de PR zelf vast: de beschrijving bevat de inhoud van het
migratiebestand en de commit van migratie-tools (met "met lokale wijzigingen" als de
werkmap niet schoon was). Het migratiebestand hoeft daarom niet gecommit te zijn, ook
niet voor een echte run. Oorspronkelijk eisten we een schone werkmap, zodat de commit
ook het migratiebestand en de receptcode vastlegde; dat bleek in de praktijk meer
hinder dan nut. Wat we daarmee opgeven: niet-gecommitte receptcode staat nergens
vastgelegd (een echte run waarschuwt daarvoor), en wie een migratie later vanaf een
andere machine herhaalt, heeft het bestand alleen als het wel gecommit is.

Het template pinnen we bewust niet: net als `cruft update` gaat een cruft update altijd
naar de nieuwste stand van het template, want zo werken de teams al en de template-repo
heeft geen tags. Welke template-commit een service kreeg, staat in de commits van de PR en
in `.cruft.json`. Gevolg: services die later in een migratie aan de beurt komen (na de
eerste paar), kunnen een nieuwere template-stand krijgen.
