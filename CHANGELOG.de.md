# Änderungsprotokoll

*[🇬🇧 English version](CHANGELOG.md)*

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Daten im Format `YYYY-MM-DD`.

---

## [0.4.16] — 2026-08-23

### Behoben

- **Der Import eines echten, von `mariadb-dump` erzeugten Recovery-Files scheiterte mit `Variable 'autocommit' can't be set to the value of NULL`.** `mariadb-dump` umschließt jede Tabelle, die es dumpt, mit Session-Housekeeping — `SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;` gepaart mit einem späteren `SET AUTOCOMMIT=@OLD_AUTOCOMMIT;`, dazu `LOCK`/`UNLOCK TABLES`, Zeichensatz-/Kollations-Sicherung-Wiederherstellung usw. Live bestätigt: Das Batching aus `importSqlDump()` (0.4.15) trennte bei einer großen Tabelle die Capture- und Restore-Zeile über getrennte Roundtrips, und MySQL 8 lehnte die Wiederherstellung ab. Statt jede mögliche Boilerplate-Variante, die ein Dump-Tool erzeugen könnte, einzeln aufzuzählen — fragil, leicht wird eine übersehen —, whitelistet der Import jetzt genau die eine Statement-Form, die tatsächlich gebraucht wird (`INSERT INTO ...`), und überspringt alles andere, statt wie bisher nur Leerzeilen und `--`-Kommentare zu überspringen.

## [0.4.15] — 2026-08-23

### Behoben

- **Der Import eines echten Datensatzes (41k+ Projekte) lief selbst nach allen vorherigen Fixes ins Timeout.** Live bestätigt gegen einen korrekten, vollständigen Recovery-Dump aus der echten Produktions-DB: `504`, nginx-Log `upstream timed out (110: Connection timed out) while reading response header from upstream`. `importSqlDump()` führte ein Statement pro Roundtrip aus — zehntausende davon beim echten Datensatz — deutlich über nginx' Standard-`proxy_read_timeout` von 60 s, der für `/api/` nie explizit gesetzt war. Umgeschrieben, um Statements in Batches (300 pro Roundtrip) über eine dedizierte `multipleStatements`-Verbindung statt des gemeinsamen Pools auszuführen (isoliert von jeder anderen Query in der App gehalten — hier sicher, weil die Statements aus dem eigenen, vertrauenswürdigen Export-Format stammen, nie aus Nutzereingaben), was die Roundtrip-Anzahl um ~300x reduziert. Zusätzlich `proxy_read_timeout`/`proxy_send_timeout` explizit auf 600 s für `/api/` angehoben als zweite Verteidigungslinie.

## [0.4.14] — 2026-08-23

### Behoben

- **Ein echtes Content-Backup wurde rundweg mit nacktem `413 Request Entity Too Large` abgelehnt.** `nginx/app.conf`s `client_max_body_size` stand auf `50M`, unter multers eigenem `100M`-`fileSize`-Limit in `server/index.js` — nginx sitzt vor multer, lehnte also einen echten ~60-MB-Export (DB-Dump + Kategorie-Übersetzungen, aus einem Live-Datensatz von 41k+ Projekten) ab, bevor multers eigene, spezifischere Fehlerbehandlung überhaupt zum Zug kam. Auf `100M` angehoben, passend zu multer.

## [0.4.13] — 2026-08-23

### Behoben

- **Der Import fügte still gar nichts ein, meldete aber 200 OK.** Live bestätigt: Der Upload eines echten Exports ergab "keine Projekte gefunden", obwohl der Restore Erfolg meldete. `projects.semver_min`/`semver_max` sind `GENERATED ALWAYS ... STORED`-Spalten (siehe `migrations/008_semver_columns.sql`), berechnet aus `data` — MySQL lehnt jedes `INSERT` ab, das überhaupt einen Wert dafür angibt, mit `The value specified for generated column 'semver_min' in table 'projects' is not allowed`. Der Export nahm über `SELECT *` deren aktuelle Werte wie jede andere Spalte mit und fügte sie wieder ein, was die allererste `projects`-Zeile bei jedem Import zum Absturz brachte — und da `importSqlDump()` beim ersten fehlschlagenden Statement abbricht, bedeutete das null importierte Zeilen in jeder Tabelle, still, obwohl die Anfrage selbst weiterhin 200 zurückgab (der Fehler stand im `sqlImport.success: false` der Antwort, nur leicht zu übersehen). Der Export fragt jetzt pro Tabelle `information_schema.COLUMNS` nach tatsächlich generierten Spalten ab und schließt sie vom `INSERT` aus, statt einer hartkodierten Ausschlussliste — jede künftige generierte Spalte wird automatisch berücksichtigt.
- **Ein fehlgeschlagener SQL-Import zeigte sich als grüne Erfolgs-Toast.** Die Fehlermeldung stand in Klammern angehängt an eine ansonsten grüne "Backup wiederhergestellt"-Snackbar — technisch vorhanden, leicht zu überlesen. Zeigt jetzt rot an, sobald `sqlImport.success` `false` ist.

## [0.4.12] — 2026-08-23

### Behoben

- **Der Sanitize-Schritt nach dem Entpacken in `/upload-backup` konnte das komplette Datenverzeichnis dauerhaft lahmlegen und hätte nebenbei alle Nutzer-Avatare gelöscht.** Live bestätigt, direkt nach einem erfolgreichen großen Import: Jeder weitere Schreibzugriff unter `/app/data` — einschließlich der temporären Datei eines brandneuen Uploads — schlug mit `EACCES: permission denied` fehl. Ursache: Der Sanitize-Schritt führte `find "${destRoot}" -not -name "*.json" -delete && chmod -R 644 "${destRoot}" && find "${destRoot}" -type d -exec chmod 755 {} +` aus, wobei `destRoot` auf `DATA_DIR` **selbst** gesetzt war, nicht auf den entpackten Archivinhalt. Zwei getrennte Bugs in dieser einen Zeile: (1) Sie löscht jede Nicht-JSON-Datei irgendwo unter `DATA_DIR` — das hätte Nutzer-Avatare in `uploads/avatars/` mit erfasst, die nichts mit dem hochgeladenen Archiv zu tun haben; (2) `chmod -R 644` nimmt `DATA_DIR` sein eigenes Execute-Bit, und der nachfolgende `chmod 755`, der es wiederherstellen sollte, kann dann selbst nicht mehr ins Verzeichnis navigieren, um zu laufen — sperrt jeden Dateizugriff darunter dauerhaft aus, bis von Hand behoben (`chmod 755 /app/data`). Der komplette Shell-basierte Sanitize-Schritt wurde durch reine `fs`-Aufrufe ersetzt, strikt beschränkt auf die Pfade, die das Archiv tatsächlich entpackt hat (bereits für die Zip-Slip-Prüfung erfasst) — keine Shell, keine Verzeichnisse werden je angefasst, nichts außerhalb des eigenen Inhalts dieser Anfrage ist gefährdet.

## [0.4.11] — 2026-08-23

### Hinzugefügt

- **Der Admin-Bootstrap garantiert jetzt einen funktionierenden Login, nicht nur einen optionalen.** Ein reiner `cloudron install` ohne zusätzliche Konfiguration ließ die Instanz bisher ganz ohne Admin-Account und ohne Weg hinein zurück — dieselbe Art "still kaputter Quickstart"-Bug, den die frühere `JWT_SECRET`-Auto-Generierung schon behoben hatte, nur diesmal für den Admin-Account. `ADMIN_USERNAME`/`ADMIN_PASSWORD` erlauben weiterhin eigene Werte, greifen aber jetzt standardmäßig auf Benutzername `admin` mit zufällig generiertem Passwort zurück, falls nicht gesetzt — einmalig im Start-Log ausgegeben und unter `/app/data/.admin_credentials` gespeichert, genau wie beim JWT-Secret. `POSTINSTALL.md` (im Cloudron-Dashboard direkt nach der Installation angezeigt) und beide Deployment-Guides entsprechend aktualisiert.

### Behoben

- **Der SQL-Import-Pfad (sowohl der First-Boot-Seed als auch der in 0.4.5 hinzugefügte admin-ausgelöste Import) crashte die komplette App mit OOM auf dem echten Datensatz.** Live bestätigt beim Import eines echten Exports (zehntausende `projects`/`translations`-Zeilen) in eine frische Instanz: `FATAL ERROR: Reached heap limit ... JavaScript heap out of memory`, `Runtime_StringSplit` ganz oben im Stack. `importSqlDump()` las den komplett entpackten SQL-Text (zig MB — allein `projects.data` hält einen vollständigen JSON-Blob pro Zeile) als einen JS-String ein und führte mehrere Whole-String-`.split()`/`.join()`/`.filter()`/`.map()`-Durchläufe darüber aus, um Statement-Grenzen zu finden — die Zwischenkopien und riesigen Substring-Arrays sprengten den Heap. Dieselbe Art von Bug wie beim Export-OOM aus 0.4.1, jetzt im passenden Import-Pfad. Umgeschrieben, um die Gzip-Datei zeilenweise über `readline` zu streamen statt den kompletten entpackten Text jemals als einen String zu materialisieren, jedes Statement wird direkt beim Lesen ausgeführt — der Spitzenspeicherverbrauch bleibt jetzt unabhängig von der Dateigröße annähernd konstant.

## [0.4.10] — 2026-08-23

### Behoben

