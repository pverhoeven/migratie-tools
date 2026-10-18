# Een template-variabele omzetten los van de cruft update

Een template-variabele achteraf omzetten (bv. `liquibase` aan of uit bij één service) doet
`cruft-zet.sh`, niet de cruft update. Een cruft update past alleen wijzigingen van het
template toe; een variabele die in `.cruft.json` wordt omgezet, levert daar niets op,
omdat de oude en de nieuwe stand dan allebei met de nieuwe waarde worden gegenereerd.
`cruft-zet.sh` houdt juist de template-commit vast en verandert alleen de context: het
genereert het template op de commit van de service met de oude en met de nieuwe waarde,
en merget dat verschil 3-way, met dezelfde code als de cruft update (`lib/template.sh`).
Daardoor bevat de wijziging alleen het effect van de variabele, ook als de service
achterloopt op het template, en blijven cruft update en omzetten losse commits.

Alleen variabelen die veilig om te zetten zijn: geen private variabelen, geen afgeleide
variabelen (standaardwaarde met `{{ }}`) en geen variabelen waar andere van afgeleid zijn.
Bij die laatste twee zouden de afgeleide waarden in `.cruft.json` niet meeveranderen.

Meestal is het een keuze per service: dan gebruik je `cruft-zet.sh`, met de branch
`migratie/cruft-zet-<variabele>`, zodat hij meetelt voor "per service hooguit één open
migratie-PR" (ADR 0001). Voor een feature die veel services tegelijk nodig hebben, kan het
ook in een migratie (`CRUFT_ZET`), na de cruft update en vóór het recept, met dezelfde
transformatie (`transformaties/cruft-zet.sh`). `ALLEEN_MET_DEPENDENCY` beperkt zo'n
migratie dan tot de services die het betreft; zonder die regel zou de variabele bij alle
services omgaan.

Overwogen: `cruft update --variables-to-update`, dat het omzetten combineert met een
update naar de nieuwste stand in één patch, met dezelfde nadelen als in ADR 0004.
