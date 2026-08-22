# AGENTS.md — Referenz für Entwickler & KI-Agenten

*[🇬🇧 English version](AGENTS.md)*

Technische Landkarte des PB Translation Hub für Entwickler und KI-Coding-Agenten.

> **Dies ist das Cloudron-paketierte Repo.** Es läuft als ein einzelner Container hinter Cloudrons
> eigenem Reverse-Proxy (siehe [CLOUDRON_DEPLOYMENT.de.md](CLOUDRON_DEPLOYMENT.de.md)), nicht als
> das Docker-Compose-Dreier-Container-Setup, das diese Datei ansonsten beschreibt
> (server/client/db). Wo sich beide unterscheiden, ist das inline vermerkt.

---

## Stack

| Ebene | Technologie |
|---|---|
| Frontend | Flutter (Dart) — Web, Desktop und Tablet |
| Backend | Node.js (Express) |
| Datenbank | MariaDB 11.8 (docker-compose) / MySQL 8.0.31 (Cloudron-Addon) + JSON-Datei-Backups |
| KI | Google Gemini (Massenübersetzung) |
| Produktions-Ausgabe | docker-compose: Nginx-Container, Port 5173. Cloudron: nginx im einzelnen App-Container, Port 3000 (Cloudrons eigener Reverse-Proxy stellt das öffentlich bereit) |

---

## Repository-Aufbau