- **Der Admin-Bootstrap aus 0.4.9 schlug bei jedem Versuch stillschweigend fehl.** Beim Deployen von 0.4.9 zur tatsächlichen Verifikation entdeckt: `[Startup] Admin account bootstrap failed (non-fatal): Data truncated for column 'user_type' at row 1`. `user_type` ist `ENUM('translator', 'reviewer')` — unterscheidet diese beiden Rollen für einen Nicht-Admin-Account und akzeptiert `'admin'` überhaupt nicht, der Insert setzte ihn aber trotzdem darauf, was MySQL rundweg ablehnte. Im Ergebnis harmlos (die Funktion loggt und macht weiter, statt den Start zu crashen), aber der Admin-Account wurde nie angelegt. `user_type` ist für einen echten Admin irrelevant — `role = 'admin'` allein erfüllt bereits jede `isAdmin`/`isReviewerOrAdmin`-Prüfung in der App —, weshalb der Insert die Spalte jetzt einfach auf ihrem Schema-Default (`'translator'`) belässt.

## [0.4.9] — 2026-08-23

### Hinzugefügt

- **Eine frische Installation hatte keinen Weg, den ersten Admin-Account anzulegen.** Beim tatsächlichen Durchtesten des Fresh-Install-Ablaufs bis zum Ende entdeckt: `POST /auth/register` akzeptiert nur `user_type` `translator`/`reviewer`, und jeder neue Account startet mit `is_active=0`, wartet auf Freigabe durch einen Admin — den es auf einer brandneuen Instanz nicht gibt. Ein echter Bootstrap-Deadlock. `ADMIN_USERNAME`/`ADMIN_PASSWORD` (plus optional `ADMIN_EMAIL`) legen diesen ersten Account jetzt beim Start an, falls gesetzt und noch kein Admin existiert — sofort aktiv, keine Freigabe nötig. Greift nur genau einmal: Ein Update oder Neustart mit weiterhin gesetzten Env-Vars tut nichts mehr, sobald ein Admin-Account existiert — kann also niemandem das Passwort zurücksetzen. `CLOUDRON_DEPLOYMENT.md`/`.de.md` und `server/.env.example` mit den neuen Variablen aktualisiert.

## [0.4.8] — 2026-08-23

### Behoben

- **Die JWT_SECRET-Auto-Generierung aus 0.4.7 crashte beim ersten Start immer noch — an anderer Stelle.** Beim Deployen von 0.4.7 zur tatsächlichen Verifikation entdeckt: Der Generator lief und loggte erfolgreich, dann crashte der Prozess ein paar Zeilen später trotzdem mit `Error: ENCRYPTION_KEY or JWT_SECRET must be set to encrypt stored API keys.` aus `lib/secretCrypto.js`, transitiv über `routes/auth.js` requiret. Dieses Modul liest `process.env.JWT_SECRET` direkt beim Laden — 0.4.7 stellte den aufgelösten Wert nur als lokale Konstante in `index.js` bereit, weshalb alles, was den Env-Var direkt liest (aktuell die einzige weitere Stelle, aber das Muster ist generisch), ihn weiterhin als nicht gesetzt sah. `resolveJwtSecret()` schreibt den Wert jetzt zurück in `process.env.JWT_SECRET`, bevor er zurückgegeben wird — konsistent überall im Prozess, nicht nur über `ctx`.

## [0.4.7] — 2026-08-23

### Behoben

- **Eine frische Installation über den dokumentierten Quickstart (`cloudron install --image ...`) legte stillschweigend die komplette API lahm.** Beim tatsächlichen End-zu-End-Test des Fresh-Install-Pfads entdeckt (Uninstall + Neuinstallation von d.drupal-tv.de aus dem 0.4.6-Image): Das Node-Backend crashte beim Start hart mit `FATAL: JWT_SECRET environment variable is not set` — aber Nginx, ein separater Prozess im selben Container, beantwortete den Cloudron-Health-Check unter `/` trotzdem weiterhin mit 200, da er das statische Frontend eigenständig ausliefert. Cloudron meldete "App installiert", die Seite lud im Browser problemlos, und jeder einzelne `/api/*`-Aufruf war tot — ohne offensichtlichen Grund. Der eigentlich nötige Schritt (`cloudron env set ... JWT_SECRET=...`, dokumentiert als Schritt 3 des Quickstarts, leicht zu übersehen) war unsichtbar, bis man in den Logs nachsah. `JWT_SECRET` braucht anders als die übrigen App-Secrets (Unsplash-Keys, Hilfe-Video-Links) keine externe Abstimmung — es sind nur Zufallsbytes, die niemand sonst kennen muss —, weshalb der harte Fehlschlag reine Reibung war, keine echte Sicherheitsanforderung. Die App generiert jetzt beim ersten Start automatisch einen Wert und speichert ihn im Datenverzeichnis, falls keiner konfiguriert ist; ein explizit gesetzter Env-Var gewinnt weiterhin immer. `CLOUDRON_DEPLOYMENT.md`/`.de.md` entsprechend aktualisiert — der manuelle Schritt ist jetzt optional, nützlich nur für einen portablen, über mehrere Instanzen geteilten Wert.

## [0.4.6] — 2026-08-23

### Behoben

- **Das SQL-Import-Feature aus 0.4.5 aktualisierte die DB, ließ Drupal aber dauerhaft veraltete Übersetzungen ausliefern.** Beim Testen durch Nachfragen entdeckt: "reicht das wirklich, dass was in der Datenbank steht — kommt das dann auch so in Drupal an?" Die Antwort war nein. `GET /:langcode/:filename` in `routes/translations.js` — die öffentliche Route, die pb_localizers `ProxyManager` auf der Drupal-Seite tatsächlich abruft — liefert Dateien aus `TRANSLATIONS_DIR`, nicht die DB. `ensureTranslationFilesFromDb()` regeneriert diese Dateien nur, wenn das Verzeichnis komplett leer ist (der Frisch-Install-Fall), weshalb ein admin-ausgelöster Import über `/upload-backup` zwar `translations` korrekt aktualisierte, aber nie die Dateien anfasste, die Drupal liest — die blieben veraltet, bis zufällig ein anderes Ereignis eine Regenerierung auslöste. Die Datei-Schreib-Schleife wurde in `regenerateTranslationFilesFromDb()` extrahiert und wird jetzt nach einem erfolgreichen SQL-Import bedingungslos aufgerufen, wodurch jede Übersetzungsdatei aus der jetzt aktualisierten Tabelle neu geschrieben wird — einfacher und robuster, als herauszufinden, welche konkreten Zeilen der importierte Dump betraf. Das `sqlImport`-Feld der Upload-Backup-Antwort meldet jetzt zusätzlich `filesRegenerated`.

### Geändert

- **Export- und Import-Button zeigen jetzt, was tatsächlich passiert, statt eines nackten Spinners.** Die Export-Karte zeigt ihre reale (einzelne) Phase — Dump erstellen und Kategorien bündeln, dann Download starten — neben einem kleinen Spinner. Die Import-Karte hatte bereits echten byteweisen Upload-Fortschritt; sobald der 100 % erreicht, wechselt sie jetzt zu einer ehrlichen, unbestimmten Anzeige mit der Beschriftung "verarbeite auf dem Server (entpacken, importieren, synchronisieren)" für die Phase, für die es kein Fortschrittssignal gibt — statt den Balken bei 100 % stehen zu lassen, während die Anfrage noch mitten in der Verarbeitung ist.

## [0.4.5] — 2026-08-23

### Hinzugefügt

- **`export-seed` transportiert jetzt auch Kategorie-Namensübersetzungen, nicht nur DB-Inhalte.** Beim Testen des Export-/Import-Ablaufs mit dem realen Ziel von ~116 Sprachen entdeckt: Kategorie-Übersetzungen (`_categories.json`, das UUID→Name-Mapping für Modul-Kategorien) leben **ausschließlich** auf der Platte — dafür gibt es überhaupt keine DB-Tabelle (siehe `routes/categories.js`) —, weshalb ein reiner DB-Export sie bisher stillschweigend fallen ließ. `GET /admin/export-seed` erzeugt jetzt ein `.zip`, das `db_seed.sql.gz` (unverändert, gleiche Tabellen) plus `translations/<langcode>/_categories.json` für jede Sprache mit vorhandener Datei bündelt.
- **`POST /upload-backup` ("Backup einspielen" in den Einstellungen) ist jetzt zusätzlich zum bestehenden reinen Datei-Restore das Import-Gegenstück zu `export-seed`.** Enthält das hochgeladene Zip ein `db_seed.sql.gz` (also ein Export-Seed-Archiv), werden dessen SQL-Statements über dasselbe `importSqlDump()` wie beim First-Boot-Seed in die DB importiert, bevor der bestehende Sanitize-Schritt sie entfernt. Ein reines Übersetzungs-Backup ohne `db_seed.sql.gz` wird exakt wie bisher wiederhergestellt — an diesem Pfad ändert sich nichts. Die Antwort enthält jetzt ein `sqlImport`-Feld, das das Ergebnis des SQL-Schritts getrennt vom Datei-Restore meldet.
- **Der exportierte SQL-Dump ist jetzt upsert-sicher.** Jede Tabelle in `SEED_TABLES` außer `glossary_terms` hat einen echten fachlichen Primary-/Unique-Key (gegen `server/migrations/*.sql` verifiziert), weshalb generierte `INSERT`s jetzt `ON DUPLICATE KEY UPDATE` für jede Spalte tragen. Dieselbe Datei, die eine leere Datenbank beim ersten Start seedet, kann jetzt auch in eine bereits befüllte Live-Instanz re-importiert werden, ohne beim ersten Duplicate-Key abzustürzen — genau der Zweck dieses Features, da ein frisches Docker-Image für jede Übersetzungsänderung bei dieser Größenordnung nicht praktikabel ist. `glossary_terms` hat nur eine Auto-Increment-`id` ohne weiteren Unique-Constraint und bleibt daher bei Plain-`INSERT` — wiederholte Importe duplizieren Glossareinträge statt sie zu aktualisieren; das zu beheben würde eine neue `UNIQUE(lang_code, source_word)`-Migration erfordern, die nicht sicher blind gegen unbekannte vorhandene Live-Daten anwendbar ist — bewusst als bekannte, dokumentierte Einschränkung belassen, statt eine beim Deploy fehlschlagende Migration zu riskieren.

