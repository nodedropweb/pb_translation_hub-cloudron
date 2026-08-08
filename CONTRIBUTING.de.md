# Mitwirken bei PB Translation Hub

*[🇬🇧 English version](CONTRIBUTING.md)*

## Erste Schritte

1. Repository klonen.
2. `server/.env.example` nach `server/.env` kopieren und die eigenen Zugangsdaten eintragen.
3. Den Stack starten: `./hubctl.sh start`
4. `http://localhost:5173` öffnen.
5. Neuen Account registrieren oder mit dem Admin-Account einloggen.

Siehe [README.de.md](./README.de.md) für einen vollständigen Feature-Überblick und [FLUTTER_DOCUMENTATION.de.md](./FLUTTER_DOCUMENTATION.de.md) für die Flutter-spezifische Einrichtung.

---

## Entwicklungs-Workflow

### Frontend (Flutter)

Das Frontend ist eine Flutter-Web-Anwendung unter `flutter_client/`.

- **Styles:** `ThemeAttributes` (`attrs.*`) verwenden — niemals Farben hartkodieren.
- **State:** Riverpod nutzen (`ref.watch` / `ref.read`). Kein `setState` für geteilten State.
- **Widgets:** Widgets unter ~500 Zeilen halten. Bei wachsenden Screens Sub-Widgets in ein `widgets/`-Unterverzeichnis auslagern.
- **WYSIWYG-Editoren:** Beim Schreiben in Quill immer das Observer-Disconnect-Muster verwenden. Siehe [FLUTTER_DOCUMENTATION.de.md §5](./FLUTTER_DOCUMENTATION.de.md#5-wysiwyg-editoren-quill).
- **Neue Screens:** Datei unter `lib/screens/<domain>/` anlegen, Route in `lib/router.dart` registrieren, und bei Reviewer-/Admin-Pflicht einen Rollen-Guard ergänzen.
- **Rollen-Guards:** Review-bezogene Routen müssen `user_type != 'translator'` im Router-Redirect prüfen. Siehe die bestehende `/review`-Route in `router.dart` als Referenz.
- **Konfetti:** `ConfettiController.play()` bei Speichern/Freigeben auslösen und Navigation um 900 ms verzögern. Vor dem Abspielen immer prüfen, ob Konfetti in den Einstellungen aktiviert ist.
- **Bilder:** Alle Netzwerk-Bilder müssen über `ApiClient.proxyImageUrl()` laufen. `CachedNetworkImage` verwenden, nicht `Image.network`. Vollbild-Hintergründe in `RepaintBoundary` einpacken.

### Backend (Node.js)

Das Backend ist ein modularer Express-Server. Routen liegen in `server/routes/`. Einstiegspunkt ist `server/index.js`.

- **Datenbank:** Alle Queries müssen den `db`-Pool mit Prepared Statements (`mysql2`) nutzen.
  Achtung: `mysql2`s `execute()` (server-seitige Prepared Statements) lehnt gebundene
  `LIMIT`/`OFFSET`-Platzhalter auf MySQL 8 selbst als echte Zahlen ab (`ER_WRONG_ARGUMENTS`) —
  MariaDB ist da nachsichtiger. Braucht eine Query `LIMIT`/`OFFSET`, den Wert als echte Ganzzahl
  validieren und direkt in den SQL-String einsetzen statt ihn als `?` zu binden.
- **Doppelte Persistenz:** Beim Schreiben von Daten sowohl in die Datenbank (MariaDB oder
  MySQL 8, siehe [CLOUDRON_DEPLOYMENT.de.md](CLOUDRON_DEPLOYMENT.de.md)) *als auch* in die
  `server/data/`- (`/app/data/` auf Cloudron) JSON-Backups schreiben.
- **Antwortgeschwindigkeit:** `res.json()` direkt nach dem DB-Write senden. Dateisystem-Backup-Writes (`fs.writeJson`) asynchron im Hintergrund ausführen.
- **Rollen-Durchsetzung:** Review-Endpunkte müssen den `user_type` des Users prüfen. HTTP 403 für `translator`-User zurückgeben.
- **Filterung:** `getFilteredIndex` für Projektlisten-Queries nutzen — diese Logik nicht duplizieren.
- **AI-Prompts:** `[DESCRIPTION]` und ähnliche Platzhalter beim Bearbeiten von Gemini-Prompts intakt lassen.
- **Sync-Rate-Limit:** Die 100-ms-Verzögerung zwischen Drupal.org-Sync-Seiten nicht entfernen.
- **Bulk-Übersetzungslimit:** Das 150-Modul-Limit nicht erhöhen, ohne auch das Dio-`receiveTimeout` auf dem Client zu verlängern.

### DB-Schema-Änderungen

Alle Schema-Änderungen müssen über das Migrations-System in `server/migrations/` laufen. Siehe [DATABASE.de.md](./DATABASE.de.md) für den vollständigen Migrations-Workflow.

- Dateien immer `NNN_beschreibung.sql` mit führenden Nullen benennen.
- `CREATE TABLE IF NOT EXISTS` frei verwenden (von MariaDB und MySQL unterstützt). **Kein
  `ADD COLUMN IF NOT EXISTS` verwenden** — das ist eine MariaDB-only-Erweiterung; MySQL 8 (auf
  Cloudron im Einsatz, siehe [CLOUDRON_DEPLOYMENT.de.md](CLOUDRON_DEPLOYMENT.de.md)) lehnt das
  rundweg ab. Einfaches `ADD COLUMN` reicht: `db_migrate.js` trackt angewendete Migrationen
  bereits in `schema_migrations` und führt keine doppelt aus, und der catch-Block behandelt einen
  "Duplicate column"-Fehler bereits als nicht-fatal, falls eine Migration doch mal doppelt läuft.
- Niemals `DROP` oder `RENAME` ohne explizite Abstimmung.
- Migration lokal testen, bevor sie in Produktion geht — idealerweise gegen sowohl eine MariaDB-
  als auch eine MySQL-8-Instanz, wenn die Änderung über ein einfaches `ADD COLUMN`/`CREATE
  TABLE` hinausgeht (siehe die Kompatibilitätshinweise in
  [CLOUDRON_DEPLOYMENT.de.md, §4](CLOUDRON_DEPLOYMENT.de.md#4-mariadb--mysql-8-kompatibilitätshinweise)
  für zwei so gefundene echte Inkompatibilitäten — Collations und generierte-Spalten-Dumps).

---

## Testing

- Die Flutter-UI sowohl bei schmalem Viewport (Tablet ~768 px) als auch breitem Desktop-Viewport testen.
- Prüfen, dass HTML-Tags in Beschreibungen die KI-Übersetzung unbeschädigt überstehen.
- Bei Backend-Änderungen sowohl den DB-Pfad als auch den JSON-Datei-Fallback-Pfad testen.
- Den Registrierungs-Flow mit beiden Rollenauswahlen (`translator` und `reviewer`) testen.
- Verifizieren, dass ein `translator`-User nicht auf die Review-Warteschlange zugreifen kann (Router-Redirect + HTTP 403 auf der API).
- Vor dem Commit von Flutter-Änderungen `flutter analyze` ausführen:
  ```bash
  wsl bash -i -c "cd /var/www/pb_translation_hub-cloudron/flutter_client && flutter analyze"
  ```

---

## Commit-Richtlinien

- Commit-Präfixe: `fix:` für Bugfixes, `feat:` für neue Features, `docs:` für Dokumentation, `refactor:` für Refactoring ohne Verhaltensänderung.
- Commits auf ein einzelnes Anliegen fokussiert halten.
- `server/.env`, `server/data/` oder Flutter-Build-Artefakte nicht committen.

---

## Unsplash-API-Compliance

Jedes Feature, das Unsplash-Fotos anzeigt oder auswählt, muss:

1. Hotlinking-URLs (`photo.urls.regular`) nutzen — Bilder nicht proxen oder neu hosten.
2. Download-Tracking über `POST /api/unsplash/track-download` auslösen.
3. UTM-Attribution auf allen Links einbinden: `?utm_source=pb_translation_hub&utm_medium=referral`.
