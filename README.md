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