### Entfernt

- **Der Button "D11 Liste einlesen" in den Einstellungen.** Drupal-11-Kompatibilitäts-Tracking ist nicht mehr der aktive Fokus (D12/13-Unterstützung ist geplant, aber noch nicht gebaut), der Button war veraltet. Sein Handler (`_handlePrioritySync`, `POST /sync/priority`) wurde aus der UI entfernt; die Tabelle `priority_projects` und ihre Nutzung im Priority-Filter/-Zähler des Dashboards bleiben unangetastet.

## [0.4.4] — 2026-08-23

### Behoben

- **Der Export-Button traf jetzt dieselbe Art von Connection-Timeout-Fehler, die das 0.4.2-Redesign eigentlich vermeiden sollte.** Live bestätigt: `DioException [connection timeout]` bei `GET /admin/export-seed` nach 30 s. Das Zwei-Phasen-Redesign aus 0.4.2 verlagerte den Dump-Aufbau serverseitig vor den Versand jeder Antwort (damit der eigentliche Download-Schritt sofort geht) — das bedeutet aber, dass dieser Request jetzt warten muss, bis der **komplette** Dump fertig gebaut ist, bevor überhaupt eine Antwort kommt, anders als bei der alten Direkt-Stream-Version, deren erste Bytes fast sofort ankamen. Der `connectTimeout` (30 s, auf normale Aufrufe zugeschnitten) des regulären API-Clients deckt auf Flutter Web genau dieses "Warten bis Antwortbeginn"-Fenster ab und löst jetzt bei einem großen Dump genauso aus wie vorher beim Download selbst. Neu: `ApiClient.longRunningDio` — eine zweite Dio-Instanz mit derselben Basis-URL und denselben Auth-/Logging-Interceptors wie die Standardinstanz, aber mit 5 Minuten `connectTimeout`/`receiveTimeout` — und der Export-Seed-Request nutzt jetzt diese, statt das globale Timeout anzuheben (was jeden gewöhnlichen Aufruf 5 Minuten warten lassen würde, bevor ein wirklich ausgefallener Server gemeldet wird).

## [0.4.3] — 2026-08-23

### Behoben

- **`/projects/filter-counts` löste nach dem 0.4.2-Fix gelegentlich immer noch das Timeout des Clients aus.** Live bestätigt: Auf dem echten Datenbestand wurden die 9 unabhängigen Aggregat-Queries des Endpoints nacheinander abgewartet und brauchten in Summe ~16 s — knapp über dem 15-s-`connectTimeout` des Flutter-Clients. Auf Flutter Web deckt Dios "connection timeout" die gesamte Wartezeit bis zum Beginn einer Antwort ab (es gibt keine Low-Level-Socket-API, um nur den TCP-Handshake zu messen), sodass eine langsame serverseitige Query es direkt auslöst — die Exception erschien als `DioException [connection timeout]` in den Client-Logs, obwohl der Retry-/Logging-Fix aus 0.4.2 korrekt funktionierte. Der Endpoint führt die 9 Queries jetzt über `Promise.all` parallel aus (der Pool erlaubt bis zu 100 Verbindungen) statt sequenziell, wodurch sich die Gesamtzeit auf etwa die langsamste Einzel-Query (~10 s für den Stale-Zähler) statt deren Summe reduziert. Der globale `connectTimeout` des Clients wurde außerdem von 15 s auf 30 s als Puffer angehoben — Dios `Options` pro Request hat kein Feld dafür, nur `BaseOptions`, weshalb das vorherige `receiveTimeout`-Override pro Aufruf einen Connect-Timeout-Fehler gar nicht beheben konnte.

## [0.4.2] — 2026-08-23

### Behoben

- **Dashboard-Zähler blieben stillschweigend bei Null hängen.** `GET /api/projects/filter-counts` führt pro Anfrage mehrere Aggregat-Queries über die kompletten Tabellen aus (darunter ein MD5-über-JSON-Scan für den Stale-Zähler) und konnte unter Last gelegentlich das Timeout des Clients überschreiten — etwa direkt nach einem großen Export, der aus demselben DB-Connection-Pool dieselben Tabellen streamt. Die Fehlerbehandlung im Flutter-Provider war ein leeres `// Ignore or log error` — ein einziger fehlgeschlagener Request ließ das Dashboard auf den `FilterCounts()`-Standardwerten (alles Null) hängen, bis zum kompletten Neuladen der Seite, ohne dass irgendwo etwas geloggt wurde. `fetchCounts()` loggt den echten Fehler jetzt über den vorhandenen `LogService` und wiederholt den Versuch bis zu zweimal mit längerem Empfangs-Timeout, statt stillschweigend aufzugeben.
- **Export-Button konnte serverseitig fertig werden und im Browser trotzdem fehlschlagen (oder still nichts tun).** Der bisherige Ablauf streamte den kompletten gzip-Dump als Antwort dieser Anfrage, ließ den Flutter-Client ihn komplett als Bytes puffern und übergab diese dann an den "Speichern unter"-Dialog von `file_picker` — dessen zugrundeliegende Browser-API (File System Access) eine noch frische User-Geste voraussetzt, die ein mehrsekündiger Transfer über zig MB aufbrauchen kann; das Speichern fiel dann lautlos aus, ohne eine Exception, die der `catch`-Block der App je zu sehen bekommen hätte. `GET /api/admin/export-seed` baut den Dump jetzt nur noch in eine temporäre Datei unter `DATA_DIR/exports` und liefert einen kurzlebigen (5 Min.), einmal verwendbaren Download-Token zurück; ein neuer Endpoint `GET /api/admin/export-seed/download/:token` (bewusst außerhalb der normalen Bearer-Auth-Kette, da eine reine Browser-Navigation diesen Header nicht mitschicken kann — abgesichert stattdessen über den 256-Bit-Zufallstoken selbst) ist das Ziel, zu dem der Client direkt navigiert, was den nativen Browser-Download auslöst, ohne je Bytes in der App zu puffern. Die erzeugte Datei wird gelöscht, sobald dieser Download abgeschlossen ist oder fehlschlägt; ein Export, dessen Token nie abgeholt wurde, wird beim nächsten Export-Aufruf aufgeräumt. Fehlschläge loggen jetzt außerdem den echten Fehler über `LogService` und zeigen ihn in der Fehler-Snackbar an statt einer generischen Meldung.

## [0.4.1] — 2026-08-23

### Behoben

- **`GET /api/admin/export-seed` hat die gesamte App per OOM abgeschossen.** `projects` allein enthält den kompletten Drupal.org-Katalog (zehntausende Zeilen, je mit einem JSON-Blob) — die 0.4.0-Version hat pro Zeile einen `INSERT`-String gebaut, alle in einem Array gesammelt, zu einem Riesenstring zusammengefügt und dann in einem Rutsch gzippt — hält dabei mehrere volle Kopien derselben Daten gleichzeitig im Speicher. Auf der Live-Testinstanz bestätigt: Node hat das Heap-Limit des Containers gesprengt und ist abgestürzt, dabei auch andere gerade laufende Anfragen mit kurzem 502 mitgerissen (ein einziger Container, ein einziger Prozess für alle Routen). Streamt jetzt Zeilen direkt aus MySQL in einen Gzip-Stream, der direkt in die Response gepiped wird, mit Backpressure über `write()`/`drain` — der Speicherverbrauch bleibt damit unabhängig von der Tabellengröße ungefähr konstant.

## [0.4.0] — 2026-08-23

### Hinzugefügt

- **Optionaler First-Boot-Daten-Seed.** `SEED_ON_FIRST_BOOT=true` an der App gesetzt, wird ein gebackener Content-Snapshot (`server/seed/db_seed.sql.gz`, erzeugt von `pb_translation_hub/export_for_cloudron.sh --seed`) automatisch importiert, sobald die Schema-Migrationen gelaufen sind — vorausgesetzt `projects` ist noch leer. Eine Frischinstallation kann so gleich mit dem vollständigen Übersetzungs-Korpus starten, kein manueller `cloudron push`/DB-Import nötig. Es werden nur Content-Tabellen geseedet (`projects`, `translations`, `glossary_terms`, `priority_projects`, `ignored_projects`, `sync_events`, `site_settings`) — `users` und `schema_migrations` sind ausgenommen, sodass eine geseedete Instanz weiterhin einen frischen Admin-Account per normaler Registrierung bekommt und die Migrations-Buchführung unangetastet bleibt. Übersetzungs-JSON-Dateien sind ebenfalls nicht Teil des Seeds — die bestehende Startup-Regeneration (`ensureTranslationFilesFromDb()`) baut sie automatisch aus der jetzt befüllten `translations`-Tabelle neu auf. Rührt eine bereits befüllte Datenbank nie an, die Env-Var kann also dauerhaft über Neustarts/Updates hinweg gesetzt bleiben.
- **Admin-UI-Datenexport ("Datenstand exportieren" in den Einstellungen).** `GET /api/admin/export-seed` baut einen Content-only, gzip-komprimierten SQL-Dump derselben Tabellen wie der First-Boot-Seed oben, direkt über die bereits offene `mysql2`-Verbindung (kein `mariadb-dump`/`mysqldump`-Binary nötig, funktioniert also unabhängig davon, was ein Deployment-Ziel mitliefert) — ein Admin kann ihn direkt aus dem Browser herunterladen und als `server/seed/db_seed.sql.gz` für den nächsten Image-Build ablegen, ohne SSH- oder Shell-Zugriff auf irgendeinen Server.

## [2.4.0] — 2026-08-22

### Security