```
pb_translation_hub-cloudron/
├── CloudronManifest.json    # Cloudron-App-Manifest (id, httpPort 3000, Addons: mysql + localstorage)
├── Dockerfile                # Single-Container-Build: flutter build web (Stage 1) + node/nginx auf cloudron/base (Stage 2)
├── start.sh                  # Container-Entrypoint: chown /app/data, backgroundet node, execs nginx
├── nginx/app.conf             # nginx-Site-Config (adaptiert aus flutter_client/nginx.conf, proxied auf 127.0.0.1:9901)
├── server/
│   ├── index.js             # Express-App-Einstieg; lädt Routen, startet Migrationen
│   ├── db_migrate.js        # DB-Migrations-Runner (automatisch beim Start aufgerufen)
│   ├── migrations/          # Nummerierte SQL-Migrationsdateien
│   │   ├── 001_initial_schema.sql
│   │   ├── 002_users_deepl_key.sql
│   │   ├── 003_users_registration_fields.sql
│   │   ├── 004_users_requested_role.sql
│   │   ├── 005_create_glossary_terms.sql
│   │   ├── 006_suggestion_type_deepl.sql       # legt auch translation_suggestions an (nachgetragen — siehe Datei)
│   │   ├── 007_glossary_word_forms.sql
│   │   ├── 008_semver_columns.sql
│   │   └── 009_sync_events.sql
│   ├── routes/
│   │   ├── auth.js          # Login, Registrierung, Registrierungsstatus
│   │   ├── projects.js      # Projektliste, Suche, Einzelprojekt-Sync
│   │   ├── translations.js  # Übersetzungen speichern/laden
│   │   ├── ai.js            # Massenübersetzung, Kostenschätzung
│   │   ├── sync.js          # Vollständiger Sync von Drupal.org
│   │   ├── admin.js         # Nutzerverwaltung (wartend, aktiv, deaktivieren, löschen)
│   │   └── categories.js    # Kategorienverwaltung
│   ├── migrate_to_mysql.js  # Einmalige JSON-→-MariaDB-Migration
│   ├── languages.json       # Liste unterstützter Zielsprachen
│   ├── watch_stale.sh       # Shell-Skript zur Überwachung veralteter Übersetzungen
│   ├── data/                 # nur lokale Entwicklung / docker-compose — auf Cloudron ist das /app/data (localstorage-Addon), nicht server/data
│   │   ├── metadata/        # JSON-Snapshots der Drupal.org-Moduldaten
│   │   └── translations/    # Übersetzungs-Backups pro Sprache (JSON)
│   └── .env                 # Secrets (nicht committed; siehe .env.example). Auf Cloudron kommt die Konfiguration stattdessen aus den von der Plattform injizierten CLOUDRON_MYSQL_*- + CLOUDRON=1-Env-Vars
├── flutter_client/
│   ├── lib/
│   │   ├── main.dart        # App-Einstieg, ProviderScope-Wrapper
│   │   ├── router.dart      # GoRouter-Deklarationen + Rollen-Guards
│   │   ├── models/          # Data-Transfer-Objekte
│   │   ├── providers/       # Riverpod-State-Provider
│   │   │   ├── auth_provider.dart
│   │   │   ├── theme_provider.dart
│   │   │   ├── language_provider.dart
│   │   │   ├── project_provider.dart
│   │   │   └── sync_provider.dart
│   │   ├── services/        # ApiClient (Dio), TokenStorage, LogService
│   │   ├── theme/           # AppTheme, ThemeAttributes
│   │   ├── utils/           # html_sanitizer.dart, translation_prompt.dart
│   │   ├── widgets/         # Geteilte Widgets
│   │   │   ├── glass_container.dart
│   │   │   ├── module_logo.dart
│   │   │   ├── page_transition.dart      # Animierter Route-Übergang
│   │   │   ├── splash_screen.dart        # Gebrandeter Splash (min. 2200 ms)
│   │   │   ├── consent_youtube_player.dart
│   │   │   ├── ckeditor_field.dart
│   │   │   ├── search_with_autocomplete.dart
│   │   │   └── sync_progress_bar.dart
│   │   └── screens/
│   │       ├── auth/
│   │       │   ├── login_screen.dart
│   │       │   └── register_screen.dart  # 4-Schritte-Registrierungsassistent
│   │       ├── dashboard/
│   │       │   ├── dashboard_screen.dart
│   │       │   └── widgets/
│   │       │       ├── project_card.dart
│   │       │       └── dashboard_filters.dart  # Zweisprachige DE+EN Filter-Labels
│   │       ├── editor/
│   │       │   ├── editor_screen.dart
│   │       │   ├── _editor_build_methods.dart
│   │       │   ├── _editor_quill_bridge.dart
│   │       │   └── widgets/
│   │       │       ├── cost_calculator_dialog.dart
│   │       │       ├── editor_html_toolbar.dart
│   │       │       └── screenshot_alts_section.dart
│   │       ├── review/
│   │       │   ├── review_list_screen.dart  # Zeigt übersetzte Titel/Kurzbeschreibungen
│   │       │   ├── review_screen.dart       # Optimistische Navigation, Split-Diff
│   │       │   └── widgets/
│   │       │       ├── review_diff_view.dart  # Original (rot) / Korrigiert (grün)
│   │       │       └── review_sidebar.dart    # StatefulWidget mit Quell-Umschalter
│   │       ├── layout/
│   │       │   └── app_layout.dart  # Sidebar-Logo: 44×44; Topbar-Mini: 34×34
│   │       ├── categories/
│   │       │   └── categories_screen.dart
│   │       ├── profile/
│   │       │   └── profile_screen.dart
│   │       ├── help/
│   │       │   ├── help_screen.dart
│   │       │   └── crwb_study_screen.dart
│   │       └── settings/
│   │           └── settings_screen.dart  # Enthält Konfetti-Umschalter
│   ├── web/
│   │   └── index.html       # HTML-Preloader / Splash, flutter-first-frame-Listener
│   ├── Dockerfile
│   └── nginx.conf
├── hubctl.sh                  # nur lokale Entwicklung
├── deploy.sh                  # nur Docker-Compose-Deployment — auf Cloudron nicht genutzt, siehe CLOUDRON_DEPLOYMENT.de.md
├── docker-compose.yml         # nur lokale Entwicklung / Nicht-Cloudron-Deployment
└── server/.env.example
```

---

## Datenbankschema

