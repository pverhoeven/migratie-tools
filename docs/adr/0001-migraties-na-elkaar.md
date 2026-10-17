# Migraties na elkaar, transformaties mogen samen

Een migratie mag meerdere transformaties bevatten (bv. een cruft update en een
OpenRewrite-recept), in een vaste volgorde. Sommige wijzigingen zijn alleen samen groen,
zoals een nieuwe Spring Boot-parent uit het template en de codeaanpassingen die daarbij
horen. Los uitgerold zou dat bij elke service handwerk opleveren. Merge-conflicten
voorkomen we niet door transformaties te scheiden, maar door per service hooguit één
migratie-PR tegelijk open te hebben: een nieuwe migratie start pas als de vorige
gemerged of gesloten is.

De tool bewaakt dit zelf: bij een echte run krijgt een service met een open PR van een
andere migratie de uitkomst "Wacht op vorige migratie" en geen nieuwe PR.