Eine vollständige Security-Coverage-Review deckte mehrere Befunde auf, die hier alle behoben wurden:

- **Kritisch: Credential-Leak in der Git-Historie.** `server/check_pass.js` (ein bcrypt-Hash plus ein Klartext-Passwort-Kandidat) war in diesem öffentlichen Repo getrackt. Datei entfernt, zur `.gitignore` hinzugefügt und aus der Git-Historie entfernt (Force-Push-Rewrite — wer das Repo bereits geklont hat, muss neu klonen). **Das betroffene Passwort muss weiterhin manuell rotiert werden**, falls das nicht schon geschehen ist.
- **Kritisch: Zip-Slip beim Backup-Upload.** `POST /api/upload-backup` erfordert jetzt `isAdmin` (vorher jeder eingeloggte Nutzer) und entpackt `.zip`-Archive über `adm-zip` mit einer Pfad-Containment-Prüfung statt eines ausgeführten `unzip`. Zusätzlich Upload-Größenlimit (100 MB) und Dateityp-Filter im `multer`-Handler.
- **Kritisch: Offener Proxy über `/api/image-proxy`.** Der Server löst das Ziel jetzt per DNS auf und blockiert private/lokale/Link-Local-Adressen (inkl. Cloud-Metadaten-Bereich), bevor der Request ausgeführt wird.
- **Hoch: SSRF in `/api/unsplash/track-download`.** `download_location` muss jetzt exakt auf `api.unsplash.com` zeigen.
- **Hoch: Path Traversal in den Datei-Ausliefer-Routen.** Neue `safeTranslationPath()`-Absicherung in `routes/translations.js` validiert `langcode`/`filename` gegen eine Whitelist und stellt sicher, dass der aufgelöste Pfad innerhalb von `TRANSLATIONS_DIR` bleibt — angewendet auf `GET /translations/:langcode/:machine_name`, `GET /debug/:langcode/:filename` und `GET /:langcode/:filename`.
- **Hoch: fehlende Authentifizierung bei `POST /api/categories/import-local`.** Erfordert jetzt `isAdmin`; `langcode` wird zusätzlich gegen eine Whitelist validiert, bevor es in einem Dateipfad verwendet wird.
- **Hoch: hardcodierter JWT-Secret-Fallback.** `index.js` bricht beim Start jetzt hart ab, wenn `JWT_SECRET` nicht gesetzt ist, statt auf einen im Quellcode sichtbaren Default zurückzufallen.
- **Hoch: kein Rate-Limiting bei Login/Registrierung.** `express-rate-limit` (15 Versuche/15 Min pro IP) für `POST /api/auth/login` und `/api/auth/register` ergänzt.
- **Mittel: fehlende Authentifizierung bei `POST /api/sync/quick` und `/api/sync/project/:machine_name`.** Beide erfordern jetzt `authenticateToken`, konsistent mit den übrigen Sync-Routen.
- **Mittel: fehlende Authentifizierung bei `POST /api/import-local`.** Erfordert jetzt `authenticateToken` + `isAdmin`.
- **Mittel: fehlende Rollenprüfung bei `POST /api/categories/translate`.** Erfordert jetzt `isReviewerOrAdmin`, passend zu `glossary.js`.
- **Mittel: unparametrisiertes Batch-Insert bei `POST /api/sync/priority`.** Manuelles String-Escaping durch `db.query('... VALUES ?', [batch])` mit Array-Platzhalter ersetzt.
- **Mittel: hardcodierter DB-Passwort-Fallback (`'drupal'`)** aus `index.js` und 8 Wartungs-/Migrationsskripten entfernt; alle brechen jetzt hart ab, wenn das Datenbank-Passwort (`CLOUDRON_MYSQL_PASSWORD` bzw. `DB_PASSWORD`) nicht gesetzt ist.
- **Mittel: Gemini/DeepL-API-Keys im Klartext gespeichert.** Neues `lib/secretCrypto.js` (AES-256-GCM, Schlüssel aus `ENCRYPTION_KEY` oder von `JWT_SECRET` abgeleitet) verschlüsselt `users.google_ai_key`/`deepl_api_key` beim Speichern; Lesevorgänge (Login, `/auth/me`, jeder AI-Aufruf in `routes/ai.js`) entschlüsseln transparent. Bestehende Klartext-Keys funktionieren unverändert weiter und werden beim nächsten Profil-Speichern automatisch verschlüsselt.
- **Niedrig: CORS ohne Origin-Einschränkung.** Optionale Allowlist über `CORS_ALLOWED_ORIGINS` (kommagetrennt); ohne gesetzte Env-Var bleibt das Verhalten wie zuvor offen, sodass dies kein Deployment brechen kann, das die Variable noch nicht gesetzt hat.
- **Niedrig: keine Security-Header.** `helmet` als globale Middleware ergänzt (CSP deaktiviert, da die Flutter-Web-SPA vom selben Origin hinter Cloudrons Reverse-Proxy ausgeliefert wird).
- **Niedrig: Timing-Angriff beim Debug-Key-Vergleich.** `requireDebugKey` (in `routes/sync.js` und `routes/translations.js`) nutzt jetzt `crypto.timingSafeEqual()` statt `!==`.
- **Abhängigkeiten:** `npm audit fix` behob 5 gemeldete Schwachstellen in `axios`, `body-parser`, `form-data`, `multer` und `qs` (0 verbleibend).

### Added

#### App-UI-Lokalisierung (i18n)
- Die eigene Oberfläche des Flutter-Clients (Buttons, Labels, Tooltips, Abschnittsüberschriften — nicht der übersetzte Projekt-*Inhalt*, der bereits mehrsprachig war) wird jetzt über Flutter-ARB-Dateien (`flutter_client/lib/l10n/`) lokalisiert, kompiliert mit `flutter gen-l10n` zu `AppLocalizations`.
- Das aktive UI-Locale folgt demselben Zielsprachen-Dropdown, das bereits für Content genutzt wird, aufgelöst in `main.dart` über eine `_nativeUiLocales`-Map.
- Native UI-Übersetzungen für **25 Sprachen**, priorisiert nach Drupal.orgs Rangliste der aktivsten Übersetzungsteams: Deutsch (Template), Französisch, Japanisch, Russisch, Spanisch, Türkisch, brasilianisches Portugiesisch, europäisches Portugiesisch, vereinfachtes Chinesisch, Ukrainisch, Niederländisch, Norwegisch Bokmål, Ungarisch, Katalanisch, Italienisch, Schwedisch, Dänisch, Polnisch, Rumänisch, Litauisch, Estnisch, Aserbaidschanisch, Indonesisch, Arabisch und Koreanisch — jede andere Zielsprache fällt auf Englisch zurück.
- `help_screen.dart`, `crwb_study_screen.dart` und `widgets/consent_youtube_player.dart` sind bewusst ausgenommen — sie implementieren bereits ihr eigenes reicheres Mehrsprachen-Content-System, unabhängig von der App-Oberfläche.

#### Analyse-Dashboard — Kompatibilität, Übersetzungsbedarf & Wochen-Verläufe
- **`server/migrations/009_sync_events.sql`** — neue Tabelle `sync_events` (Verlauf von `new_module` / `description_changed` / `stale` mit `event_date`).
- **`server/index.js`** — Helper `recordSyncEvents()` protokolliert vor jedem `projects`-Upsert neue Module, geänderte Beschreibungen und dadurch veraltete Übersetzungen (pro Sprache); in `syncProjects()` und allen Sync-Pfaden in **`server/routes/sync.js`** eingebunden.
- **`server/routes/dashboard.js`** — neuer Endpoint `GET /dashboard/weekly?type=new_description|stale&weeks=&langcode=` (Wochenbuckets + Modullisten). Kompatibilität/Bedarf nutzt weiterhin `/projects/filter-counts`.
- **`server/scripts/backfill_sync_events.js`** — einmaliger, idempotenter Backfill des Verlaufs aus `projects.changed`.
- **`flutter_client/lib/screens/analytics/analytics_screen.dart`** + **`providers/analytics_provider.dart`** — neuer „Statistik"-Screen (Route `/analytics`, Nav-Eintrag): Übersetzungsbedarf-Karten, Kompatibilitäts-Balken pro Drupal 9–12, zwei ausklappbare Wochenlisten (neue Beschreibungen / veraltet markiert).

#### Vollständiges Backup & Restore (DB + Übersetzungs-/Kategorie-Dateien)
- **`backup.sh`** / **`restore.sh`** — sichern bzw. restaurieren DB-Dump **und** den `data/translations/`-Baum (inkl. `_categories.json`, das nur als Datei existiert) in/aus einem Archiv `backups/pb_hub_backup_<stamp>.tar.gz`. Modi `--local` und Live-Server per SSH.

#### Stale-Massen-Übersetzung — alle veralteten Module per Knopfdruck neu übersetzen
- **`server/routes/ai.js`** — neuer Endpoint `GET /ai/stale-machine-names?langcode=X`: liefert alle Machine-Names, deren `source_hash` nicht mehr mit dem aktuellen englischen Text übereinstimmt, direkt aus der DB (kein Pagination-Limit).
- **`flutter_client/lib/screens/dashboard/dashboard_screen.dart`** — `_showStaleBulkTranslateDialog()`: spezieller Dialog für den Stale-Filter, der alle veralteten Module vorab abruft, Gesamtanzahl und Kostenschätzung anzeigt und ohne Count-Dropdown direkt startet.
- **`_executeBulkTranslationWithNames()`** — neue Methode, die eine explizite Machine-Name-Liste in Batches à 4 an `/ai/translate-bulk` schickt; orangefarbener Progress-Dialog; aktualisiert nach Abschluss automatisch den Stale-Filter.