### `projects`
| Spalte | Typ | Anmerkungen |
|---|---|---|
| `machine_name` | VARCHAR(255) PK | Eindeutiger Modul-Identifikator |
| `title` | VARCHAR(255) | Original-englischer Titel |
| `data` | LONGTEXT (JSON) | Vollständiger Drupal.org-Metadaten-Blob |
| `changed` | BIGINT | Unix-Timestamp der letzten Drupal.org-Änderung |
| `updated_at` | TIMESTAMP | Bei jedem Sync gesetzt |

### `translations`
| Spalte | Typ | Anmerkungen |
|---|---|---|
| `machine_name` | VARCHAR(255) PK | FK → projects |
| `langcode` | VARCHAR(10) PK | z. B. `de`, `fr` |
| `title` | VARCHAR(255) | Übersetzter Titel |
| `summary` | TEXT | Übersetzte Kurzbeschreibung (HTML) |
| `body` | LONGTEXT | Übersetzter Body (HTML) |
| `screenshot_alts` | TEXT (JSON) | Bild-Alt-Text-Map |
| `source_hash` | VARCHAR(32) | MD5 der englischen Quelle für Stale-Erkennung |
| `is_reviewed` | TINYINT(1) | 0 = in Review-Warteschlange; 1 = für Produktion freigegeben |
| `reviewed_by` | VARCHAR(50) | Username des Reviewers |
| `updated_at` | TIMESTAMP | Letzter Speicherzeitpunkt |

### `users`
| Spalte | Typ | Anmerkungen |
|---|---|---|
| `id` | INT AUTO_INCREMENT PK | Interne ID |
| `username` | VARCHAR(50) UNIQUE | Anmeldename |
| `password` | VARCHAR(255) | bcrypt-Hash |
| `name` | VARCHAR(100) | Anzeigename |
| `email` | VARCHAR(100) | E-Mail-Adresse |
| `role` | VARCHAR(20) Standard `'user'` | `'admin'` oder `'user'` |
| `user_type` | ENUM('translator','reviewer') Standard `'translator'` | Bestimmt Review-Warteschlangen-Zugriff |
| `requested_role` | VARCHAR(20) | Bei Registrierung angefragte Rolle |
| `target_languages` | LONGTEXT (JSON) | Array der Zielsprachen, z. B. `["de","fr"]` |
| `is_active` | TINYINT(1) Standard `0` | 0 = wartend auf Aktivierung; 1 = aktiv |
| `avatar_url` | VARCHAR(255) | Relativer Pfad unter `/uploads/avatars/` |
| `google_ai_key` | VARCHAR(255) | Persönlicher Gemini-API-Key |
| `deepl_api_key` | VARCHAR(255) | Persönlicher DeepL-API-Key |
| `ai_batch_limit` | INT Standard `5` | Max. Module pro KI-Massenlauf |
| `ai_prompt` | TEXT | Individueller KI-Übersetzungsprompt |
| `last_reviewed_project` | VARCHAR(255) | Zuletzt reviewtes Modul |
| `created_at` | TIMESTAMP | Registrierungszeitpunkt |

**Zugriffslogik:**

| `role` | `user_type` | Review-Warteschlange | Admin-Panel |
|---|---|---|---|
| `admin` | — | Ja | Ja |
| `user` | `reviewer` | Ja | Nein |
| `user` | `translator` | Nein | Nein |

### `schema_migrations`
| Spalte | Typ | Anmerkungen |
|---|---|---|
| `version` | VARCHAR(20) PK | Numerischer Versionsstring, z. B. `003` |
| `filename` | VARCHAR(255) | Migrations-Dateiname |
| `applied_at` | TIMESTAMP | Ausführungszeitpunkt |

### `priority_projects`
| Spalte | Typ | Anmerkungen |
|---|---|---|
| `machine_name` | VARCHAR(255) PK | Modul-Identifikator |
| `list_name` | VARCHAR(50) PK | z. B. `drupal11` — historischer Name, wird von der Filter-Logik nicht mehr gelesen (nur `machine_name` zählt für Listenzugehörigkeit) |

