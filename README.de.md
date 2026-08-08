# PB Translation Hub

*[🇬🇧 English version](README.md)*

[![Drupal](https://img.shields.io/badge/Drupal-10.x%20%7C%2011.x-blue.svg)](https://drupal.org)
[![Node.js](https://img.shields.io/badge/Node.js-18+-green.svg)](https://nodejs.org)
[![Flutter](https://img.shields.io/badge/Flutter-stable-54C5F8.svg)](https://flutter.dev)
[![MariaDB](https://img.shields.io/badge/MariaDB-10.5+-003545.svg)](https://mariadb.org)

Ein selbst gehosteter Übersetzungsserver, der dem [Project Browser Localizer](https://drupal.org/project/pb_localizer)-Drupal-Modul lokalisierte Metadaten für den Drupal Project Browser bereitstellt.

> Dies ist die **Cloudron-paketierte** Variante. Siehe [CLOUDRON_DEPLOYMENT.de.md](CLOUDRON_DEPLOYMENT.de.md),
> um sie auf einer Cloudron-Instanz zu installieren. Für das ursprüngliche Docker-Compose-Deployment
> siehe das [unveränderte Original-Repo](https://github.com/nodedropweb/pb_translation_hub).

---

## Architektur

```
┌─────────────────────────────────────────────┐
│                 Drupal-Site                 │
│  Project Browser → pb_localizer-Modul       │
│           │ JSON-Anfrage                    │
└───────────┼─────────────────────────────────┘
            │
┌───────────▼─────────────────────────────────┐
│              PB Translation Hub             │
│                                             │
│  Flutter-Admin-UI  ←→  Node.js-Server       │
│       :5173               :9901             │
│                            │                │
│                      ┌─────▼──────┐         │
│                      │  MariaDB   │         │
│                      └────────────┘         │
│                       + JSON-Backups        │
└─────────────────────────────────────────────┘
            │
┌───────────▼─────────────────────────────────┐
│             drupal.org JSON:API              │
│   Maßgebliche Quelle für Modul-Metadaten    │
└─────────────────────────────────────────────┘
```

---

## Features

- **KI-Massenübersetzung** — übersetzt Tausende Module via Google Gemini mit Kostenschätzung und jederzeit stoppbarem Lauf
- **Shadow-API** — liefert übersetzte Modul-Metadaten als Drop-in-Ersatz für die Drupal.org-JSON:API
- **Menschliche Review-Warteschlange** — Side-by-Side-Split-Diff (Original oben, korrigierte Version unten), Ein-Klick-Produktionsfreigabe; nur für Nutzer mit Rolle `reviewer` oder `admin`
- **Rollenbasierte Zugriffskontrolle** — `translator`-Nutzer arbeiten ausschließlich im Editor; `reviewer` und `admin` haben Zugriff auf die Review-Warteschlange
- **Nutzerverwaltung** — Admin-Panel zum Aktivieren wartender Nutzer (mit Rollenauswahl), Verwalten aktiver Nutzer (Deaktivieren / Löschen) und ein 4-Schritte-Selbstregistrierungs-Flow
- **Stale-Erkennung** — MD5-basierte Erkennung englischer Quelländerungen, die Übersetzungen ungültig machen
- **Intelligente Suche** — SQL-bewertete Suche (exakt > Präfix > enthält) mit Status-Filtern (Priorität, Review, Veraltet, Übersetzt)
- **Einzelprojekt-Sync** — sofortige Aktualisierung der Metadaten eines Moduls von Drupal.org ohne vollständigen Sync
- **Sync-Fortschritt** — Live-Fortschrittsbalken mit Gesamt-Modulzahl aus der ersten Drupal.org-API-Antwort
- **DB-Migrationssystem** — nummerierte SQL-Migrationen in `server/migrations/`, automatisch beim Server-Start angewendet
- **Konfetti-Feiern** — optionales animiertes Konfetti bei Speichern/Freigeben (Umschalter in den Einstellungen), mit 900-ms-Verzögerung vor der Navigation, damit der Effekt sichtbar bleibt
- **Splash-Screen** — gebrandeter HTML-Preloader mit mindestens 2200 ms Anzeigedauer
- **Glassmorphism-UI** — Dark-Mode-first Flutter-Interface mit dynamischen Unsplash-Hintergründen und mehreren Farbthemen
- **Zweisprachige Filter-Labels** — jeder Dashboard-Filter zeigt das deutsche Label (fett, 13 px) und das englische Label (kleiner, 10 px) übereinander
- **Tastatur-first-Workflow** — `Strg+Alt+S` Speichern & Weiter, `Strg+Enter` Freigeben, und mehr
- **DSGVO-konformes Hilfe-Center** — Consent-gated Video-Einbettungen, keine externen Requests ohne Nutzeraktion

---

## Erste Schritte

### Voraussetzungen
- Docker + Docker Compose (empfohlen)
- *Oder:* Node.js ≥ 18, MariaDB ≥ 10.5, Flutter Stable SDK

### Docker (empfohlen)
```bash
cd /var/www/pb_translation_hub
docker compose up -d --build
```
App erreichbar unter `http://localhost:5173`. Backend-API unter `http://localhost:9901`.

### Manueller Dev-Start
```bash
./hubctl.sh start
```
`./hubctl.sh stop | restart | status | logs` zur Verwaltung der Services nutzen.

Siehe [FLUTTER_DOCUMENTATION.de.md](./FLUTTER_DOCUMENTATION.de.md) für Flutter-spezifische Dev-Anweisungen.

---

## Konfiguration

`server/.env.example` nach `server/.env` kopieren und setzen:

```ini
UNSPLASH_ACCESS_KEY=...
UNSPLASH_SECRET_KEY=...
DB_HOST=127.0.0.1
DB_USER=pb_hub
DB_PASSWORD=...
DB_NAME=pb_translation_hub
JWT_SECRET=...
GEMINI_API_KEY=...
```

---

## Ports

| Service | Port |
|---|---|
| Flutter-Frontend (Dev) | 5173 |
| Flutter-Frontend (Docker) | 5173 → nginx:80 |
| Node.js-Backend | 9901 |

Um den Docker-Host-Port zu ändern, `docker-compose.yml` unter dem `client:`-Service bearbeiten.

---

## Dokumentation

| Datei | Inhalt |
|---|---|
| [FLUTTER_DOCUMENTATION.de.md](./FLUTTER_DOCUMENTATION.de.md) | Flutter-Client im Detail: Screens, Quill-Editoren, Bild-Loading, CORS, Android, Themes, Docker-Build |
| [AGENTS.de.md](./AGENTS.de.md) | Technische Referenz für KI-Agenten/Entwickler: Aufbau, DB-Schema, API-Endpunkte, Widget-Muster |
| [DATABASE.de.md](./DATABASE.de.md) | Datenbankschema, Migrationssystem, Backup-Strategie |
| [DATA_STRUCTURE.de.md](./DATA_STRUCTURE.de.md) | JSON-Datenformen für Projekte und Übersetzungen |
| [DOCUMENTATION.de.md](./DOCUMENTATION.de.md) | Architektur-, Workflow- und Feature-Überblick |
| [DEPLOYMENT.de.md](./DEPLOYMENT.de.md) | Produktions-Deployment mit Docker + rsync, Rolling Restart, DB-Backup |
| [CLOUDRON_DEPLOYMENT.de.md](./CLOUDRON_DEPLOYMENT.de.md) | Cloudron-Deployment: Installation, Datenimport, Update |
| [CONTRIBUTING.de.md](./CONTRIBUTING.de.md) | Richtlinien für Mitwirkende |
| [CHANGELOG.de.md](./CHANGELOG.de.md) | Versionshistorie und Änderungsprotokoll |