#### Stale-Erkennung — veraltete Übersetzungen anzeigen & beheben
- **`server/routes/projects.js`** — `/projects/:machine_name` berechnet jetzt einen MD5-Hash über `title + body.summary + body.value` und vergleicht ihn mit `translations.source_hash`. Weicht der Hash ab, liefert die API `status: 'stale'`.
- **`flutter_client/lib/screens/editor/editor_screen.dart`** — neues Feld `_isStale`; wird beim Laden gesetzt, wenn der API-Status `'stale'` ist. Bei veralteter Übersetzung öffnet sich die englische Quell-Seitenleiste automatisch.
- **`flutter_client/lib/screens/editor/_editor_build_methods.dart`** — orangefarbener „Veraltet — Details"-Button in der Editor-Toolbar; öffnet `_showStaleDialog()`. Neue Methode `_useEnglishSource()` ersetzt Zusammenfassung und Body mit dem aktuellen englischen Original und setzt `_isStale` zurück.

#### Diff-Ansicht — Übersetzung vs. englische Quelle
- **`flutter_client/lib/utils/diff_utils.dart`** — Wort-Diff-Algorithmus (`DiffSpan`, `DiffOp`: equal / insert / delete). Liefert eine Liste von `DiffSpan`-Objekten für zwei Texte.
- **`flutter_client/lib/widgets/diff_view.dart`** — `DiffView`-Widget (inline farbkodierter Diff) und `showDiffSheet()` (Bottom-Sheet mit zweispaltigem Vergleich). Grün = Einfügung, Rot = Löschung.
- **`flutter_client/lib/screens/review/review_screen.dart`** — neuer „DIFF"-Button im Review-Screen-Header: öffnet `showDiffSheet()` mit Übersetzung (links) vs. englischer Quelle (rechts).

#### Debug-Sync-Endpunkte (geschützt via `PB_DEBUG_KEY`)
- **`server/routes/sync.js`** — drei neue Routen, nur erreichbar mit korrektem `X-PB-Debug-Key`-Header:
  - `GET /debug/sync/inspect/:machine_name` — vergleicht DB-Stand mit Live-Daten von Drupal.org (Title, Changed, Body-Länge).
  - `POST /debug/sync/force/:machine_name` — erzwingt Einzelmodul-Sync von Drupal.org in DB + Metadaten-Verzeichnis.
  - `POST /debug/sync/quick` — führt Quick-Sync für ein konfigurierbares Zeitfenster (`days`, Standard: 7) durch und gibt ein detailliertes Log zurück.

#### Automatischer Quick-Sync alle 7,5 Tage
- **`server/index.js`** — `scheduleQuickSync()` startet einen `setInterval` (7,5 Tage) nach dem Server-Start. Überspringt automatisch, wenn bereits ein Sync läuft oder kein `lastFullSync`-Timestamp vorhanden ist.

#### App-Icons (Android / iOS / Windows)
- **`appicons/`** — vollständige Icon-Sets für alle Plattformen hinzugefügt (Android Launcher-Icons, iOS-Größen 16–1024 px, Windows Tiles, Splash Screens, Store Logo).

#### Deutsches Intro-Audio
- **`flutter_client/web/audio/crwb_de.mp3`** — deutschsprachige Audioversion des Project-Browser-Localizer-Intros (ElevenLabs-Generierung) aktualisiert.

### Fixed

#### CKEditor — `<img>`-Tags erhalten
- **`flutter_client/web/index.html`** — `img` zur `htmlSupport.allow`-Konfiguration hinzugefügt, damit CKEditor 5 `<img>`-Tags beim Initialisieren oder Speichern nicht mehr entfernt.

#### Docker — PM2-Cluster deaktiviert
- **`server/Dockerfile`** — PM2 läuft jetzt mit `-i 1` (Single-Instance) statt `-i max`. Cluster-Modus würde konkurrierende Sync-Prozesse erzeugen, da der Sync-Status im RAM gehalten wird.

---

## [2.3.0] — 2026-06-09

### Added