Der "Priority"-Filter (`getFilteredIndex`, `filter === 'priority'`) bedeutet: auf dieser Liste
**und** `projects.semver_max < 12000000` (noch nicht Drupal-12-kompatibel) — nicht
"unübersetzt", wie eine frühere Version dieses Filters bedeutete. Sowohl die Count-Query
(`routes/projects.js`) als auch die List-Query (`server/index.js`) müssen von `projects`
getrieben bleiben (gejoint gegen `priority_projects`), nicht von `priority_projects` allein —
eine frühere Version zählte direkt aus `priority_projects`, während die Liste über `projects`
jointe, sodass Priority-Module, die nie in `projects` gesynct wurden, gezählt, aber in der Liste
unsichtbar waren.

### `ignored_projects`
| Spalte | Typ | Anmerkungen |
|---|---|---|
| `machine_name` | VARCHAR(255) PK | Modul-Identifikator |
| `langcode` | VARCHAR(10) PK | Sprachcode |

### `site_settings`
| Spalte | Typ | Anmerkungen |
|---|---|---|
| `setting_key` | VARCHAR(100) PK | Einstellungsname |
| `setting_value` | TEXT | Wert |

Bekannte Keys: `registration_enabled` (`'1'` / `'0'`).

---

## Server-Routen

### Authentifizierung (`routes/auth.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| `POST` | `/auth/login` | Login; liefert JWT |
| `POST` | `/auth/register` | Neuen (inaktiven) Nutzeraccount anlegen |
| `GET` | `/auth/registration-status` | Liefert `{ enabled: true/false }` |

### Projekte (`routes/projects.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| `GET` | `/api/projects` | Gefilterte, paginierte Projektliste; SQL-bewertete Suche |
| `GET` | `/api/projects/:machineName` | Einzelprojekt mit Übersetzung und Vorschlägen |
| `POST` | `/api/sync/project/:machineName` | Einzelprojekt-Aktualisierung von Drupal.org |

### Übersetzungen (`routes/translations.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| `POST` | `/api/translations/:machineName` | Übersetzung speichern (Titel, Kurzbeschreibung, Body) |
| `POST` | `/api/translations/:machineName/review` | Übersetzung freigeben (setzt `is_reviewed = 1`) |
| `GET` | `/api/translations/:machineName/suggestions` | Vorschläge auflisten |
| `POST` | `/api/translations/:machineName/suggestions` | Neuen Vorschlag speichern |

### KI (`routes/ai.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| `POST` | `/api/ai/translate-bulk` | Massenübersetzung; max. 150 Module pro Request |
| `POST` | `/api/ai/estimate-cost` | Token- und Kostenschätzung vor Massenlauf |
| `POST` | `/api/ai/translate-single` | KI-Übersetzung eines einzelnen Moduls |

### Sync (`routes/sync.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| `POST` | `/api/sync/start` | Vollständigen Sync von Drupal.org starten |
| `GET` | `/api/sync/status` | Sync-Fortschritt (aktuelle Seite, Gesamtzahl aus der ersten API-Antwort) |
| `POST` | `/api/sync/stop` | Laufenden Sync stoppen |

### Admin (`routes/admin.js`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| `GET` | `/admin/users/pending` | Nutzer mit `is_active = 0` auflisten |
| `POST` | `/admin/users/:id/activate` | Nutzer aktivieren; Body `{ user_type }` weist Rolle zu |
| `GET` | `/admin/users/active` | Nutzer mit `is_active = 1` auflisten |
| `PATCH` | `/admin/users/:id/deactivate` | Aktiven Nutzer deaktivieren (sperren) |
| `DELETE` | `/admin/users/:id` | Nutzer dauerhaft löschen |

### Sonstiges

| Methode | Pfad | Beschreibung |
|---|---|---|
| `GET` | `/api/image-proxy` | Externes Bild proxen (`?url=<encoded>`); bis zu 5 Redirects |
| `POST` | `/api/unsplash/track-download` | Unsplash-Download-Tracking (API-Compliance) |
| `GET` | `/api/unsplash/random` | Zufälligen Unsplash-Hintergrund holen |
| `GET` | `/uploads/:path` | Hochgeladene Dateien ausliefern (Avatare) |

