# Cloudron-Deployment-Anleitung

*[🇬🇧 English version](CLOUDRON_DEPLOYMENT.md)*

Diese Anleitung beschreibt, wie du PB Translation Hub als Cloudron-App installierst, bestehende
Daten importierst und die App aktualisierst. Sie richtet sich an eine Administratorin bzw. einen
Administrator bei Drupal e.V., die/der das fertige Paket übernimmt.

Für das ursprüngliche (nicht-Cloudron) Docker-Compose-Deployment siehe
[DEPLOYMENT.md](DEPLOYMENT.md) — dieses Dokument gilt weiterhin für das
[unveränderte Original-Repo](https://github.com/nodedropweb/pb_translation_hub), nicht für diese
Cloudron-Paket-Variante.

---

## Schnellstart: Neuinstallation mit dem GitHub-Image

Konkretes Beispiel: Die App soll unter `pb.drupal.de` laufen, per vorgebautem Image von GHCR.

**0. Einmalige Voraussetzungen**

1. Auf dem **eigenen Rechner** (nicht auf dem Cloudron-Server) Node.js/npm und die Cloudron-CLI
   installieren:
   ```bash
   npm install -g cloudron
   ```
2. CLI mit der Cloudron-Instanz verbinden (öffnet einen Login-Flow im Browser):
   ```bash
   cloudron login my.drupal.de
   ```

**1. DNS anlegen**

A-Record `pb.drupal.de` → IP des Cloudron-Servers (und `my.drupal.de`, falls dies die erste App
auf der Instanz ist). Vor dem nächsten Schritt propagieren lassen, sonst schlägt die
Let's-Encrypt-Ausstellung fehl. **Hat der Server eine IPv6-Adresse, wird zusätzlich ein
passender AAAA-Record benötigt** — Details dazu im [DNS-Abschnitt unten](#dns).

**2. Installieren**

```bash
cloudron install --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0 --location pb
```

`:latest` funktioniert auch für eine Neuinstallation, aber **immer einen konkreten Versions-Tag
pinnen** (passend zum `version`-Feld in `CloudronManifest.json` zum Zeitpunkt der Installation)
statt sich auf `:latest` zu verlassen — siehe die Anmerkung in
[Abschnitt 5](#5-eine-installierte-app-aktualisieren), warum `:latest` `cloudron update` nicht
zuverlässig auslöst.

Läuft `drupal.de` nicht als Standarddomain der Cloudron-Instanz, sondern als eine von mehreren
konfigurierten Domains, zusätzlich `--domain drupal.de` anhängen.

Nach ca. 26 Sekunden ist die (leere) App unter `https://pb.drupal.de` erreichbar.

**3. App-Secrets setzen**

```bash
cloudron env set --app pb.drupal.de JWT_SECRET=<eigener-zufälliger-wert>
```

Ohne eigenen `JWT_SECRET` läuft die App zwar, signiert Login-Tokens aber mit einem im öffentlichen
Quellcode sichtbaren Fallback-Wert — vor dem produktiven Einsatz unbedingt setzen. Für Unsplash-
Bildsuche und Hilfe-Videos siehe den vollständigen Befehl im
[Abschnitt „App-Secrets" unten](#app-secrets-env-werte).

**4. Weiter je nach Fall**

- **Frische/leere Installation** → fertig. `https://pb.drupal.de` öffnen, ersten Account
  registrieren, Sync von Drupal.org anstoßen.
- **Bestehende Daten übernehmen** (z. B. Umzug vom bisherigen Docker-Compose-Deployment) → weiter
  mit [Abschnitt 3](#3-nach-der-installation-bestehende-daten-importieren) unten (Datenbank-Dump
  + `translations`/`metadata`/`uploads` importieren), danach
  `cloudron restart --app pb.drupal.de`.

**5. Später aktualisieren**

```bash
cloudron update --app pb.drupal.de --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:<neue-version>
```

Den Tag der **neuen** Version verwenden (z. B. `0.3.0`), nicht `:latest` — siehe die Anmerkung in
[Abschnitt 5](#5-eine-installierte-app-aktualisieren) unten.

Alles Weitere unten (Datenimport im Detail, MariaDB/MySQL-Kompatibilität, bekannte
Cloudron-Eigenheiten) ist Nachschlagewerk für die Details — für eine reine Neuinstallation ohne
Datenübernahme reichen die fünf Schritte oben.

---

## 1. Architektur

Cloudron-Apps laufen als **ein einzelner Container mit einem einzigen Port** — ein Docker-Compose-
Äquivalent gibt es hier nicht. Dieses Paket fasst die ursprünglich drei Services in einem
zusammen:

```
Internet → Cloudron-Reverse-Proxy (443) → App-Container (httpPort 3000)
                                              │
                                    nginx (liefert den Flutter-Web-Build aus,
                                    reicht /api/, /uploads/ und die rohen
                                    /{lang}/{file}.json-Routen durch)
                                              │ 127.0.0.1:9901
                                    Node.js-Backend (server/index.js)
                                              │
                          ┌───────────────────┴───────────────────┐
                          │                                       │
                 Cloudron-MySQL-Addon                   Cloudron-Localstorage-Addon
                 (CLOUDRON_MYSQL_*-Env-Vars)                    (/app/data)
```

Das Container-Dateisystem ist **read-only, außer `/app/data`, `/tmp` und `/run`** — sieh dir
`start.sh` und `Dockerfile` an, um zu sehen, wie nginx' Temp-/Log-Pfade und das
Upload-Verzeichnis des Node-Backends entsprechend umgeleitet werden.

---

## 2. Die App installieren

### Empfohlen: das vorgebaute Image installieren

Nach jedem Release wird ein vorgebautes Image unter `ghcr.io/nodedropweb/pb_translation_hub-cloudron`
veröffentlicht. **Diesen Weg nutzen, sofern kein konkreter Grund für einen Build aus dem
Quellcode besteht** — das ist unser empfohlener Standard für eine Produktivinstallation:

```bash
cloudron login my.<deine-domain>
cloudron install --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0 --location <subdomain>
```

Kein Build-Schritt, kein Flutter-SDK-Download auf deinem Cloudron-Server — Cloudron zieht das
Image nur noch und startet es. Gemessen bei einer frischen Installation: **~26 Sekunden**,
gegenüber 5–10 Minuten beim Bauen aus dem Quellcode (allein der Flutter-Web-Release-Build
dauert mehrere Minuten). Das Ergebnis ist in beiden Fällen identisch — es geht rein um die
Install-/Update-Geschwindigkeit.

Einen echten Versions-Tag statt `:latest` pinnen — `:latest` ist für eine einmalige
Neuinstallation in Ordnung, aber `cloudron update` braucht einen tatsächlich anderen Tag-String
zwischen den Aufrufen, um zu erkennen dass es etwas Neues gibt (siehe
[Abschnitt 5](#5-eine-installierte-app-aktualisieren)) — mit einem Versions-Tag zu starten hält
Install- und Update-Befehle konsistent.

### Alternative: aus dem Quellcode bauen

Nur nötig, wenn du am Paket selbst entwickelst, oder `ghcr.io` von deinem Cloudron-Server aus
aus irgendeinem Grund nicht erreichbar ist:

```bash
git clone https://github.com/nodedropweb/pb_translation_hub-cloudron.git
cd pb_translation_hub-cloudron
cloudron login my.<deine-domain>
cloudron install --location <subdomain>
```

Cloudron baut das Image direkt auf deinem Cloudron-Server — kein lokales Docker nötig, aber
spürbar langsamer, und es bindet während des Baus CPU auf dem Server.

### DNS

Cloudron braucht einen A-Record für `<subdomain>.<deine-domain>` (und, falls dies die erste App
auf einer frischen Cloudron-Instanz ist, auch einen für `my.<deine-domain>`), der **vor** der
Installation auf die Server-IP zeigt — der Install-Schritt stellt per HTTP-Validierung ein
Let's-Encrypt-Zertifikat aus.

> **IPv6-Hinweis:** Hat der Cloudron-Server eine IPv6-Adresse, erkennt Cloudron das automatisch
> und verlangt beim Zertifikats-Check zusätzlich zum A- auch einen passenden **AAAA-Record** für
> dieselbe Subdomain. Fehlt dieser oder zeigt er auf eine falsche/veraltete Adresse, kann die
> Zertifikatsausstellung bzw. -erneuerung fehlschlagen oder hängen bleiben — selbst wenn der
> A-Record korrekt ist. Zwei Optionen: entweder einen korrekten AAAA-Record für die Subdomain
> anlegen, oder den IPv6-Support in den Cloudron-Netzwerkeinstellungen deaktivieren, um den Check
> zu überspringen. Hat der Server gar keine IPv6-Adresse, entfällt die Prüfung von selbst und ein
> reiner A-Record genügt.

### App-Secrets (.env-Werte)

Das Docker-Compose-Deployment liest Secrets (Unsplash-API-Keys, `JWT_SECRET`, …) aus einer
lokalen `server/.env`-Datei — die ist bewusst nicht Teil des Repos und landet auch nicht im
gebauten Image (schon gar nicht jetzt, wo das GHCR-Image öffentlich ist). Im frisch installierten
Cloudron-Container ist deshalb **keiner dieser Werte gesetzt**, ohne dass das an irgendeiner
Stelle auffällt — Unsplash-Bildsuche, Hilfe-Videos und die Debug-Endpunkte bleiben einfach
stillschweigend deaktiviert.

Cloudron hat dafür einen eigenen, genau dafür vorgesehenen Mechanismus — `cloudron env` —, der wie
die Addon-Variablen (`CLOUDRON_MYSQL_*`) funktioniert und ohne Code-Änderung greift, weil die App
ohnehin überall `process.env.X` liest:

```bash
cloudron env set --app <subdomain> \
  JWT_SECRET=<eigener-zufälliger-wert> \
  UNSPLASH_ACCESS_KEY=<...> \
  HELP_VIDEO_DE=<youtube-link> \
  HELP_VIDEO_EN=<youtube-link> \
  PB_DEBUG_KEY=<eigener-wert>
```

`cloudron env set` startet den Container automatisch neu; die Werte sind danach sofort aktiv
(geprüft mit `cloudron exec --app <subdomain> -- printenv <NAME>`). Mit `cloudron env list --app
<subdomain>` lassen sich die aktuell gesetzten Werte einsehen, mit `cloudron env unset` wieder
entfernen. Auch einzelne Werte lassen sich so jederzeit ändern (z. B. ein neuer Video-Link) —
das ist ein reiner Konfigurationswechsel und braucht **kein** neues Image, keinen Rebuild, kein
`cloudron update`.

**Was macht welcher Wert?**

| Variable | Zweck | Wenn nicht gesetzt |
|---|---|---|
| `JWT_SECRET` | Signiert die Login-Tokens **aller** Nutzer (Auth). Der Code prüft nur die Signatur, nicht nochmal die Rolle in der DB — wer den Wert kennt, kann sich ein Token mit `role: admin` selbst bauen. | Fällt auf einen im öffentlichen Quellcode sichtbaren Wert zurück — **unbedingt setzen**, bevor die App produktiv genutzt wird. |
| `UNSPLASH_ACCESS_KEY` | Zufälliges Hintergrundbild fürs Theme (`/api/unsplash/random-bg`). | App fällt automatisch auf fest hinterlegte Bild-URLs zurück — rein kosmetisch, kein Fehler. |
| `HELP_VIDEO_DE` / `HELP_VIDEO_EN` | YouTube-Tutorial-Video auf der Hilfeseite, je Sprache. | Video-Panel wird ausgeblendet, kein Fehler. |
| `PB_DEBUG_KEY` | Schaltet zwei Debug-Endpunkte frei (Vorschau auf noch nicht freigegebene Übersetzungen, Sync-Inspektion) — für Mitwirkende, nicht für Endnutzer gedacht. | Beide Endpunkte antworten mit 403, sicher deaktiviert — optional. |

`UNSPLASH_APP_ID` und `UNSPLASH_SECRET_KEY` (in `server/.env.example` gelistet) werden im Code
aktuell **nicht** verwendet und müssen nicht gesetzt werden.

> **Wichtig — `JWT_SECRET` wirklich setzen.** Der Code hat einen Fallback-Wert, falls
> `JWT_SECRET` fehlt, und der steht wortwörtlich im öffentlichen Quellcode
> (`server/index.js`). Bleibt er unverändert, kann jeder, der den Quellcode kennt, gültige
> Login-Tokens fälschen. **Vor dem produktiven Einsatz unbedingt einen eigenen, zufälligen Wert
> setzen.**

Welche Variablen es gibt und wofür sie sind, steht in `server/.env.example` im Repo. Die
tatsächlichen Werte (Unsplash-Zugangsdaten etc.) bekommst du — wie den Datenexport aus
[Abschnitt 3](#3-nach-der-installation-bestehende-daten-importieren) — vom aktuellen Maintainer
über einen privaten Kanal.

---

## 3. Nach der Installation: bestehende Daten importieren

Eine frische Installation hat eine **leere** Datenbank und keine Übersetzungsdateien. Wenn du ein
bestehendes Deployment übernimmst (z. B. beim Umzug vom Docker-Compose-Setup), importiere dessen
Daten einmalig direkt nach der Installation.

**Woher bekomme ich den Datenexport?** Das Hauptrepo (`pb_translation_hub`) bringt dafür
`export_for_cloudron.sh` mit — es zieht einen frischen Dump direkt aus dem laufenden
MariaDB-Deployment und wendet dabei schon beide Fixes aus
[Abschnitt 4](#4-mariadb--mysql-8-kompatibilitätshinweise) an (Collation-Ersetzung +
Strip/Re-Add der generierten Spalten) — keine manuelle SQL-Chirurgie nötig:

```bash
# aus pb_translation_hub/ heraus
./export_for_cloudron.sh                       # schreibt exports/pb_hub_cloudron_<stamp>.sql.gz
./export_for_cloudron.sh --import-to <subdomain> [--yes]   # importiert auch direkt (siehe 3a)
```

Es fasst nur Übersetzungs-/DB-Daten an — `metadata`/`status.json`/`uploads` (Abschnitt 3b) müssen
weiterhin manuell kopiert werden. Bekommst du stattdessen einen anders erzeugten Export (z. B.
einen rohen `mysqldump`), explizit nachfragen, ob er bereits MySQL-8-angepasst ist — falls nicht,
gelten die Fixes aus Abschnitt 4.

### 3a. Datenbank

**Empfohlen — per Skript:** `./export_for_cloudron.sh --import-to <subdomain>` legt zuerst per
`cloudron backup create` ein Sicherheits-Backup der Ziel-App an und spielt den transformierten
Dump danach direkt in deren MySQL-Addon ein. `--yes` überspringt die Sicherheitsabfrage für den
nicht-interaktiven Einsatz — nur setzen, wenn das wirklich gewollt ist, sonst greift die
interaktive Nachfrage als Sicherheitsnetz.

**Manuelle Alternative:** die von Cloudron in den Container injizierten MySQL-Addon-Zugangsdaten
abrufen:

```bash
cloudron exec --app <subdomain> -- env | grep CLOUDRON_MYSQL
```

Einen bereits transformierten Dump importieren (siehe die
[MariaDB-→-MySQL-Kompatibilitätshinweise](#4-mariadb--mysql-8-kompatibilitätshinweise) unten —
ein Dump direkt aus dem ursprünglichen MariaDB-Deployment lässt sich **nicht** unverändert
importieren):

```bash
gunzip -c dump.sql.gz | cloudron exec --app <subdomain> -- \
  mysql -h "$CLOUDRON_MYSQL_HOST" -u "$CLOUDRON_MYSQL_USERNAME" -p"$CLOUDRON_MYSQL_PASSWORD" "$CLOUDRON_MYSQL_DATABASE"
```

(Die tatsächlichen Werte aus Schritt 1 einsetzen — `cloudron exec` expandiert die eigenen
Env-Vars des Containers in so einer von außen eingeschleusten Shell-Zeile nicht automatisch.)

### 3b. Übersetzungsdateien & Uploads

Der Datenverzeichnis-Aufbau der App unter `/app/data`:

```
/app/data/
  status.json
  metadata/       ← eine JSON-Datei pro gesynctem Drupal.org-Projekt
  translations/
    de/           ← eine JSON-Datei pro übersetztem Projekt, je Sprache
    fr/
    ...
  uploads/
    avatars/
```

Ein bestehendes `server/data/{metadata,translations,status.json}` und `server/uploads/` aus dem
Ausgangs-Deployment nach `/app/data` auf der Cloudron-App kopieren:

```bash
cloudron push --app <subdomain> pfad/zu/metadata     /app/data/metadata
cloudron push --app <subdomain> pfad/zu/translations /app/data/translations
cloudron push --app <subdomain> pfad/zu/status.json  /app/data/status.json
cloudron push --app <subdomain> pfad/zu/uploads       /app/data/uploads
```

> **⚠️ Bekannte Falle — Verzeichnis-Verschachtelung.** Die App legt beim allerersten Start leere
> Platzhalter-Verzeichnisse an (`metadata/`, `translations/`, `uploads/`, via
> `fs.ensureDirSync(...)` in `server/index.js`). Kopierst du Daten *nachdem* die App schon einmal
> gestartet ist — was sie sein wird, da der Health-Check bei der Installation einen laufenden
> Server voraussetzt — und deine Kopiermethode ist ein einfaches Verschieben/Kopieren statt eines
> echten Merges (uns ist genau das beim Testen passiert: `mv extracted/translations
> /app/data/translations`, während `/app/data/translations` bereits als leeres Verzeichnis
> existierte, hat die Daten still und leise eine Ebene zu tief verschachtelt —
> `/app/data/translations/translations` statt den Inhalt zu ersetzen), findet die App nichts und
> verhält sich, als wäre der Import nie passiert. **Nach dem Kopieren die Struktur immer direkt
> verifizieren** — z. B. sollte `cloudron exec --app <subdomain> -- ls /app/data/translations`
> Sprachcodes (`de`, `fr`, …) direkt auflisten, nicht einen weiteren `translations`-Ordner.

Nach dem Import von Datenbank UND Dateien die App neu starten, damit alles übernommen wird:

```bash
cloudron restart --app <subdomain>
```

Prüfen mit:

```bash
curl -s "https://<subdomain>.<deine-domain>/api/projects/filter-counts?langcode=de"
```

Die Zahlen sollten ungleich null sein und zum Ausgangs-Deployment passen.

---

## 4. MariaDB-→-MySQL-8-Kompatibilitätshinweise

Das ursprüngliche Deployment läuft auf **MariaDB 11.8**; Cloudrons MySQL-Addon ist
**MySQL 8.0.31**. Ein roher `mysqldump` von der MariaDB-Seite lässt sich nicht unverändert
importieren. `pb_translation_hub/export_for_cloudron.sh` automatisiert beide Fixes unten
(End-to-End gegen einen echten MySQL-8-Container verifiziert — voller Datensatz, alle Tabellen,
Apostrophe/Mehrbyte-Inhalte kommen unversehrt an); dieser Abschnitt dokumentiert, was es tut, für
alle, die einen Dump stattdessen von Hand patchen:

1. **Collation** `utf8mb4_uca1400_ai_ci` (nur MariaDB) → wird ersetzt durch `utf8mb4_unicode_ci`
   (portabel, wird von den Migrationen dieses Repos selbst und von `glossary_terms` genutzt, was
   Mixed-Collation-Join-Fehler gegen über den normalen Migrationsweg angelegte Tabellen vermeidet)
   im gesamten Dump. `utf8mb4_0900_ai_ci` (MySQL 8s natives Standard-Collation) funktioniert beim
   manuellen Patchen genauso.
2. **Generierte Spalten** (`projects.semver_min` / `semver_max`,
   `STORED GENERATED ALWAYS AS`): `mysqldump`/`mariadb-dump` schreibt deren berechnete Werte
   direkt in die `INSERT`-Statements. MariaDB toleriert das; MySQL 8 wirft
   `ER_GENERATED_COLUMN_NOT_ALLOWED` (Fehler 3105), weil es einen expliziten Wert für eine
   generierte Spalte strikt verbietet. Fix: `projects` *ohne* `semver_min`/`semver_max` anlegen,
   die Daten per `INSERT`s laden, die nur die echten Spalten benennen, dann beide Spalten **nach**
   dem Laden der Daten per `ALTER TABLE projects ADD COLUMN ... GENERATED ALWAYS AS (...) STORED`
   hinzufügen — MySQL berechnet die Werte an diesem Punkt selbst.
   (Eine von `mysqldump` erzeugte mehrzeilige `INSERT`-Anweisung textuell zu kürzen ist gegen
   JSON-Inhalte mit Kommas/Anführungszeichen fragil; das Skript erzeugt die `projects`-Zeilen
   stattdessen selbst per `SELECT ... QUOTE(...)` und umgeht das Problem ganz.)
   - **Falle, falls man das selbst baut:** Erzeugt man diese `INSERT`s per `mysql -B`
     (Batch-Modus), werden sie doppelt escaped — der Batch-Modus wendet sein eigenes
     TSV-artiges Backslash-Escaping zusätzlich zu `QUOTE()`s bereits korrektem SQL-Escaping an,
     was jeden Wert mit echtem Backslash zerstört (z. B. JSON-Text mit eingebettetem `\r\n`) und
     beim Import mit `Unknown command '\\'` fehlschlägt. `-r`/`--raw` unterdrückt das erneute
     Escaping des Batch-Modus.

Startest du stattdessen von einer **leeren** Datenbank, betrifft dich das alles nicht — die
mitgelieferten Migrationen in `server/migrations/` sind bereits MySQL-8-sicher und laufen
automatisch beim ersten Start.

---

## 5. Eine installierte App aktualisieren

**Immer den Tag der neuen Version angeben, nie `:latest`.** `cloudron update` entscheidet anhand
eines Vergleichs des übergebenen Image-Verweises mit dem aktuell installierten, ob es etwas zu
tun gibt — übergibt man beide Male `:latest`, hat sich der Tag-String aus Cloudrons Sicht nicht
geändert, und das Update kann stillschweigend zu nichts führen, obwohl unter diesem Tag längst
ein neueres Image gepusht wurde. `:latest` funktioniert zuverlässig nur bei der *ersten*
Installation einer App, nicht beim Aktualisieren einer bereits laufenden. Die Ziel-Version immer
aus [dem Changelog](CHANGELOG.de.md)/[den Releases](https://github.com/nodedropweb/pb_translation_hub-cloudron/releases)
oder dem `version`-Feld in `CloudronManifest.json` des Commits entnehmen, auf den aktualisiert
werden soll.

```bash
cloudron update --app <subdomain> --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0
```

Falls stattdessen aus dem Quellcode gebaut wurde:

```bash
cd pb_translation_hub-cloudron   # wo auch immer du geklont hast
git pull
cloudron update --app <subdomain>
```

`cloudron update` erstellt immer zuerst automatisch einen Backup-Snapshot und führt dann einen
Rolling Restart durch — anders als beim Rolling Restart des Docker-Compose-Deployments gibt es
hier aber nur **einen einzigen Container**, daher entsteht ein kurzes Downtime-Fenster während
Neubau und Neustart (typischerweise unter einer Minute, sobald das Image gebaut ist).

---

## 6. Bekannte Cloudron-Packaging-Eigenheiten (beim Testen gefunden)

Diese haben uns echte Debugging-Zeit gekostet und sind gut zu kennen, bevor du selbst danach
suchst:

- **`iconUrl` (das dokumentierte, nicht als veraltet markierte Manifest-Feld) funktioniert bei
  CLI-gesteuerten Installationen nicht** — es wird zwar per Schema validiert, aber die CLI
  (`@cloudron` `actions.js`) ruft es weder bei Install noch bei Update tatsächlich ab. Was
  wirklich funktioniert, ist das offiziell "als veraltet markierte" Feld `icon`, das auf eine
  **lokale Datei** im Paket zeigt (z. B. `"icon": "logo.png"`) — die CLI liest sie ein und lädt
  sie direkt als Teil des Install-Requests hoch.
- **Das Icon wird nur bei einer echten Neuinstallation angehängt**, nicht bei `cloudron update`
  oder `cloudron repair` einer bereits installierten App — obwohl der Code-Pfad für `update` das
  Icon-Feld ebenfalls einliest und mitsendet. War eine App jemals ohne funktionierendes Icon
  installiert, half nur `cloudron uninstall` + frisches `cloudron install`.
- **Die JSON-Ausgabe von `cloudron inspect` zeigt das Icon nicht**, selbst wenn es tatsächlich
  korrekt gespeichert ist und ausgeliefert wird — stattdessen über den echten Icon-Endpoint
  prüfen (`https://my.<domain>/api/v1/apps/<app-id>/icon`), nicht `inspect` vertrauen.
- **`cloudron push` hat einen Pfad-Auflösungs-Bug unter Windows** — selbst eine triviale lokale
  Datei scheitert mit einer irreführenden Meldung
  `bash: line 1: <verstümmelter-Pfad>: No such file or directory`. Workaround: stattdessen
  `cloudron exec` nutzen und Daten per SSH/Docker von einem Linux-Host einschleusen (siehe
  Abschnitt 3 oben), oder die CLI aus WSL/Linux statt nativem Windows heraus ausführen.
- **nginx' Standard-Temp- und Log-Pfade liegen auf dem read-only-Teil des Dateisystems** —
  sowohl `/var/lib/nginx/*` als auch `/var/log/nginx/*` müssen umgeleitet werden (zu `/run/*`
  bzw. auf stdout/stderr), sonst crash-loopt der Container sofort beim Start. Bereits in
  `nginx/app.conf` und `Dockerfile` dieses Repos berücksichtigt.
- **Verzeichnis-Berechtigungen können verlorengehen, wenn der Build-Kontext von einem
  Windows/WSL-Host hochgeladen wird** — `routes/`, `migrations/` usw. kamen im gebauten Image
  ohne Ausführungsrecht an (`drw-rw-rw-`), was `require()`s Verzeichnis-Traversierung mit einer
  irreführenden "Cannot find module"-Fehlermeldung brach, obwohl die Datei physisch vorhanden
  war. Behoben mit einem pauschalen `chmod -R a+rX` nach allen `COPY`-Schritten im `Dockerfile`.

---

## 7. Für Maintainer: eine Code-Änderung veröffentlichen

Dieser Abschnitt richtet sich an den/die Maintainer des Pakets (nicht an den Drupal-e.V.-Admin,
der es betreibt) — wie ein lokaler Commit ins `ghcr.io`-Image kommt, das `cloudron update` zieht.

**Voraussetzungen:** Docker installiert, wo auch immer du baust (eigener Rechner oder ein
beliebiger Linux-Host — muss nicht der Cloudron-Server selbst sein), sowie ein
GitHub-Personal-Access-Token mit `write:packages`-Scope für `docker login ghcr.io`.

**Zuerst die Version hochzählen** — das `version`-Feld in `CloudronManifest.json`, nach Semver
(Patch für Fixes, Minor für Features, passend zum Eintrag in `CHANGELOG.md`). Diese Versionsnummer
*ist* der Image-Tag, der unten gepusht wird; daran erkennt `cloudron update`, dass es etwas Neues
gibt (siehe die Anmerkung in [Abschnitt 5](#5-eine-installierte-app-aktualisieren) — `:latest`
löst bei einer bereits installierten App **kein** zuverlässiges Update aus, nur bei einer
Neuinstallation).

```bash
cd pb_translation_hub-cloudron
# "version" in CloudronManifest.json hochzählen, z. B. 0.1.0 → 0.2.0; CHANGELOG.md-Eintrag ergänzen
git add -A && git commit -m "..." && git push origin master   # Änderung zuerst landen

docker build -t ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0 .

docker login ghcr.io -u <dein-github-username>   # nur einmal pro Rechner nötig
docker push ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0

# Optional: zusätzlich den mitlaufenden `latest`-Tag verschieben — nur als Komfort für einen
# *neuen* Install-Befehl ohne Versionsangabe. Für Updates niemals allein darauf verlassen.
docker tag ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0 ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest
docker push ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest
```

Der Flutter-Web-Build-Schritt innerhalb von `docker build` dauert mehrere Minuten — dieselben
Kosten, die in [Abschnitt 2](#2-die-app-installieren) für eine Quellcode-Installation beschrieben
sind, hier aber nur einmal statt auf jedem Cloudron-Server jedes Admins.

### 7a. Einen Daten-Seed ins Image backen (optional)

Eine frische Installation hat normalerweise eine leere Datenbank — siehe
[Abschnitt 3](#3-nach-der-installation-bestehende-daten-importieren) für den manuellen
Post-Install-Import. Alternativ kann sich das Image beim ersten Start selbst befüllen, sodass eine
frische Installation den kompletten Übersetzungs-Korpus schon ohne manuellen Schritt mitbringt:

```bash
# aus pb_translation_hub/ (Hauptrepo) heraus, vor docker build:
./export_for_cloudron.sh --seed ../pb_translation_hub-cloudron/server/seed/db_seed.sql.gz
```

Danach `docker build` wie oben — `server/seed/` liegt bereits im Build-Kontext und wird automatisch
mit ins Image gebacken (kein eigenes `COPY` nötig, es liegt schon unter `server/`). Fehlt die
Datei, baut das Image trotzdem problemlos — Seeding ist dann zur Laufzeit einfach ein No-op.

Der Seed enthält **nur Inhalts-Daten** — `projects`, `translations`, `glossary_terms`,
`priority_projects`, `ignored_projects`, `sync_events`, `site_settings`. Bewusst ausgeschlossen:
`users` (damit eine geseedete Instanz per normaler Registrierung ihren eigenen frischen
Admin-Account bekommt, nicht deinen echten Passwort-Hash) und `schema_migrations` (damit die
Buchführung des Migrationsrunners unangetastet bleibt). Übersetzungs-JSON-Dateien sind ebenfalls
nicht Teil des Seeds — die bestehende Startup-Logik (`ensureTranslationFilesFromDb()`) erzeugt sie
ohnehin automatisch aus der `translations`-Tabelle, sobald das Übersetzungsverzeichnis leer ist.

Das Seeding selbst läuft nur, wenn explizit angefordert — `SEED_ON_FIRST_BOOT=true` auf der App
setzen (Cloudron-Dashboard → App → Environment Variables, oder `cloudron env set`). Es prüft vorher,
ob `projects` noch leer ist, ist also unbedenklich dauerhaft gesetzt zu lassen: es rührt eine bereits
befüllte Datenbank bei keinem späteren Neustart oder Update an.

Nach dem Push zieht jeder, der `cloudron update --app <subdomain> --image
ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0` ausführt (siehe
[Abschnitt 5](#5-eine-installierte-app-aktualisieren)), das neue Image — mit dem **exakten
Versions-Tag, der gerade gepusht wurde**, nicht mit `:latest`.
