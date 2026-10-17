# Het template blijft de bron van zijn eigen bestanden

Een migratie die bestanden van het template raakt (bv. de `pom.xml` van een
template-service), bevat altijd een template-update (na een wijziging in het template); een recept past bij
template-services alleen code aan die de service zelf bezit. Anders wijken services
stilletjes af van het template en moet elke latere template-update daar overheen
patchen, waardoor conflicten zich opstapelen. Bij services zonder template geldt deze
beperking niet.