---

## Zentrale Backend-Services

### `db_migrate.js`
Wird beim Server-Start aufgerufen, bevor Routen registriert werden. Liest alle `.sql`-Dateien in `server/migrations/`, nach numerischem Präfix sortiert. Überspringt bereits in `schema_migrations` verzeichnete Versionen. Führt jede ausstehende Migration in einer Transaktion aus. Beendet den Prozess mit Code 1 bei Fehlschlag.

### `syncProjects`
Paginierter Abruf von `https://www.drupal.org/jsonapi/index/project_modules`. Enthält eine 100-ms-Verzögerung zwischen Seiten — nicht entfernen (Rate-Limit-Compliance). Die `total`-Zahl wird aus der ersten API-Antwort (`meta.count`) gelesen und in `syncProvider` für eine akkurate Fortschrittsanzeige gespeichert. Schreibt sowohl in MariaDB als auch nach `server/data/metadata/`.

### `GET /api/projects`
SQL-gestützte gefilterte Liste. Nutzt Joins, um den Status aufzulösen (`missing` / `translated` / `stale`). In-SQL-Suchbewertung: exakt > Präfix > enthält. Übersetzer und Reviewer sehen beide dieselbe Liste; die Router-Guards steuern, wer den Review-Screen öffnen kann.

### `POST /api/ai/translate-bulk`
Akzeptiert `{ machineNames, langcode }`. Gedeckelt bei 150 Modulen pro Aufruf. Das `receiveTimeout` auf dem Dio-Client für diese Route ist auf 10 Minuten gesetzt. Orchestriert die Gemini-Übersetzung für Titel, Kurzbeschreibung und Body. Speichert Ergebnisse als **Vorschläge** (nicht als Live-Übersetzungen). Unterstützt Abbruch via Per-Request-Abort-Signale.

### Performance: `res.json()` vor Datei-Write
Bei Übersetzungs-Speicher-Endpunkten wird die JSON-Antwort sofort nach Abschluss des DB-Writes an den Client gesendet. Das dateisystembasierte JSON-Backup (`fs.writeJson`) läuft asynchron im Hintergrund. Das hält die API-Antwort schnell, ohne die Datenhaltbarkeit zu opfern.

---

## Flutter-Client-Richtlinien

### Rollen-Guards in router.dart
Der GoRouter in `lib/router.dart` prüft den `user_type` des Nutzers aus `authProvider` für alle `/review*`-Routen. Nutzer mit `user_type == 'translator'` werden mit einer Toast-Meldung zu `/` umgeleitet. Admins umgehen die Prüfung.

### Theme-Attribute — niemals Farben hartkodieren
```dart
final themeState = ref.watch(themeProvider);
final attrs = AppTheme.getAttributes(themeState.themeId);
// Nutzen: attrs.brand600, attrs.bgCard, attrs.textMain, attrs.borderMain, etc.
```

### Neuen Screen hinzufügen
1. Datei unter `lib/screens/<domain>/<screen>_screen.dart` anlegen.
2. Route in `lib/router.dart` registrieren.
3. Bei Reviewer-/Admin-Pflicht einen Rollen-Guard hinzufügen.
4. Kein `const` auf Widgets, die `attrs`-Werte konsumieren.

### Alle Netzwerkbilder müssen den Server-Proxy nutzen
Niemals eine externe URL direkt an `Image.network()` oder `CachedNetworkImage` übergeben.
Immer über den Proxy leiten:
```dart
ApiClient.proxyImageUrl('https://git.drupalcode.org/project/token/-/avatar')
```
`CachedNetworkImage` nutzen (niemals bloßes `Image.network`).
`RepaintBoundary` um Vollbild-Hintergrundbilder legen.

