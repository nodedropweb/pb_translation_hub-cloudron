# Deployment-Guide: PB Translation Hub

*[🇬🇧 English version](DEPLOYMENT.md)*

> **Dieses Repo ist die Cloudron-paketierte Variante.** Wenn du auf Cloudron deployst, siehe
> stattdessen [CLOUDRON_DEPLOYMENT.de.md](CLOUDRON_DEPLOYMENT.de.md) — dieses Dokument
> beschreibt das ursprüngliche Docker-Compose- + `deploy.sh`-Deployment des
> [unveränderten Original-Repos](https://github.com/nodedropweb/pb_translation_hub), das auf
> Cloudron nicht mehr gilt.

Dieses Dokument beschreibt den vollständigen Deployment-Prozess für den PB Translation Hub auf dem Produktionsserver.

## Infrastruktur-Überblick

| Komponente | Detail |
|---|---|
| **Produktionsserver** | `drupaltutorials.de` |
| **App-URL** | `https://pb.drupaltutorials.de` |
| **App-Verzeichnis (Server)** | `/home/joachim/pb_translation_hub` |
| **Betriebssystem** | Ubuntu 26.04 LTS |
| **Docker** | 29.4.2 |
| **Docker Compose** | v5.1.3 |
| **Nginx** | Let's-Encrypt-SSL via Certbot |
| **Systemd-Service** | `pb-translation-hub.service` |

## Architektur (Docker)

```
Internet → Nginx (443 HTTPS) → localhost:5173 → [Flutter-Web-Container]
                                                       ↓ /api/-Proxy
                                               [Node.js-Server-Container :9901]
                                                       ↓
                                               [MariaDB-Container]
                                                 (Docker-Volume: db_data)
```

### Container
| Service | Image | Interner Port | Beschreibung |
|---|---|---|---|
| `db` | `mariadb:11.8` | 3306 | Datenbank (persistentes Docker-Volume) |
| `server` | gebaut aus `./server` | 9901 | Node.js/Express-API (PM2-Cluster) |
| `client` | gebaut aus `./flutter_client` | 80 | Flutter Web + Nginx-Proxy |

---

## 1. Voraussetzungen

- **Docker** ≥ 24 mit **Docker Compose** (auf dem Produktionsserver vorhanden)
- **SSH-Zugriff** auf den Server (schlüsselbasiert, kein Passwort nötig)
- `rsync` lokal installiert
- Gültige API-Keys auf dem Server (Unsplash, Gemini/Google AI)

---

## 2. Deployment via deploy.sh

Das Hilfsskript `deploy.sh` im Projekt-Root automatisiert den Deployment-Prozess.

```bash
# Von der lokalen WSL-Instanz aus (von /var/www/pb_translation_hub)
./deploy.sh
```

### Rolling Restart

`deploy.sh` führt einen **Rolling Restart** durch — der Datenbank-Container geht nie offline:

1. Dateien werden per rsync auf den Server übertragen (Live-Daten werden nie überschrieben).
2. Der **Server-Container** wird neu gebaut und neu gestartet. Beim Start wendet `db_migrate.js` automatisch alle ausstehenden DB-Migrationen an.
3. Der **Client-Container** wird danach neu gebaut und neu gestartet.
4. Der **DB-Container** bleibt während des gesamten Prozesses online.

Das bedeutet: Die Datenbank ist während des gesamten Deploys verfügbar, es gibt kein Downtime-Fenster für die Datenschicht.

### Optional: DB-Backup vor dem Deploy

Um vor dem Anwenden von Schema-Änderungen ein Datenbank-Backup zu erstellen:

```bash
./deploy.sh --db-backup
```

Mit dem Flag `--db-backup` führt das Skript einen `mysqldump` im `db`-Container aus und speichert den komprimierten Dump unter `~/backups/pb_db_YYYYMMDD_HHMMSS.sql.gz` auf dem Produktionsserver, bevor irgendwelche Container neu gebaut werden.

### Migrations-Log

Nachdem der Server-Container gestartet ist, wartet das Deploy-Skript auf das Container-Log, um zu bestätigen, dass die Migrationen abgeschlossen sind:

```
[Migration] ✓ 004_users_requested_role.sql angewendet
[Migration] Datenbank ist aktuell — keine ausstehenden Migrationen.
```

Schlägt eine Migration fehl, beendet sich der Server mit Code 1, und das Deploy-Skript meldet den Fehler.

---

## 3. Manuelles rsync (Alternative)

```bash
rsync -avz --progress \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude 'flutter_client/build' \
  --exclude 'flutter_client/.dart_tool' \
  --exclude 'flutter_client/.flutter-plugins*' \
  --exclude 'flutter_client/.metadata' \
  --exclude 'flutter_client/.idea' \
  --exclude 'flutter_client/android' \
  --exclude 'flutter_client/ios' \
  --exclude 'flutter_client/macos' \
  --exclude 'flutter_client/windows' \
  --exclude 'flutter_client/linux' \
  --exclude 'server/data' \
  --exclude 'server/uploads' \
  --exclude 'server/.env' \
  --exclude 'server/*.log' \
  --exclude 'server/*.pid' \
  --exclude 'scratch' \
  --exclude 'test-results' \
  --exclude 'tests' \
  /var/www/pb_translation_hub/ joachim@drupaltutorials.de:/home/joachim/pb_translation_hub/
```

---

## 4. Umgebungskonfiguration (`server/.env`)

Die `.env`-Datei existiert **nur auf dem Produktionsserver** (`/home/joachim/pb_translation_hub/server/.env`) und wird nie ins Git committed.

```env
# Unsplash API
UNSPLASH_APP_ID=...
UNSPLASH_ACCESS_KEY=...
UNSPLASH_SECRET_KEY=...

# Datenbank (DB_HOST wird von docker-compose.yml auf 'db' überschrieben)
DB_HOST=db
DB_USER=pb_hub
DB_PASSWORD=...
DB_NAME=pb_translation_hub

# Sicherheit
JWT_SECRET=...

# Google AI
GEMINI_API_KEY=...
```

**Hinweis:** `DB_HOST` wird über den `environment:`-Abschnitt in `docker-compose.yml` auf `db` gesetzt und überschreibt den `.env`-Wert innerhalb von Docker automatisch.

---

## 5. DB-Migrationssystem

Schema-Änderungen werden als nummerierte SQL-Dateien in `server/migrations/` verwaltet. Der Migrations-Runner `server/db_migrate.js` wird bei jedem Start des Server-Containers automatisch aufgerufen.

### Funktionsweise

1. Legt die `schema_migrations`-Tabelle an, falls sie nicht existiert.
2. Liest alle `.sql`-Dateien in `server/migrations/`, numerisch sortiert.
3. Überspringt bereits in `schema_migrations` verzeichnete Migrationen.
4. Führt ausstehende Migrationen innerhalb einer Transaktion aus (Rollback bei Fehlschlag).
5. Beendet den Node.js-Prozess mit Code `1` bei Fehlschlag — kein stilles Überspringen.

### Neue Migration anlegen

```bash
# Nächste freie Nummer wählen und Datei anlegen:
cat > server/migrations/005_meine_aenderung.sql << 'EOF'
-- Migration 005: Beschreibung
ALTER TABLE translations ADD COLUMN reviewer_note TEXT DEFAULT NULL;
EOF
```

**Regeln:**
- Dateiname muss `NNN_beschreibung.sql` sein (führende Nullen, snake_case).
- Nur additive Änderungen: `ADD COLUMN` (**ohne** `IF NOT EXISTS` — MariaDB-only, auf MySQL 8/Cloudron nicht unterstützt, siehe [CLOUDRON_DEPLOYMENT.de.md, §4](CLOUDRON_DEPLOYMENT.de.md#4-mariadb--mysql-8-kompatibilitätshinweise)), `CREATE TABLE IF NOT EXISTS`.
- Keine `DROP`- oder `RENAME`-Operationen ohne explizite Abstimmung.
- Jede Migration läuft in einer Transaktion.

### Migration auf Produktion deployen

```bash
# Empfohlen: DB vor Schema-Änderungen sichern
./deploy.sh --db-backup
```

Der Rolling Restart stellt sicher, dass der DB-Container online bleibt, während der Server-Container neu gebaut wird. Migrationen laufen automatisch beim Server-Start.

---

## 6. Systemd-Service

Die Systemd-Unit `pb-translation-hub.service` startet die Docker-Container automatisch beim Boot.

```bash
# Status prüfen
sudo systemctl status pb-translation-hub

# Starten / Stoppen / Neustarten
sudo systemctl start pb-translation-hub
sudo systemctl stop pb-translation-hub
sudo systemctl restart pb-translation-hub

# Beim Boot aktivieren
sudo systemctl enable pb-translation-hub
```

Die Service-Datei liegt unter `/etc/systemd/system/pb-translation-hub.service`.

---

## 7. Nginx-Konfiguration (bereits vorhanden)

Nginx ist auf dem Produktionsserver bereits konfiguriert und proxied `pb.drupaltutorials.de` → `localhost:5173`:

```nginx
server {
    server_name pb.drupaltutorials.de;

    location / {
        proxy_pass http://localhost:5173;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # SSL via Certbot (Let's Encrypt)
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/pb.drupaltutorials.de/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pb.drupaltutorials.de/privkey.pem;
}
```

> Für Avatar-Uploads: `client_max_body_size 10M;` zum Nginx-Server-Block hinzufügen, falls noch nicht vorhanden.

---

## 8. Docker-Build-Prozess

### Server-Container (Node.js)

```
server/Dockerfile → node:22-alpine → npm install --production → PM2-Cluster
```

PM2 läuft im Cluster-Modus (`-i max`) und nutzt alle verfügbaren CPU-Kerne.

Die `server/.dockerignore` schließt aus: `node_modules`, `data/`, `uploads/`, `.env`, `*.log`, Dev-Skripte.

### Client-Container (Flutter Web)

```
flutter_client/Dockerfile → ghcr.io/cirruslabs/flutter:stable → flutter build web --release → nginx:alpine
```

Der Flutter-Build kann 3–10 Minuten dauern (dart2js-Kompilierung). Dank Rolling Restart bleiben Server und Datenbank während dieses Builds verfügbar.

Die `flutter_client/.dockerignore` schließt aus: `build/`, `.dart_tool/`, alle mobilen Plattform-Verzeichnisse (`android/`, `ios/`, `macos/`, `windows/`, `linux/`).

---

## 9. Datenbank-Backup

Die Datenbank läuft in einem Docker-Volume (`db_data`).

### Backup manuell erstellen (auf dem Produktionsserver)

```bash
docker exec pb_translation_hub-db-1 \
  mysqldump -u pb_hub -p'PASSWORD' pb_translation_hub \
  | gzip > ~/backups/pb_db_$(date +%Y%m%d_%H%M%S).sql.gz
```

### Backup via deploy.sh erstellen

```bash
./deploy.sh --db-backup
# Speichert nach ~/backups/ auf dem Produktionsserver
```

### Aus Backup wiederherstellen

```bash
gunzip < backup.sql.gz | docker exec -i pb_translation_hub-db-1 \
  mysql -u pb_hub -p'PASSWORD' pb_translation_hub
```

### Erstinitialisierung auf einem neuen Server (leeres Volume)

Beim ersten `docker compose up` importiert MariaDB automatisch `server/data/db_export.sql.gz` (via `docker-entrypoint-initdb.d`). Danach laufen die Migrationen auf dem exportierten Schema, um es auf den aktuellen Stand zu bringen. Beide zusammen garantieren eine konsistente Datenbank auf jedem neuen Server.

---

## 10. Fehlerbehebung

```bash
# Container-Logs
docker compose logs -f server
docker compose logs -f client

# Container-Status
docker compose ps

# In einen Container einsteigen
docker exec -it pb_translation_hub-server-1 sh
docker exec -it pb_translation_hub-db-1 bash

# Ohne Cache neu bauen (nach größeren Dependency-Änderungen)
docker compose build --no-cache
docker compose up -d
```

**Häufige Probleme:**

- **Unsplash-API nicht erreichbar:** Rate-Limit (50 Req/h im Sandbox-Modus) oder falscher Key → `docker compose logs server` prüfen.
- **Avatare nicht persistiert:** Volume-Mount `./server/uploads:/app/uploads` in `docker-compose.yml` prüfen.
- **Flutter-Build schlägt fehl:** `docker compose logs client` prüfen — meist fehlende Pub-Packages oder eine Dart-SDK-Inkompatibilität.
- **Migrationsfehler beim Start:** Server beendet sich mit Code 1. `docker compose logs server` auf den konkreten SQL-Fehler prüfen. Migrationsdatei korrigieren und neu deployen.

---

## 11. Drupal pb_localizer verbinden

Nach dem Deployment Drupal-Sites mit dem Hub verbinden:

```bash
drush config:set pb_localizer.settings hub_url "https://pb.drupaltutorials.de" --yes
drush config:set pb_localizer.settings hub_port "443" --yes
```
