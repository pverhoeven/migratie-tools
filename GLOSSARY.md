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
Een service die uit het template is gegenereerd en de template-standen volgt.
_Avoid_: cruft-service, gegenereerde service

**Template-variabele**:
Een keuze per template-service, vastgelegd in `.cruft.json` (bv. `db`, `liquibase`),
waarmee het template de service anders opbouwt.
_Avoid_: flag (in de code), cookiecutter-variabele

**Uitsluitlijst**:
De repo's in de groep die nooit als service gelden, voor geen enkele migratie
(bv. libraries).

**Template**:
Het centrale cruft-template, in een eigen git-repo, waaruit template-services zijn
gegenereerd. Het template is de bron van de bestanden die het genereert.

**Template-stand**:
Een commit op de hoofdlijn van de template-repo. De nieuwste template-stand is de
laatste commit op de standaardbranch.
_Avoid_: template-versie (er zijn geen tags)

**Achterstand**:
Het aantal template-standen dat een template-service achterloopt op de nieuwste
template-stand.

### Hoe er gemigreerd wordt

**Migratie**:
Een wijziging van één of meer transformaties in een vaste volgorde, die over de
services wordt uitgerold en per service hooguit één PR oplevert.
_Avoid_: run, update, stappen-combinatie

**Run**:
Eén uitvoering van een migratie over de services, als dry-run of echt. Een migratie
kan meerdere runs hebben.

**Transformatie**:
Het deel van een migratie dat een service wijzigt: een cruft update of een recept.
_Avoid_: stap

**Cruft update**:
De transformatie die een template-service bijwerkt naar de nieuwste template-stand,
zoals het commando `cruft update` dat doet, maar per template-stand en met echte
git-conflicten.
_Avoid_: template-update

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