### Modul-Logos: immer `ModuleLogo` nutzen
Für Logo-Banner auf Projektkarten `lib/widgets/module_logo.dart` nutzen:
```dart
ModuleLogo(
  machineName: project.machineName,
  logoUrl: project.logoUrl,
  fallbackLogoUrl: 'https://git.drupalcode.org/project/project_browser/-/avatar',
  accentColor: attrs.brand600,
  bgColor: attrs.bgCard,
)
```

### WYSIWYG-Editoren (Quill via HtmlElementView)
- `q.scroll.observer.disconnect()` **vor** dem Setzen von `q.root.innerHTML` nutzen, damit Quills Mutation-Observer `<table>`- und `<img>`-Elemente nicht entfernt.
- Direkt danach mit `q.scroll.observer.observe(...)` wieder verbinden.
- Bilder müssen über den Bild-Proxy laufen.
- Proxy-URLs vor dem Speichern mit `_stripProxyUrls(html)` entfernen.

### Konfetti-Muster
```dart
// In initState:
_confettiController = ConfettiController(duration: const Duration(seconds: 2));

// Bei Erfolg (erst Einstellung prüfen):
if (confettiEnabled) _confettiController.play();
await Future.delayed(const Duration(milliseconds: 900));
// dann navigieren
```

---

## Ports

| Service | Dev-Port | docker-compose-Produktion | Cloudron |
|---|---|---|---|
| Backend (Node.js) | 9901 | 9901 (intern Docker, nie veröffentlicht) | 127.0.0.1:9901 im App-Container, von nginx proxied — nie direkt exponiert |
| Frontend (Flutter) | 5173 | 5173 → nginx:80 (Docker) | vom nginx desselben Containers auf `httpPort` 3000 ausgeliefert, das Cloudrons eigener Reverse-Proxy öffentlich auf 443 bereitstellt |

