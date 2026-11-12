# redmine-portfolio

Lokale Redmine-Installation mit PostgreSQL und Shadcn.

Voraussetzungen sind Docker mit Compose v2 und OpenSSL.

```sh
./scripts/setup-secrets
docker compose up --build -d
docker compose logs -f redmine
```

Nach dem Start ist Redmine unter [localhost:3000](http://localhost:3000) erreichbar.
Der Benutzername lautet `admin`. Das initiale Passwort steht in `.env`
unter `PORTFOLIO_ADMIN_PASSWORD`. Beim ersten Start lädt Redmine die
deutsche Standardkonfiguration.

`docker compose config --quiet` prüft die Konfiguration, ohne die Werte
aus `.env` auszugeben. `docker compose down` stoppt die Umgebung.
Datenbank und Uploads liegen in benannten Volumes und bleiben beim
normalen Stoppen und Neuerstellen der Container erhalten.

## Demodaten

Beim ersten Start entstehen das Projektportfolio, 15 private Projekte,
fünf Demobenutzer und drei Tickets. Die Passwörter stehen in `.env`.

| Login | Rolle |
|---|---|
| `admin` | Systemadministration |
| `lead_geo` | Projektleitung Geoinformation |
| `member_geo` | Projektmitarbeiter Geoinformation |
| `reader_geo` | Portfolio-Leser Geoinformation |
| `lead_it` | Projektleitung Informatik |
| `nonmember` | Benutzer ohne Projektmitgliedschaft |

`docker compose exec -T redmine rails runner scripts/bootstrap.rb`
führt die Initialisierung erneut aus. Bereits initialisierte Demodaten
und Projektänderungen bleiben erhalten.

## Betriebsprüfung

```sh
docker compose config --quiet
docker compose ps
curl -fsS -o /dev/null http://localhost:3000/login
```

PostgreSQL muss als `healthy` erscheinen. Prüfe auf der Login-Seite
den Theme-Wechsel im oberen Menü und nach `docker compose down` und
`docker compose up -d` die Anmeldung und die vorhandenen Demoprojekte.
