# Voorbeeld

Een cruft-template voor een Spring Boot-service met Helm-chart, en twee services
die eruit gegenereerd zijn, om migraties lokaal mee te oefenen.

```bash
voorbeeld/opzetten.sh          # template en services in work/voorbeeld/
voorbeeld/wijzig-template.sh   # vier template-commits (zie wijzigingen/)
./achterstand.sh work/voorbeeld/services/*
./local.sh voorbeeld/cruft-update.env \
    work/voorbeeld/services/bestel-service work/voorbeeld/services/klant-service
```

De template-commits: actuator en health-probes, Spring Boot 3.5.7, logging op WARN,
resources in de Helm-chart.

- **bestel-service** heeft eigen aanpassingen die niet botsen met het template; de
  migratie geeft vier commits, één per template-commit, en een groene build.
- **klant-service** heeft de logging op `DEBUG` gezet: de update stopt bij de
  template-commit "logging op warn" met een conflict in `application.properties`.

Het conflict afmaken: open `work/klant-service` in IntelliJ, kies *Git → Resolve
Conflicts…* en kies in `application.properties` een waarde (of haal de markers met de
hand weg en doe `git add`). Ga daarna verder:

```bash
./local.sh --verder voorbeeld/cruft-update.env klant-service
```

Of in een eigen clone, zoals je dat met een project in IntelliJ zou doen:

```bash
git clone work/voorbeeld/services/klant-service /tmp/klant-service
cd /tmp/klant-service
/pad/naar/migratie-tools/in-repo.sh /pad/naar/migratie-tools/voorbeeld/cruft-update.env
```

Een migratie met een recept (uit `recepten/`) verwijdert de debug-regel uit de eigen
klasse `Bestellingen` van bestel-service:

```bash
./local.sh voorbeeld/debug-opruimen.env work/voorbeeld/services/bestel-service
```

De wekelijkse opschoning probeer je op bestel-service, die rommel heeft in `BestelService`
en `BestelServiceTest`:

```bash
./local.sh voorbeeld/opschoning.env work/voorbeeld/services/bestel-service
git -C work/bestel-service show
```

| Rommel in de service | Recept |
|---|---|
| ongebruikte imports (`Map`, en `Autowired` na het weghalen) | `RemoveUnusedImports` |
| ongebruikt privéveld `teller` | `RemoveUnusedPrivateFields` |
| `@Autowired` op de enige constructor | `NoAutowiredOnConstructor` |
| `new ArrayList<String>(…)` | `UseDiamondOperator` |
| ongebruikte variabele `ongebruikt` | `RemoveUnusedLocalVariables` |
| `LOG.info("regels: " + …)` | `ParameterizedLogging` |
| `if (…) return true; else return false;` | `SimplifyBooleanReturn` |
| `toString()` zonder `@Override` | `MissingOverrideAnnotation` |
| `e.printStackTrace()` | `PrintStackTraceToLogError` |
| `public` testklasse en testmethodes | `JUnit5BestPractices` |

Draai je de opschoning daarna nog een keer, dan is de uitkomst "Ongewijzigd".

Een eigen template-wijziging proberen: pas `work/voorbeeld/template` aan, commit op
`main` en draai de migratie opnieuw. Helm-templates in `chart/templates/` worden niet
door cookiecutter gerenderd (`_copy_without_render`), omdat ze zelf `{{ }}` gebruiken.
