# Voorbeeld

Een cruft-template voor een Spring Boot-service met Helm-chart, en twee services
die eruit gegenereerd zijn, om migraties lokaal mee te oefenen.

```bash
voorbeeld/opzetten.sh          # template (v1.0.0) en services in work/voorbeeld/
voorbeeld/wijzig-template.sh   # template v1.1.0 en v1.2.0 (zie wijzigingen/)
./local.sh voorbeeld/template-v1.2.0.env \
    work/voorbeeld/services/bestel-service work/voorbeeld/services/klant-service
```

- **bestel-service** heeft eigen aanpassingen die niet botsen met het template; de
  migratie geeft twee commits (`template: v1.1.0`, `template: v1.2.0`) en een groene build.
- **klant-service** heeft de logging op `DEBUG` gezet, terwijl v1.2.0 die op `WARN`
  zet: de update stopt bij v1.2.0 met een conflict in `application.properties`.

Een migratie met een recept (uit `recepten/`) verwijdert de debug-regel uit de eigen
klasse `Bestellingen` van bestel-service:

```bash
./local.sh voorbeeld/debug-opruimen.env work/voorbeeld/services/bestel-service
```

Een eigen template-wijziging proberen: pas `work/voorbeeld/template` aan, commit,
tag (bv. `v1.3.0`) en maak een migratiebestand met `TEMPLATE_VERSION=v1.3.0`.
Helm-templates in `chart/templates/` worden niet door cookiecutter gerenderd
(`_copy_without_render`), omdat ze zelf `{{ }}` gebruiken.
