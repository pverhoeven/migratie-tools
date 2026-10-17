# migratie-tools

Gereedschap om wijzigingen gecontroleerd uit te rollen over alle services in een
GitLab-groep, migratie na migratie, met per service een eigen PR.

## Language

### Wat er gemigreerd wordt

**Service**:
Een Maven-repo in de GitLab-groep die niet op de uitsluitlijst staat, al dan niet uit
het template gegenereerd.
_Avoid_: project, applicatie, repo (als het om de scope gaat)

**Template-service**:
Een service die uit het template is gegenereerd en de template-versies volgt.
_Avoid_: cruft-service, gegenereerde service

**Uitsluitlijst**:
De repo's in de groep die nooit als service gelden, voor geen enkele migratie
(bv. libraries).

**Template**:
Het centrale cruft-template, in een eigen git-repo, waaruit template-services zijn
gegenereerd. Het template is de bron van de bestanden die het genereert.

**Template-versie**:
Een tag in de repo van het template.

**Achterstand**:
Het aantal template-versies dat een template-service achterloopt op de nieuwste
template-versie.

### Hoe er gemigreerd wordt

**Migratie**:
Een vastgepinde wijziging van één of meer transformaties in een vaste volgorde, die
over de services wordt uitgerold en per service hooguit één PR oplevert.
_Avoid_: run, update, stappen-combinatie

**Run**:
Eén uitvoering van een migratie over de services, als dry-run of echt. Een migratie
kan meerdere runs hebben.

**Transformatie**:
Het deel van een migratie dat een service wijzigt: een template-update of een recept.
_Avoid_: stap

**Recept**:
Een OpenRewrite-recept, in YAML of Java, dat in deze repo wordt beheerd.
_Avoid_: recipe, rewrite-regel

**Controle**:
Een toets die na de transformatie bepaalt of de wijziging van een service door mag;
een controle wijzigt zelf niets.
_Avoid_: stap, check, gate

### Uitkomst per service

**Gewijzigd**:
De transformatie heeft iets veranderd en alle controles zijn groen.

**Ongewijzigd**:
De service is van toepassing, maar de transformatie verandert niets.

**Niet van toepassing**:
Niet al de transformaties van de migratie kunnen op deze service; de migratie is niet
voor deze service bedoeld.
_Avoid_: overgeslagen

**Handwerk nodig**:
De migratie kon niet automatisch worden afgerond (conflict of rode controle) en een
mens moet de service afmaken.
_Avoid_: overgeslagen, mislukt

**Wacht op vorige migratie**:
Voor deze service staat nog een PR van een andere migratie open; een latere run pakt
hem op.

**Werklijst**:
De services met uitkomst "Handwerk nodig" na een run van een migratie.
