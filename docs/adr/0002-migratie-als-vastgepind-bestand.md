# Een migratie is een vastgepind bestand; herhaalde runs raken bestaande branches niet

Elke migratie staat als bestand in deze repo, met alle versies en recepten vastgepind
("laatste versie" mag niet); de bestandsnaam is de branchnaam. Zo is achteraf uit git te
herleiden wat er precies is uitgerold, en hoort een PR bij één concrete migratie in
plaats van bij een combinatie van stapnamen. Een herhaalde run slaat services over die
al een branch voor die migratie hebben (in plaats van die te vervangen), omdat
handwerk bij "Handwerk nodig" juist op die branch gebeurt: lokaal via `local.sh`, er
komt dan geen automatische PR. Opnieuw genereren betekent eerst de branch verwijderen.

Omdat de recepten in deze repo zelf staan, is de pin van een echte run de git-commit van
migratie-tools: die legt migratiebestand en receptcode samen vast. Een echte run weigert
daarom bij een vuile werkmap en zet de commit-hash in de PR; dry-runs mogen wel met een
vuile werkmap, om te kunnen itereren.