#### Glossary — Wortformen (Plurale & flektierte Formen)
- **`server/migrations/007_glossary_word_forms.sql`** — neue Spalte `word_forms TEXT NULL` in `glossary_terms`. Speichert kommagetrennte flektierte Formen (Plural, Genitiv, Dativ usw.), z.B. `"Inhalte,Inhalts,Inhalten"`.
- **`server/routes/glossary.js`** — GET normalisiert `word_forms` von Komma-String zu Array; POST/PUT nehmen ein `word_forms`-Array entgegen, speichern als String, geben in der Antwort wieder Array zurück.
- **`flutter_client/web/index.html`** — `_ckApplyGlossaryMarkers` baut pro Term eine RegExp-Alternation aus `source_word` + allen `word_forms`: `\b(Inhalt|Inhalte|Inhalts|Inhalten)\b`. Die exakte gematchte Form wird als `encodeURIComponent`-kodiertes Segment in den Marker-Namen geschrieben (`glossaryTerm:<id>:<uid>:<encodedForm>`).
- **`GlossaryHighlightPlugin`** — dekodiert die gematchte Form aus dem Marker-Namen und schreibt sie als `data-matched`-Attribut ans Highlight-`<span>`. Zusätzlich zu den bestehenden `data-preferred` und `data-explanation`.
- **Glossar-Tooltip** — zeigt jetzt die konkrete im Text gefundene Wortform an:
  - *Flektierte Form* (z.B. „Inhalte"): kleiner weißer Label „Inhalte" + Pfeil „↓ bevorzugte Übersetzung" + lila/fett „Inhalt".
  - *Grundform* (matched == preferred): nur die Grundform lila/fett, kein Pfeil.
- **`flutter_client/lib/screens/glossary/glossary_screen.dart`** — Chip-UI für Wortformen im Bearbeitungsdialog: Textfeld + „+"-Button zum Hinzufügen, „✕"-Chips zum Entfernen. In der Tabellenzeile werden Wortformen als kleinere Amber-Mini-Chips neben dem Grundform-Badge angezeigt.

#### Einstellung: Automatische Absatzformatierung (Auto-P)
- **`flutter_client/lib/providers/theme_provider.dart`** — neues Feld `autoAutop: bool` in `ThemeState`, persistiert als `pb-autoAutop` in `SharedPreferences`. Standard: `false`. Neue Methode `setAutoAutop(bool)`.
- **`flutter_client/lib/screens/settings/settings_screen.dart`** — Switch-Toggle im Bereich „Workflow & Spaß", direkt unter dem Large-UI-Toggle. Zweisprachig: DE „Automatische Absatzformatierung (¶ Auto-P)" / EN „Automatic Paragraph Formatting (¶ Auto-P)".
- **`flutter_client/lib/screens/review/review_screen.dart`** — am Ende von `_fetchData()`, nachdem alle Felder mit Inhalt befüllt wurden, wird `_autop()` automatisch auf Summary und Body angewendet, wenn `themeState.autoAutop == true`. Identisches Verhalten zum manuellen ¶-Button, aber ohne Snackbar-Meldung.

### Fixed

#### CKEditor — Init-Race-Condition
- **`flutter_client/web/index.html`** (`_ckBridge.init`) — `document.getElementById('cke_editor_<id>')` wird jetzt bis zu 10× mit 200 ms Abstand wiederholt, falls das DOM-Element beim ersten Aufruf noch nicht im Dokument ist. Zusätzlicher Retry (bis zu 3×, 500 ms) bei `ClassicEditor.create()`-Rejection.
- **`flutter_client/lib/widgets/ckeditor_field_web_impl.dart`** — 3-Sekunden-Safety-Net: falls `onReady` nach dem `bridge.init`-Aufruf nie feuert, wird der Editor zerstört und neu initialisiert. `didUpdateWidget` aktualisiert `_lastContent` nun immer, auch wenn `_editorReady` noch `false` ist.

#### Glossar-Tooltip — Stabilität (mouseover/mouseout)
- **`flutter_client/web/index.html`** — `mouseover`- und `mouseout`-Handler nutzen jetzt `relatedTarget`, um zu prüfen ob die Maus den Highlight-Span wirklich verlässt. Interne Bewegungen innerhalb des Spans lösen kein Hide mehr aus. `clearTimeout` wird im `mouseover`-Handler nur noch aufgerufen wenn die Maus tatsächlich über einem Highlight-Element ist.

---

## [2.2.0] — 2026-06-02

### Added

#### DeepL-Integration
- **`POST /ai/deepl-translate`** — übersetzt Kurzbeschreibung und Body eines einzelnen Moduls über die DeepL-API mit dem persönlichen `deepl_api_key` des authentifizierten Nutzers. Wählt automatisch `api-free.deepl.com` für Keys mit `:fx`-Endung und `api.deepl.com` für Pro-Keys. Sendet `tag_handling: 'html'`, um Markup zu erhalten. Speichert das Ergebnis sowohl als `translations`-Datensatz als auch als `translation_suggestions`-Zeile (Typ `'deepl'`).
- **`GET /ai/deepl-usage`** — proxied einen Aufruf von `GET /v2/usage` auf der DeepL-API mit dem Key des Nutzers. Liefert `character_count`, `character_limit` und (für Pro-Accounts) Aufschlüsselung pro Produkt sowie Abrechnungszeitraum-Timestamps. Wird vom Sidebar-Nutzungs-Widget verwendet.
- **DeepL-Sidebar-Widget** (`_DeeplUsageWidget`) — erscheint in der Navigations-Sidebar, sobald der eingeloggte Nutzer einen `deepl_api_key` im Profil gespeichert hat. Zeigt einen farbkodierten Fortschrittsbalken (grün → orange → rot bei 70 %/90 %) plus formatierte Zeichenzahlen. Hat einen manuellen Aktualisieren-Button. Bei unbegrenzten Keys wird „unbegrenzt / unlimited" statt eines Balkens angezeigt.
- **`server/migrations/006_suggestion_type_deepl.sql`** — erweitert das `suggestion_type`-ENUM auf `translation_suggestions` von `('ai','manual')` auf `('ai','manual','deepl')`. Diese Migration verursachte den ursprünglichen 500er-Fehler ("Data truncated") und wird jetzt automatisch beim Server-Start angewendet.
- **DeepL-Button im Editor** — reiht sich neben den bestehenden Gemini- und DeepL-Buttons in der Übersetzungspanel-Kopfzeile ein. Deaktiviert, während eine andere KI-Übersetzung läuft.
- **`User-Agent: PBTranslationHub/1.0`**-Header zu allen DeepL-API-Requests hinzugefügt (`/v2/translate` und `/v2/usage`), wie von den DeepL-API-Richtlinien gefordert.

#### Review-Screen — Tablet-Layout
- **`_buildReviewHeaderTablet`** — neue responsive Header-Variante für Bildschirmbreiten zwischen 600 dp und 1099 dp (deckt das BEYNIVAN-M986-EEA-Tablet bei ~1000 dp Querformat ab). Identisches einzeiliges Layout wie der Desktop-Header, aber Tastaturkürzel-Hinweise (`Strg+→`, `Strg+Enter`) werden aus den Button-Labels weggelassen, um Overflow zu vermeiden.

#### Editor — Off-Canvas-Quellpanel
- **Clipboard/Prompt-Button** zur „Englische Quelle"-Off-Canvas-Drawer-Kopfzeile hinzugefügt, identisch zum bereits vorhandenen PROMPT-Button im Review-Screen-Header. Kopiert `buildTranslationPrompt(…)` mit dem aktuellen englischen Quelltext.

#### Übersetzungs-Prompt-Verbesserungen
- Labels `"Summary:"` und `"Main Description:"` aus dem kopierten Clipboard-Text entfernt; die zwei Blöcke werden jetzt durch eine Leerzeile und einen nackten `---`-Separator getrennt. Die KI-Anweisung erklärt weiterhin, dass der erste Block die Kurzbeschreibung und der zweite der Body ist.
- Explizite Regel hinzugefügt: **Ausgabe nicht in Markdown-Code-Fences einpacken** (keine Triple-Backtick-HTML-Blöcke). Behebt, dass Gemini/Deepseek gefencte Code-Blöcke statt rohem HTML zurückgeben.

#### Ignorierte Module — Massen-Wiedereinreihung
- **`DELETE /projects/ignore-all`** — neuer Server-Endpunkt (Auth erforderlich). Löscht alle Zeilen aus `ignored_projects` und liefert `{success, count}`.
- **Dashboard-Button „Alle wieder einreihen"** — erscheint nur, wenn der „Ignoriert"-Filter aktiv ist. Öffnet einen sprachbewussten Bestätigungsdialog (DE/EN). Bei Bestätigung wird der Massen-Wiedereinreihungs-Endpunkt aufgerufen und der Filter auf „Alle" umgeschaltet.
- **Editor-Button „Einreihen"** — im Editor-Header angezeigt, sobald `meta.is_ignored === true` für das aktuelle Modul. Ruft `DELETE /projects/:name/ignore` für das einzelne Modul auf.

#### Login-Screen — Bilder-Slideshow
- **Manueller Bild-Slider** mit `‹`/`›`-Navigationspfeilen, animierten Fortschritts-Punkten und Crossfade-Übergängen. Jeder `›`-Klick zeigt entweder den nächsten gecachten Slide oder holt ein neues Bild von `/unsplash/random-bg`.
- **Auto-Play-Umschalter**-Button über den Punkten; startet/stoppt einen 6-Sekunden-Auto-Advance-Timer (nutzt denselben Lazy-Fetch-Mechanismus, um unnötige API-Aufrufe zu vermeiden).
- **Verpflichtende Unsplash-Attribution** unten links für jedes API-bezogene Bild angezeigt: Fotografenname und "Unsplash" verlinken beide mit `?utm_source=pb_translation_hub&utm_medium=referral`, um die Unsplash-API-Bedingungen einzuhalten und Production-Tier-Zugriff (50.000 Requests/Stunde) zu erhalten.

#### Themes
- **Pearl-Theme** (`'pearl'`) — cleanes flaches Design mit solidem Lavendel-Hintergrund (`#ECE8F9`, 100 % deckendes Overlay), reinweißen Karten, minimalem Blur (`glassBlur: 1.0`) und sanftem Lila-Akzent (`#8B7FD4`). Ersetzt das bisherige "Hell/Light"-Theme.
- **Stage-Theme** (`'stage'`) — Konzert-/Event-Ästhetik: dunkler Smaragd-Türkis-Hintergrund (`#0C2222`), warmer Orange-Akzent (`#F58620`), 80 % Türkis-Overlay. Hintergrund-Keyword: `concert,neon,stage,festival,dark`.
- **"Hell/Light"-Button** in Sidebar und Einstellungen mappt jetzt auf `pearl` (die interne Theme-ID). Nutzer, die `light` in `SharedPreferences` gespeichert hatten, werden beim nächsten Laden automatisch auf `pearl` migriert.

#### Review-List-Screen — Toolbar
- **"Aktualisieren / Refresh"** und **"Freigaben zurücksetzen / Reset published"** von schwebenden Icon-Buttons im Seiten-Header in die Such-Toolbar verschoben. Beide sind jetzt `OutlinedButton.icon` mit sichtbaren Labels und Lade-Spinnern.

### Fixed
- **DeepL-500er-Fehler** — das Einfügen eines Vorschlags mit `suggestion_type = 'deepl'` hat die ENUM-Spalte abgeschnitten. Behoben durch Migration 006.
- **Light-Theme-Lesbarkeit** — `GlassContainer`-Bereiche im Study- und Help-Screen nutzten `Colors.white.withValues(alpha: 0.04)`-Hintergründe (unsichtbar im hellen Modus). Alle hartkodierten fast-transparenten weißen Container durch `attrs.bgCard` ersetzt.
- **Sichtbarkeit der Tastatur-Chips** im Help-Screen (Shortcut-Bereich) — `Colors.white.withOpacity(0.1)`-Hintergründe durch `attrs.bgInput` / `attrs.borderMain` ersetzt.

---

## [2.1.0] — 2026-06-02

### Added

#### Glossar-Term-Highlighting (CKEditor-5-Plugin)
- **`server/migrations/005_create_glossary_terms.sql`** — neue Tabelle `glossary_terms` (`id`, `lang_code`, `source_word`, `preferred_word`, `explanation`, `created_by`, Timestamps). Indexiert auf `lang_code` und `source_word`.
- **`server/routes/glossary.js`** — REST-API: `GET /glossary` (filterbar via `?langcode=`), `POST /glossary`, `PUT /glossary/:id`, `DELETE /glossary/:id`. Schreibende Endpunkte erfordern Rolle `reviewer` oder `admin`.
- **`GlossaryHighlightPlugin`** in `web/index.html` — CKEditor-5-Plugin, das `markerToHighlight` nutzt (nur beim Editieren, verunreinigt `getData()` nie). Marker tragen `affectsData: false`, sodass Undo/Redo sie ignoriert.
- **`_ckApplyGlossaryMarkers(editor)`** — wendet `glossaryTerm:<id>:<uid>`-Modell-Marker auf jedes Block-Element an; nutzt `\b`-Wortgrenzen-Regex (case-insensitive). Läuft innerhalb von `model.change()`.
- **`_ckBridge.setGlobalGlossary(termsJson)`** — globaler Glossar-Store. Der Aufruf dieser Methode wendet Marker in allen aktiven CKEditor-Instanzen sofort neu an.
- **Schwebendes Tooltip** (`#_ck_glossary_tip`) — erscheint bei Hover über `.ck-glossary-highlight`-Spans; zeigt bevorzugte Übersetzung und Erklärung. Positioniert, um im Viewport zu bleiben.
- **`flutter_client/lib/utils/ck_glossary.dart`** — geteilte Dart-Utilities:
  - `loadCkEditorGlossary(api, langcode)` — holt `/glossary` und ruft `setGlobalGlossary` auf der Bridge auf. Wird sowohl von `ReviewScreen` als auch `EditorScreen` beim Mount und Sprachwechsel aufgerufen.
  - `setCkEditorTheme(themeId)` — setzt CSS-Custom-Properties auf `#_ck_glossary_tip` und `:root` direkt via `dart:html` (keine JS-Bridge nötig). Deckt alle 5 Themes ab.
- **`flutter_client/lib/screens/glossary/glossary_screen.dart`** — Verwaltungs-UI für Glossar-Terme. Reviewer und Admins können Terme hinzufügen, bearbeiten und löschen. Zeigt die Terme der aktuellen Zielsprache mit Quellwort, bevorzugter Übersetzung und Erklärung. Erreichbar über Sidebar-Navigationseintrag.
- **Glossar-Laden in `EditorScreen`** — `_loadGlossary()` hinzugefügt (war bisher nur in `ReviewScreen`); wird 400 ms nach `initState` und bei Sprachwechsel via `ref.listen` ausgelöst.
- **Glossar-Laden in `ReviewScreen`** — refaktoriert, um das geteilte `loadCkEditorGlossary` aufzurufen; wird ebenfalls bei Sprachwechsel ausgelöst.
- **Marker nach `setData` neu angewendet** — ein 300 ms debouncter Aufruf von `_ckApplyGlossaryMarkers` läuft innerhalb des `change:data`-Listeners, sodass Marker nach jeder Inhaltsänderung aufgefrischt werden.

#### Theme-bewusstes Glossar-Styling
- **CSS-Custom-Properties** `--ck-hl-bg` und `--ck-hl-border` auf `:root` steuern die Highlight-Markierungsfarbe; `--tip-*`-Variablen auf `#_ck_glossary_tip` steuern das schwebende Tooltip. Beide werden von `setCkEditorTheme()` aktualisiert.
- **Farb-Sets pro Theme** in `ck_glossary.dart`: dark (Amber-Highlight, lila Tooltip), light (lila Highlight + Tooltip), glassy (Cyan), nature (Grün), liquid (Himmelblau).
- **`app_layout.dart`** ruft `setCkEditorTheme(themeState.themeId)` bei jedem `build()` auf — Tooltip- und Highlight-Farben aktualisieren sich sofort beim Theme-Wechsel.

#### Entwicklungs-Erfahrung
- **`api_client.dart` WSL-/Nicht-Standard-Port-Erkennung** — `baseUrl` und `serverOrigin` erkennen jetzt jeden Nicht-Standard-Port (nicht 80/443) als Entwicklungsumgebung und lösen zu `host:9901` auf. Zuvor wurden nur `localhost` / `127.0.0.1` erkannt, was beim Zugriff über die WSL-IP zu Login-Fehlern führte.

#### Logging & Diagnose
- **`LogService`** (`lib/services/log_service.dart`) — In-Memory-Ringpuffer für `INFO`-/`WARNING`-/`ERROR`-Einträge mit Timestamps und optionalen Details. Integriert in Dio-Interceptors.
- **Log-Download** (`lib/services/log_downloader_web.dart` / `_stub.dart`) — exportiert den Log-Puffer als JSON-Datei via `dart:html`-Blob-Download im Web.

#### Audio-Player
- **`audio_player_web.dart` / `audio_player_stub.dart`** — bedingter Import, der `dart:html AudioElement` für Web umschließt. Wird vom CRWB-Study-Screen für TTS-Audio-Wiedergabe ohne native Abhängigkeiten verwendet.

#### CKEditor-5-Web-Implementierung
- **`ckeditor_field_web_impl.dart`** — vollständige Web-only-CKEditor-5-Implementierung, aus `ckeditor_field.dart` extrahiert. Registriert via `ui_web.platformViewRegistry`. Behandelt `init`, `setData`, `destroy`, Suppression-CSS und `didUpdateWidget`-Pushes.
- **`ckeditor_field_stub.dart`** — Nicht-Web-Stub, der den bedingten Import auf Desktop erfüllt.

### Fixed
- **Glossar-Marker nicht in `EditorScreen` gezeigt** — `loadCkEditorGlossary` wurde nur von `ReviewScreen` aufgerufen. Jetzt auch von `EditorScreen` aufgerufen.

---

## [2.0.0] — 2026-05-31

### Breaking Changes
- **Nutzerverwaltungssystem** — Nutzer haben jetzt einen `user_type` (`translator` / `reviewer`) und ein `is_active`-Flag. Bestehende Nutzer in der Datenbank müssen `is_active = 1` manuell gesetzt bekommen, falls sie vor diesem Release angelegt wurden, oder über das Admin-Panel reaktiviert werden.
- **Rollenbasierter Zugriff auf die Review-Warteschlange** — Nutzer mit `user_type = 'translator'` können nicht mehr auf die Review-Warteschlange zugreifen. Der Router leitet sie zum Dashboard um, und der Server liefert HTTP 403 auf Review-Endpunkten.
- **DB-Migrationen erforderlich** — Migrationen `003_users_registration_fields.sql` und `004_users_requested_role.sql` fügen neue Spalten zur `users`-Tabelle hinzu. Der Migrations-Runner wendet sie automatisch beim Server-Start an.

### Added
- **4-Schritte-Registrierungsassistent** (`register_screen.dart`) — Self-Service-Account-Erstellung: Account → Rolle → Sprachen → API-Keys. Registrierung kann global über `site_settings.registration_enabled` deaktiviert werden.
- **Panel "Wartende Nutzer"** — Admin-Screen, der Accounts mit `is_active = 0` auflistet. Admins weisen eine Rolle zu (`translator` / `reviewer`) und aktivieren jeden Account. Neben Nutzern, die die Rolle `reviewer` angefragt haben, erscheint ein Badge.
- **Panel "Aktive Nutzer"** — Admin-Screen, der Accounts mit `is_active = 1` auflistet. Admins können Nutzer deaktivieren (sperren) oder dauerhaft löschen.
- **`GET /auth/registration-status`** — öffentlicher Endpunkt; liefert `{ enabled: true/false }`.
- **`GET /admin/users/active`** — listet aktive Nutzer.
- **`PATCH /admin/users/:id/deactivate`** — deaktiviert einen aktiven Nutzer.
- **Konfetti** — `confetti`-Package integriert. `ConfettiController` in Editor- und Review-Screens feuert bei Speichern/Freigeben. Eine 900-ms-Navigationsverzögerung stellt sicher, dass die Animation sichtbar ist, bevor die Route wechselt. Umschalter im Settings-Screen.
- **Splash-Screen** — `lib/widgets/splash_screen.dart` (Flutter-Widget) + HTML-Preloader in `web/index.html`. Mindestanzeigedauer 2200 ms. Wird beim `flutter-first-frame`-Event ausgeblendet.
- **Logo** — `assets/images/logo.png` in Sidebar (44×44) und Topbar-Mini-Logo (34×34) angezeigt. App-Name von "TRANSLATION SUITE" zu "TRANSLATION HUB" geändert.
- **Zweisprachige Filter-Buttons** — jeder Dashboard-Filter zeigt das deutsche Label (fett, 13 px) und das englische Label (grau, 10 px) vertikal übereinander.
- **Split-Diff-Ansicht** — `review_diff_view.dart`: Originaltext oben (rot getönter Hintergrund), korrigierter Text unten (grün getönt). Ersetzt die vorherige überlappende Diff-Anzeige.
- **Optimistische Navigation im Review-Screen** — `_goToNextReview()` ist synchron (`void`); der Speicher-POST läuft im Hintergrund, während die App sofort zum nächsten Eintrag in der Warteschlange navigiert.
- **`inheritedQueue` im Review-Screen** — die vollständige Review-Warteschlange wird von `review_list_screen.dart` an `review_screen.dart` übergeben, um die Race-Condition zu beseitigen, die doppelt angezeigte Module verursachte.
- **Review-Liste zeigt übersetzte Titel** — `review_list_screen.dart` nutzt `meta.translation.title` und `meta.translation.summary` statt der englischen Originale, sodass Reviewer den zielsprachlichen Inhalt sehen.
- **`review_sidebar.dart` als `StatefulWidget`** — Sidebar hat einen internen `_showSourceCode`-Umschalter, um zwischen gerenderter Vorschau und roher HTML-Quellansicht zu wechseln. Enthält einen Copy-to-Clipboard-Button.
- **Off-Canvas-Umschalt-Button nach links verschoben** — der Sidebar-Umschalt-Button im Review-Screen ist jetzt auf der linken Seite des Headers.
- **Englische Quelle aus dem Haupt-Editor-Bereich entfernt** — im Review-Screen wird die englische Quelle ausschließlich innerhalb der Sidebar gezeigt. Die Tabs "Visueller Vergleich" und "Quellcode" wurden entfernt; nur "Direkter Editor" und "Vorschau" bleiben. Der "Nur vergleichen"-Button wurde entfernt.
- **Sync-Fortschritt zeigt echte Gesamtzahl** — `total` wird aus `meta.count` in der ersten Drupal.org-API-Antwort gelesen. Der Fortschrittsbalken zeigt "X Module …", solange die Gesamtzahl noch nicht bekannt ist, und wechselt dann zu "X / Y", sobald die erste Seite antwortet.
- **DB-Migrationssystem** — `server/db_migrate.js` + `server/migrations/NNN_*.sql`. Trackt angewendete Versionen in `schema_migrations`. Läuft automatisch beim Server-Start. Beendet sich mit Code 1 bei Fehlschlag.
- **Neue DB-Spalten** — `users.target_languages` (JSON-Array), `users.user_type` (ENUM), `users.requested_role` (VARCHAR), `users.deepl_api_key` (VARCHAR), `projects.changed` (BIGINT).
- **`deploy.sh` Rolling Restart** — Server- und Client-Container werden neu gebaut, ohne die Datenbank offline zu nehmen. Kein `docker compose down`.
- **`deploy.sh --db-backup`-Flag** — erstellt vor Deploy-Beginn einen komprimierten `mysqldump` in `~/backups/`.
- **Migrations-Log in deploy.sh** — das Deploy-Skript wartet auf das Server-Container-Log, um zu bestätigen, dass Migrationen erfolgreich abgeschlossen sind.
- **`watch_stale.sh`** — Shell-Skript zur Überwachung veralteter Übersetzungen auf dem Server.
- **Neue Flutter-Dateien:** `register_screen.dart`, `splash_screen.dart`, `page_transition.dart`.
- **Neue Server-Dateien:** `db_migrate.js`, `migrations/001–004_*.sql`, `watch_stale.sh`.

### Changed
- **Bulk-Übersetzungslimit** — von 200 auf 150 Module pro Request reduziert, für bessere Server-Stabilität.
- **Dio-`receiveTimeout` für Bulk-Route** — auf 10 Minuten erhöht, um große Bulk-Übersetzungs-Batches abzudecken.
- **Server-Antwort-Performance** — `res.json()` wird direkt nach dem DB-Write gesendet. `fs.writeJson` (Dateisystem-Backup) läuft asynchron im Hintergrund.

### Fixed
- **Doppelte Module in Review-Warteschlange** — verursacht durch eine Race-Condition, bei der der Review-Screen die Warteschlange unabhängig vom List-Screen abgerufen hat. Warteschlange wird jetzt als `inheritedQueue` übergeben.
- **Sync-Fortschritt zeigte "1731 / 100"** — die Gesamtzahl war auf 100 hartkodiert. Wird jetzt aus `meta.count` der ersten API-Antwort gelesen.
- **Konfetti im Review-Screen nicht sichtbar** — sofortige Navigation nach Freigabe ließ keine Zeit für die Animation. Eine 900-ms-Verzögerung wird jetzt vor der Navigation angewendet.
- **Splash-Screen-Logo nicht sichtbar** — `frameBuilder` wurde für das asynchrone Asset-Bild nicht genutzt, wodurch das Logo im ersten Frame unsichtbar war. Behoben mit korrektem asynchronem Asset-Laden.
- **Review-Karten zeigten englischen Text** — `review_list_screen.dart` liest Titel und Kurzbeschreibungen jetzt aus `meta.translation` statt aus den englischen `attributes`.

---

## [1.5.0] — 2026-05-25

### Changed
- **Fleather ersetzt Quill.js als WYSIWYG-Editor** im gesamten Flutter-Client.
  - `fleather: ^1.26.0` und `parchment: ^1.25.1` zu `pubspec.yaml` hinzugefügt.
  - Die Quill-CDN-`<link>`- und `<script>`-Tags aus `web/index.html` entfernt.
  - `editor_html_toolbar.dart` neu geschrieben — nimmt jetzt einen `FleatherController` statt
    einen `onExecCommand`-Callback entgegen. Toolbar-Buttons nutzen `ParchmentStyle.containsSame()` /
    `controller.formatSelection()` für korrekte Toggle-Semantik bei jedem Attribut.
  - `_editor_quill_bridge.dart` (Part-Datei) zu einer reinen HTML-Utility-Datei umgeschrieben;
    aller DOM-/`dart:html`-Quill-Bridge-Code entfernt.
  - `editor_screen.dart` auf `FleatherController` + `FleatherEditor` für sowohl das
    Summary- als auch das Body-Feld migriert. `TextEditingController` bleibt die HTML-Source-of-Truth
    fürs API-Speichern; ein Listener auf `FleatherController` kodiert das Parchment-Dokument
    bei jeder Bearbeitung automatisch via `ParchmentHtmlCodec` nach HTML.
  - `_editor_build_methods.dart` neu geschrieben — visuelle Container nutzen jetzt `FleatherTheme` +
    `FleatherEditor` (Dark-Theme, alle erforderlichen `FleatherThemeData`-Felder). Fest-höhige
    `SizedBox`-Wrapper durch `constraints: BoxConstraints(minHeight: …)` ersetzt, sodass
    Editoren mit dem Inhalt wachsen.
  - `review_screen.dart` vollständig migriert: Quill-Visual-Editor-`HtmlElementView`-Platform-
    Views entfernt; `FleatherEditor` an ihrer Stelle eingefügt. CodeMirror-HTML-Quell-Iframes
    für den Quellansicht-Umschalter beibehalten. Der `quill-change`-DOM-Event-Listener, `_execCommand`,
    `_setJsPendingContent` und alle `_syncHtmlToReviewIFrame`-/`_syncHtmlToReviewVisual`-
    Aufrufe durch `_reloadFleatherControllers()` und `_syncToSourceIFrame()` ersetzt.

### Removed
- Quill.js-CDN-Abhängigkeiten (`quill.snow.css`, `quill.js` 1.3.6) — werden nicht mehr geladen.
- Alle `dart:html`-basierten `document.createElement`-/`ScriptElement`-Hacks, die genutzt wurden,
  um Inhalt in Quill-Iframes zu übergeben.

---

## [1.4.0] — 2026-05-24

### Added
- **"Can't Read, Won't Buy"-Studien-Screen** (`lib/screens/help/crwb_study_screen.dart`)
  — Alle 32 Seiten der Common-Sense-Advisory-(2006)-Studie als native Flutter-
  Inhalte eingebettet. Der Screen ist immer offline verfügbar und unabhängig von der externen
  PDF-URL. Inhalt umfasst: Executive Summary, Umfrage-Demografie (2.430 Konsumenten /
  8 Länder), alle 8 Kernaussagen mit animierten Balkendiagrammen, den Besucher-Abbruch-
  Funnel (aufklappbare Kacheln), vier Fazit-Karten und einen formalen Zitationsblock.
- Route `/help/crwb` in GoRouter registriert (innerhalb der authentifizierten ShellRoute).
- **Video-Panel-Fehler-/Ladezustände** in `HelpScreen` — ein Skeleton-Spinner wird gezeigt,
  während der Server antwortet; ein bernsteinfarbenes Warnbanner ersetzt den leeren Bereich, wenn der
  Server nicht erreichbar ist oder `HELP_VIDEO_DE` / `HELP_VIDEO_EN` nicht in `.env` gesetzt sind.

### Changed
- Button "Originalstudie lesen (PDF)" in `HelpScreen` navigiert jetzt zu `/help/crwb`
  (interner Screen) statt die externe PDF-URL zu öffnen.
- `help_screen.dart` importiert jetzt `go_router` für `context.push()`; der ungenutzte
  `TokenStorage`-Import wurde entfernt.

---

## [1.3.1] — 2026-05-24

### Fixed
- **Tastaturkürzel im Help-Screen korrigiert** — drei Shortcuts (`Strg+Alt+K`, `Strg+Alt+H`, `Strg+Alt+O`), die nie im Editor implementiert wurden, wurden aus dem Shortcuts-Panel entfernt.
- **Vorschau-Shortcut-Modifikator korrigiert** — Help-Screen zeigt jetzt `Alt+P` (nicht `Strg+Alt+P`) für "Vorschau umschalten", passend zur tatsächlichen Bindung in `editor_screen.dart`.

### Changed
- `_shortcutRow()` in `HelpScreen` akzeptiert einen optionalen `showCtrl`-Parameter für Zeilen mit Nicht-Standard-Modifikatoren.
- Die Behauptung "Alle Shortcuts nutzen STRG + ALT" aus der Shortcuts-Panel-Beschreibung entfernt.

---

## [1.3.0] — 2026-05-24

### Added
- **`ModuleLogo`-Widget** (`lib/widgets/module_logo.dart`) — einheitlicher, CORS-sicherer Modul-
  Logo-Loader mit dreistufiger Kaskade: primäre `logoUrl` → `fallbackLogoUrl` → Buchstaben-Avatar.

### Fixed
- **Projekt-Karten-Logos im Browser unsichtbar** — alle Logo-Requests laufen jetzt über `/api/image-proxy`.
- **Buchstaben-Fallback für Module mit defektem GitLab-Avatar** — Module ohne GitLab-Repository zeigen jetzt das `project_browser`-Logo über die `fallbackLogoUrl`-Kaskade.

---

## [1.2.0] — 2026-05-22

### Added
- **Dashboard-Filter-Umbruch** — Filter-Buttons nutzen ein `Wrap`-Widget; fließen bei Tablet-Hochformat-Viewports (~768 px) in eine zweite Zeile.
- **Android-14-Unterstützung** — `targetSdk = 34`; `INTERNET`-Berechtigung und `android:enableOnBackInvokedCallback="true"` hinzugefügt.

### Changed
- **KI-Massenübersetzungs-Dialog — Fortschrittsmeldungen** — Fortschritt meldet jetzt Modulnummern statt Batch-Nummern.
- **KI-Massenübersetzungs-Dialog — Standardwerte** — Standardauswahl von 24 auf 25 geändert; Optionsliste zu `[25, 50, 100, 200]` geändert.
- **Profil-Screen** — den redundanten "Max Batch Size"-Schieberegler entfernt (das Steuerelement im KI-Dialog reicht).

### Fixed
- **`dart analyze`-Warnungen** — ungenutzte Variablen entfernt; `activeColor` → `activeThumbColor` bei `Switch`-Widgets korrigiert.

---

## [1.1.0] — 2026-05-20

### Added
- **`CachedNetworkImage` durchgängig** — jeden `Image.network()`-Aufruf ersetzt.
- **`RepaintBoundary` auf Hintergrundbildern** — Login-Screen- und App-Layout-Hintergründe vom Haupt-Render-Baum isoliert.
- **Help-Screen** (`screens/help/help_screen.dart`) — DSGVO-konformes Hilfe-Center mit Consent-gated YouTube-Video-Einbettungen.

### Changed
- **`Color.withOpacity()` → `.withValues(alpha:)`** — alle Flutter-Farb-Opazitäts-Aufrufe auf die nicht-veraltete API migriert.

### Fixed
- **`GlassContainer` defekte Opazität** — `.withValues(alpha: )` (leerer Wert) zu `0.1` korrigiert.

---

## [1.0.0] — 2026-04-xx

### Added
- **Flutter-Client** — vollständiger Ersatz des vorherigen React-Clients. Gebaut mit Riverpod, GoRouter, Dio und einer Glassmorphism-Dark-Mode-first-UI.
- **Server-Modularisierung** — `server/index.js` in separate Routen-Module aufgeteilt.
- **ProxyManager** — `is_reviewed`-Qualitäts-Gate, URL-Normalisierung, Port-Erkennungslogik.
- **MariaDB** als primärer Datenspeicher, ersetzt das vorherige SQLite-Setup.
- **Docker-Compose**-Dreier-Service-Stack (`db`, `server`, `client`).
- **`deploy.sh`** — automatisiertes rsync-+-Docker-Build-+-Hot-Swap-Skript; unterstützt `--client-only`-Flag.

---

## Versionsnummerierung

Versionen folgen [Semantic Versioning](https://semver.org/):
- **MAJOR** — Breaking Changes am Shadow-API-Vertrag, DB-Schema oder Zugriffskontrollmodell
- **MINOR** — neue Features, neue Endpunkte, neue UI-Screens
- **PATCH** — Bugfixes, Performance-Verbesserungen, Dokumentations-Updates