`./hubctl.sh start` für lokale Entwicklung nutzen — verwaltet beide Ports. Auf Cloudron gibt es
immer nur **einen** Container und **einen** Port (`httpPort` in `CloudronManifest.json`) — siehe
[CLOUDRON_DEPLOYMENT.de.md §1](CLOUDRON_DEPLOYMENT.de.md#1-architektur).

---

## Unsplash-API-Compliance

1. **Hotlinking** — immer `photo.urls.regular` direkt in `<img>` oder CSS-Hintergründen nutzen. Nicht neu hosten.
2. **Download-Tracking** — `POST /api/unsplash/track-download` aufrufen, wenn ein Hintergrund ausgewählt wird.
3. **Attributions-Links** — immer `?utm_source=pb_translation_hub&utm_medium=referral` einbinden.

---

## App-UI-Lokalisierung (i18n)

Die eigene **Oberfläche** des Flutter-Clients (Buttons, Labels, Tooltips, Abschnittsüberschriften
— nicht der übersetzte Projekt-*Inhalt*) wird über Flutter-ARB-Dateien in
`flutter_client/lib/l10n/` lokalisiert, kompiliert mit `flutter gen-l10n` zu `AppLocalizations`.
Das aktive UI-Locale folgt demselben Zielsprachen-Dropdown wie der Content (`languageProvider`),
aufgelöst in `main.dart` über die `_nativeUiLocales`-Map (interner `languages.json`-Code →
Flutter-`Locale`).

**Native UI-Sprachen:** Deutsch (Template), Französisch, Japanisch, Russisch, Spanisch,
Türkisch, brasilianisches Portugiesisch (`pt-br` → `app_pt_BR.arb`) und vereinfachtes Chinesisch
(`zh-hans` → `app_zh_Hans.arb`). Englisch ist der Fallback für jede andere Zielsprache.
`app_pt.arb`/`app_zh.arb` existieren zusätzlich als benötigte Basis-Locale-Fallbacks —
`flutter gen-l10n` verweigert den Build einer `pt_BR`/`zh_Hans`-Datei ohne vorhandene
Basis-Datei `pt`/`zh`, selbst wenn diese nicht direkt genutzt wird.

Bewusst **ausgeschlossen**: `help_screen.dart`, `crwb_study_screen.dart` und
`widgets/consent_youtube_player.dart` — diese implementieren bereits ihr eigenes, reicheres
Mehrsprachensystem (DE/EN/FR/PT/JA/ZH über einen internen `_t(lang, de, en, [ja])`-Helper) für
echten Hilfe-/Lern-*Content*, keine App-Oberfläche.

Um eine native UI für eine neue Sprache zu ergänzen: `lib/l10n/app_<code>.arb` anlegen (Keys von
`app_en.arb` als Basis kopieren, Dateiname nach Flutters Locale-Datei-Konvention benennen), Werte
übersetzen, und einen Eintrag zur `_nativeUiLocales`-Map in `main.dart` hinzufügen.

---

## Guardrails

- Alle DB-Queries müssen den `db`-Connection-Pool nutzen (Prepared Statements via `mysql2`).
- `mysql2`s `execute()` lehnt gebundene `LIMIT`/`OFFSET`-Platzhalter auf MySQL 8 ab
  (`ER_WRONG_ARGUMENTS`), selbst als echte Zahlen — MariaDB ist da nachsichtiger. Als Ganzzahl
  validieren und in den SQL-String einsetzen statt als `?` zu binden, für jedes `LIMIT`/`OFFSET`.
- Der mysql2-Pool wird mit `decimalNumbers: true` erstellt — nicht entfernen. Ohne das kommt
  jedes `SUM(CASE WHEN ... THEN 1 ELSE 0 END)`-artige Aggregat als JS-String statt als Zahl
  zurück, was das strikt typisierte Dart-Model-Parsing auf der Flutter-Seite still bricht
  (genau dieser Bug ließ die Filter-Count-Badges im Dashboard bei 0 hängen).
- Beim Speichern von Daten **sowohl** in die Datenbank **als auch** ins dateisystembasierte
  JSON-Backup schreiben (`server/data/` lokal, `/app/data/` auf Cloudron).
- Das Datenverzeichnis ist die portable Backup-Ebene — synchron halten.
- Die 100-ms-Sync-Verzögerung zwischen Drupal.org-Seiten nicht überspringen.
- Review-bezogene Endpunkte müssen `user_type != 'translator'` prüfen, bevor sie fortfahren; sonst HTTP 403 zurückgeben.
- Massenübersetzung ist bei 150 Modulen pro Request gedeckelt; dieses Limit nicht erhöhen, ohne auch das Dio-`receiveTimeout` zu verlängern.
- DB-Migrationen: `CREATE TABLE IF NOT EXISTS` frei nutzen, aber **niemals** `ADD COLUMN IF NOT
  EXISTS` — das ist MariaDB-only, MySQL 8 (Cloudron) lehnt es rundweg ab. Einfaches `ADD COLUMN`
  reicht; `db_migrate.js` trackt angewendete Versionen bereits in `schema_migrations` und führt
  nie eine Migration doppelt aus, daher war die `IF NOT EXISTS`-Absicherung nie tragend. Niemals
  `DROP` oder `RENAME` ohne explizite Abstimmung.
- In Riverpods `Notifier.build()` kein `ref.watch` auf einen Provider, dessen State sich während
  des App-Starts mehrfach ändert (z. B. `languageProvider`, der von Default → gespeicherte
  Sprache → Post-Fetch übergeht), wenn `build()` auch einen asynchronen, seiteneffektbehafteten
  Fetch startet und einen frischen Default-State zurückgibt — jeder Rebuild setzt den State auf
  den Default zurück und lässt einen neuen Fetch gegen einen bereits laufenden antreten.
  `ref.read` für den initialen Wert nutzen und `ref.listen`, um auf echte spätere Änderungen zu
  reagieren, ohne den State zurückzusetzen (siehe `FilterCountsNotifier` in
  `project_provider.dart` für das gefixte Muster und dessen Kommentar für den dadurch
  verursachten Bug).
