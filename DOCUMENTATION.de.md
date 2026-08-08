# Project Browser Translation Hub — Dokumentation

*[🇬🇧 English version](DOCUMENTATION.md)*

*Siehe auch: [DATABASE.de.md](./DATABASE.de.md) für technische Schema-Details.*

## Überblick: Was ist das?

Der **PB Translation Hub** ist eine zentrale Server-Anwendung, die das Problem nicht-lokalisierter Modul-Metadaten im Drupal Project Browser löst.

Traditionell holt der Project Browser Daten direkt von Drupal.org über die JSON:API. Diese Daten sind ausschließlich englisch. Dieser Hub fungiert als Übersetzungs-Backend:

1. Er **synchronisiert** Metadaten für alle ~40.000 Drupal-Module lokal.
2. Er bietet einen erstklassigen, KI-gestützten **Editor** zum Übersetzen dieser Metadaten.
3. Er liefert die übersetzten Daten als **Shadow-API** aus. Das Drupal-Modul (namens **Project Browser Localizer**) fungiert als Proxy, holt Live-Daten von Drupal.org und legt die auf diesem zentralen Server gehosteten Übersetzungen darüber.

## Warum? "Sprache ist Vertrauen"

Basierend auf der einflussreichen CSA-Research-Studie "Can't Read, Won't Buy" ist Sprache ein entscheidender Faktor bei Adoptionsentscheidungen:

- **Präferenz:** 72,4 % der Nutzer beschäftigen sich eher mit Produkten in ihrer Muttersprache.
- **Notwendigkeit:** 52,4 % kaufen nur auf Websites in ihrer eigenen Sprache.
- **Vertrauen & Qualität:** 67 % halten lokalisierte Informationen für essenziell.
- **Wert vor Preis:** 56,2 % gewichten Sprache stärker als einen niedrigeren Preis.

Durch die Übersetzung der Project-Browser-Metadaten baust du Vertrauen auf und entfernst die "Nur-Englisch"-Barriere für globale Site-Builder.

---

## Technische Architektur

### Das Proxy- & "Shadow-API"-Konzept

Der Hub bildet die Drupal.org-JSON:API-Struktur nach. Wenn das **Project Browser Localizer**-Modul (installiert auf einer Client-Drupal-Site) Daten anfragt:

1. Das Modul fängt die Standard-Drupal.org-Anfrage ab.
2. Es holt die entsprechenden übersetzten Felder von diesem Hub.
3. Es überlagert die originalen englischen Felder mit den übersetzten.
4. Der Site-Builder erlebt einen nahtlosen, lokalisierten Project Browser.

### Privacy-First-Design

Der Hub enthält ein integriertes Hilfe-Center mit einem 100 % DSGVO-konformen YouTube-Widget. Es nutzt eine "Consent Wall" mit einem verschwommenen, themenbewussten Platzhalter — es wird garantiert keine Verbindung zu Google-Servern aufgebaut, bevor der Nutzer explizit auf "Zustimmen & Video laden" klickt.

### Stale-Erkennung

Jede Übersetzung speichert einen `source_hash` (MD5) des englischen Originalinhalts. Erkennt der Hub während eines Syncs, dass sich der Inhalt auf Drupal.org geändert hat, stimmt der Hash nicht mehr überein, und die Übersetzung wird als **"Veraltet"** markiert. Das alarmiert Übersetzer, dass die Übersetzung aktualisiert werden muss.

### KI-Übersetzungs-Backends

Der Hub unterstützt drei maschinelle Übersetzungs-Backends. Jeder Nutzer kann eigene API-Keys in seinem Profil konfigurieren — Keys werden **niemals** zwischen Nutzern geteilt. Jeder API-Aufruf nutzt ausschließlich den Key des authentifizierten Nutzers (`req.user.id` aus dem verifizierten JWT).

#### Google Gemini (Bulk-Auto-Run)

Die Gemini-Engine kann Hunderte Module in Minuten übersetzen:

1. **Auswahl:** Zielt auf die nächsten X fehlenden Module basierend auf deiner aktuellen Such- und Filtereinstellung. Gedeckelt bei 150 pro Lauf.
2. **Kostenschätzung:** Vor dem Start liefert der Hub eine Token- und Kostenschätzung basierend auf der Google-Gemini-Preisgestaltung.
3. **Entwurf:** KI-Übersetzungen werden als **Vorschläge** (`suggestion_type = 'ai'`) gespeichert, überschreiben manuelle Arbeit nicht ohne Review.
4. **Sicherheit:** Ein **Stop**-Button unterbricht den Prozess und sichert den bisherigen Fortschritt.

#### DeepL

Modulweise Übersetzung über die [DeepL-API](https://developers.deepl.com/docs).

- **Endpunkt:** `POST /ai/deepl-translate` (authentifiziert)
- **Key-Auflösung:** Keys, die auf `:fx` enden, nutzen automatisch `api-free.deepl.com`; alle anderen `api.deepl.com`.
- **HTML-Erhalt:** `tag_handling: 'html'` wird übergeben, damit alles Markup (`<p>`, `<a>`, `<ul>` etc.) erhalten bleibt.
- **Gespeichert als:** `suggestion_type = 'deepl'` in `translation_suggestions`.
- **Key-Isolation:** Die eigene `deepl_api_key`-Spalte des Nutzers wird zur Anfragezeit aus der DB gelesen. Es gibt keinen globalen/Admin-Key-Fallback.

##### DeepL-Nutzungs-Widget

Ein kompaktes Nutzungs-Widget erscheint in der Navigations-Sidebar für jeden Nutzer mit konfiguriertem DeepL-Key. Es ruft `GET /ai/deepl-usage` auf → proxied zu `GET /v2/usage` auf der DeepL-API.

| Angezeigtes Feld | Quelle |
|---|---|
| Zeichenzahl / Limit | `character_count` / `character_limit` |
| Fortschrittsbalken (farbkodiert) | grün < 70 %, orange < 90 %, rot ≥ 90 % |
| Aufschlüsselung pro Produkt | `products[]` (nur Pro-Accounts) |
| "Unbegrenzt"-Label | wenn `character_limit ≥ 1.000.000.000.000` (DeepL-Sentinel-Wert) |

Antworten im Free-Plan enthalten nur `character_count` und `character_limit`; Pro-Antworten enthalten zusätzlich `api_key_character_count`, `api_key_character_limit`, Abrechnungszeitraum-Timestamps und Pro-Produkt-Daten.

#### Manueller Clipboard-Prompt

Nutzer ohne API-Key können einen vorgefertigten Prompt (englische Quelle + Übersetzungsanweisungen) in die Zwischenablage kopieren und in ein beliebiges KI-Tool einfügen (ChatGPT, Gemini Web, Deepseek etc.). Der Prompt ist verfügbar in:

- Der **Review-Screen**-Kopfzeile (Button "PROMPT")
- Dem **Editor**-Off-Canvas-Quellpanel (Clipboard-Icon)
- Der **Editor**-Übersetzungspanel-Kopfzeile (Clipboard-Icon)

Der Prompt weist die KI an, **ausschließlich rohes HTML** zurückzugeben — keine Markdown-Code-Fences, keine Labels. Zwei HTML-Blöcke (Kurzbeschreibung und Body) werden durch eine nackte `---`-Zeile getrennt.

### Menschliche Review- & Vorschlags-Engine

Um Übersetzungsqualität sicherzustellen, implementiert der Hub einen strikten "Human-in-the-Loop"-Workflow:

- **Mehrere Vorschläge:** Jedes Modul kann mehrere Übersetzungsversionen haben (z. B. von verschiedenen KI-Modellen oder Nutzern). Diese werden in einer eigenen Vorschlags-Datenbank gespeichert.
- **Split-Diff-Ansicht:** Der **Review-Screen** zeigt den Originaltext oben (rot) und den korrigierten Text unten (grün) in einem Side-by-Side-Split-Layout. Kein überlappender Text, keine Verwirrung.
- **Produktions-Freigabe:** Eine Übersetzung wird erst als `is_reviewed: true` markiert und an Endnutzer ausgeliefert (via die JSON-Dateien), nachdem ein Mensch explizit bestätigt hat.
- **Zugriff auf die Review-Warteschlange:** Nur Nutzer mit Rolle `reviewer` oder `admin` können auf die Review-Warteschlange zugreifen. Nutzer mit Rolle `translator` werden sowohl vom Router-Guard (Client) als auch von einem serverseitigen Middleware-Guard umgeleitet.
- **Optimistische Navigation:** Wenn ein Reviewer eine Übersetzung freigibt, navigiert die App sofort zum nächsten Modul, während der Speicher-POST im Hintergrund läuft. Das hält den Workflow schnell.

### Rollenbasierte Zugriffskontrolle

Der Hub unterstützt drei Nutzertypen, die bestimmen, welche Teile der Anwendung zugänglich sind:

| Rolle | `user_type` | Review-Warteschlange | Admin-Panel |
|---|---|---|---|
| `admin` | — | Ja | Ja |
| `user` | `reviewer` | Ja | Nein |
| `user` | `translator` | Nein | Nein |

Der Zugriff wird auf zwei Ebenen durchgesetzt:
- **Router-Guard** im Flutter-Client leitet `translator`-Nutzer von `/review*`-Routen weg.
- **Server-Middleware** liefert HTTP 403 für jeden `translator`-Nutzer, der review-bezogene Endpunkte aufruft.

### Nutzerverwaltung

Administratoren verwalten den Nutzer-Lifecycle über das Admin-Panel:

- **Wartende Nutzer:** Neue Registrierungen starten inaktiv (`is_active = 0`). Ein Admin sieht die Liste wartender Nutzer, weist eine Rolle zu (`translator` oder `reviewer`) und aktiviert den Account.
- **Aktive Nutzer:** Admins können aktive Nutzer deaktivieren (sperren) oder dauerhaft löschen.
- **Reviewer-Badge:** Hat ein Nutzer bei der Registrierung die Rolle `reviewer` angefragt, wird ein Badge neben seinem Namen in der Warteliste angezeigt.

### Themes

Der Flutter-Client bringt sechs visuelle Themes mit. Das aktive Theme wird in `SharedPreferences` unter dem Key `pb-theme` persistiert.

| ID | Label | Stil | Akzent |
|---|---|---|---|
| `pearl` | Hell / Light | Solider Lavendel-Hintergrund, reinweiße flache Karten, minimaler Blur | Sanftes Lila `#8B7FD4` |
| `dark` | Dunkel / Dark | Halbtransparentes dunkles Glas | Violett `#8B5CF6` |
| `glassy` | Glasig / Glassy | Tiefblaues Glassmorphism | Cyan `#009CDE` |
| `nature` | Natur / Nature | Waldschwarz mit starkem Blur | Smaragd `#10B981` |
| `liquid` | Flüssig / Liquid | Dunkles Navy mit Neon-Akzenten | Himmelblau `#0EA5E9` |
| `stage` | Bühne / Stage | Dunkles Smaragd-Türkis, Konzert-Ästhetik | Warmes Orange `#F58620` |

Hintergründe für alle außer `pearl` (das ein 100 % deckendes Overlay nutzt) werden über die Unsplash-API via `GET /unsplash/random-bg` mit themenspezifischen Keywords geholt und in `SharedPreferences` gecacht. Das `pearl`-Theme deckt den Hintergrund per Design vollständig ab, für einen sauberen, flachen Look.

### Selbstregistrierungs-Flow

Neue Nutzer registrieren sich über einen 4-Schritte-Assistenten:

1. **Account** — Username, E-Mail, Passwort
2. **Rolle** — `translator` oder `reviewer` wählen (gespeichert als `requested_role`)
3. **Sprachen** — Zielsprachen für die Übersetzung auswählen
4. **API-Keys** — optional einen persönlichen Google-Gemini- und/oder DeepL-Key angeben

Die Registrierung kann global über `site_settings.registration_enabled = '0'` deaktiviert werden.

### DB-Migrationssystem

Schema-Änderungen werden als nummerierte SQL-Dateien in `server/migrations/` verwaltet. Der Migrations-Runner `server/db_migrate.js` wird automatisch beim Server-Start aufgerufen. Er:

1. Legt die `schema_migrations`-Tabelle an, falls sie nicht existiert.
2. Liest alle `.sql`-Dateien in `server/migrations/`, numerisch sortiert.
3. Überspringt bereits in `schema_migrations` verzeichnete Migrationen.
4. Führt ausstehende Migrationen innerhalb einer Transaktion aus.
5. Beendet sich mit Code 1 bei Fehlschlag — kein stilles Überspringen.

### Tastaturkürzel (Produktivität)

Der Editor ist für professionelle Übersetzer mit Power-User-Shortcuts optimiert:

- `Strg+Alt+S` — **Speichern & Weiter** (aktuelle Übersetzung speichern und zum nächsten unübersetzten Projekt springen)
- `Alt+P` — **Vorschau umschalten** (zwischen Editor und Live-Vorschau wechseln)
- `Strg+Alt+D` — **Projekt überspringen** (zum nächsten Projekt springen, ohne zu speichern)

---

## Workflow-Modi

Der Hub unterstützt spezialisierte Workflow-Modi, um deine Arbeit zu fokussieren:

1. **Alle Projekte:** Zeigt alles im System.
2. **Review-Warteschlange:** Zeigt übersetzte Projekte, die auf menschliche Freigabe warten (nur reviewer/admin).
3. **Drupal-12-Fokus (Priorität):** Filtert die kuratierte Prioritätsliste auf Module herunter, die noch nicht als Drupal-12-kompatibel markiert sind (`semver_max < 12000000`) — also Module, die mit Blick auf das nahende EOL von Drupal 10 am dringendsten Aufmerksamkeit brauchen.
4. **Veraltet:** Zeigt Übersetzungen, bei denen sich die englische Quelle seit der Übersetzung geändert hat.

---

## Wartung & Betrieb

### Starten und Stoppen

Das mitgelieferte `hubctl.sh`-Skript für einfache Verwaltung nutzen:

- `./hubctl.sh start` — startet Backend und Frontend im Hintergrund
- `./hubctl.sh stop` — stoppt alle Prozesse und räumt PID-Dateien auf
- `./hubctl.sh restart` — führt Stop gefolgt von Start aus
- `./hubctl.sh status` — zeigt, ob die Prozesse laufen, und ihre PIDs
- `./hubctl.sh logs` — verfolgt beide Service-Logs live

### Build für Produktion

Siehe [DEPLOYMENT.de.md](./DEPLOYMENT.de.md) für den Docker-Compose-Produktions-Deployment-Guide (Rolling Restart, Datenbank-Backup-Workflow), oder [CLOUDRON_DEPLOYMENT.de.md](./CLOUDRON_DEPLOYMENT.de.md) beim Deployment dieser Cloudron-paketierten Variante.

### Datenpersistenz & Backup

- **Primärspeicher:** Datenbank `pb_translation_hub` (MariaDB bei Docker-Compose, MySQL 8 auf Cloudron).
- **Dateibasiertes Backup:** Das System spiegelt automatisch alle Metadaten und Übersetzungen nach `server/data/` (`/app/data/` auf Cloudron).
  - `metadata/` — originale Drupal.org-Daten-Snapshots
  - `translations/` — Übersetzungs-Backups pro Sprache

Dieser Ordner liefert eine portable Version deiner Übersetzungen, die mit `node migrate_to_mysql.js` in eine neue Datenbank re-importiert werden kann.

---

## Deployment-Guide

Siehe [DEPLOYMENT.de.md](./DEPLOYMENT.de.md) für die vollständige Schritt-für-Schritt-Docker-Compose-Produktions-Deployment-Prozedur (`deploy.sh`-Rolling-Restart-Skript, das `--db-backup`-Flag, Nginx-Konfiguration, Systemd-Service-Einrichtung), oder [CLOUDRON_DEPLOYMENT.de.md](./CLOUDRON_DEPLOYMENT.de.md) für das Cloudron-Äquivalent.

Um eine Drupal-Site nach dem Deployment mit dem Hub zu verbinden (URL auf deine tatsächliche Instanz anpassen):

```bash
drush config:set pb_localizer.settings hub_url "https://<deine-hub-domain>" --yes
drush config:set pb_localizer.settings hub_port "443" --yes
```
