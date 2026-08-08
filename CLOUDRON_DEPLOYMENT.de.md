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
cloudron install --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest --location pb
```

Läuft `drupal.de` nicht als Standarddomain der Cloudron-Instanz, sondern als eine von mehreren
konfigurierten Domains, zusätzlich `--domain drupal.de` anhängen.

Nach ca. 26 Sekunden ist die (leere) App unter `https://pb.drupal.de` erreichbar.

**3. Weiter je nach Fall**

- **Frische/leere Installation** → fertig. `https://pb.drupal.de` öffnen, ersten Account
  registrieren, Sync von Drupal.org anstoßen.
- **Bestehende Daten übernehmen** (z. B. Umzug vom bisherigen Docker-Compose-Deployment) → weiter
  mit [Abschnitt 3](#3-nach-der-installation-bestehende-daten-importieren) unten (Datenbank-Dump
  + `translations`/`metadata`/`uploads` importieren), danach
  `cloudron restart --app pb.drupal.de`.

**4. Später aktualisieren**

```bash
cloudron update --app pb.drupal.de --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest
```

Alles Weitere unten (Datenimport im Detail, MariaDB/MySQL-Kompatibilität, bekannte
Cloudron-Eigenheiten) ist Nachschlagewerk für die Details — für eine reine Neuinstallation ohne
Datenübernahme reichen die vier Schritte oben.

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
cloudron install --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest --location <subdomain>
```

Kein Build-Schritt, kein Flutter-SDK-Download auf deinem Cloudron-Server — Cloudron zieht das
Image nur noch und startet es. Gemessen bei einer frischen Installation: **~26 Sekunden**,
gegenüber 5–10 Minuten beim Bauen aus dem Quellcode (allein der Flutter-Web-Release-Build
dauert mehrere Minuten). Das Ergebnis ist in beiden Fällen identisch — es geht rein um die
Install-/Update-Geschwindigkeit.

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

---

## 3. Nach der Installation: bestehende Daten importieren

Eine frische Installation hat eine **leere** Datenbank und keine Übersetzungsdateien. Wenn du ein
bestehendes Deployment übernimmst (z. B. beim Umzug vom Docker-Compose-Setup), importiere dessen
Daten einmalig direkt nach der Installation.

**Woher bekomme ich den Datenexport?** Du bekommst dafür kein Skript, sondern ein fertiges Archiv
(DB-Dump + `metadata`/`translations`/`status.json`/`uploads`) vom bisherigen Betreiber des
Produktiv-Deployments — frag beim aktuellen Maintainer nach, der stellt dir einen aktuellen Export
über einen privaten Kanal (nicht öffentlich verlinkt) bereit. Der Dump aus einem laufenden
MariaDB-Deployment ist normalerweise **nicht** unverändert MySQL-8-kompatibel — bitte explizit
nachfragen, ob der Export bereits für MySQL 8 angepasst wurde (siehe
[Abschnitt 4](#4-mariadb--mysql-8-kompatibilitätshinweise)), das erspart dir die manuellen Fixes.

### 3a. Datenbank

Die von Cloudron in den Container injizierten MySQL-Addon-Zugangsdaten abrufen:

```bash
cloudron exec --app <subdomain> -- env | grep CLOUDRON_MYSQL
```

Einen Dump importieren (siehe die
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
importieren. Zwei konkrete Inkompatibilitäten wurden gefunden und müssen im Dump vor dem Import
gepatcht werden (beide sind bereits in den `server/migrations/*.sql` dieses Repos gefixt, die auf
einer frischen/leeren Datenbank automatisch greifen — ein **wiederhergestellter Dump** umgeht den
Migrations-Runner aber und braucht dieselben Fixes direkt an der SQL-Datei):

1. **Collation** `utf8mb4_uca1400_ai_ci` (nur MariaDB) → im gesamten Dump ersetzen durch
   `utf8mb4_0900_ai_ci` (MySQL 8s natives Äquivalent) oder `utf8mb4_unicode_ci` (portabel, wird
   von den Migrationen dieses Repos selbst genutzt).
2. **Generierte Spalten** (`projects.semver_min` / `semver_max`,
   `STORED GENERATED ALWAYS AS`): `mysqldump` schreibt deren berechnete Werte direkt in die
   `INSERT`-Statements. MariaDB toleriert das; MySQL 8 wirft
   `ER_GENERATED_COLUMN_NOT_ALLOWED` (Fehler 3105), weil es einen expliziten Wert für eine
   generierte Spalte strikt verbietet. Fix: `semver_min`/`semver_max` aus dem
   `CREATE TABLE projects`-Statement und aus den `INSERT`-Werten jeder Zeile entfernen, dann
   beide Spalten **nach** dem Laden der Daten per
   `ALTER TABLE projects ADD COLUMN ... GENERATED ALWAYS AS (...) STORED` wieder hinzufügen —
   MySQL berechnet die Werte an diesem Punkt selbst, keine expliziten Werte nötig.

Startest du stattdessen von einer **leeren** Datenbank, betrifft dich das alles nicht — die
mitgelieferten Migrationen in `server/migrations/` sind bereits MySQL-8-sicher und laufen
automatisch beim ersten Start.

---

## 5. Eine installierte App aktualisieren

Empfohlen (passend zum empfohlenen Install-Weg):

```bash
cloudron update --app <subdomain> --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest
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

```bash
cd pb_translation_hub-cloudron
git add -A && git commit -m "..." && git push origin master   # Änderung zuerst landen

docker build -t ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest .

docker login ghcr.io -u <dein-github-username>   # nur einmal pro Rechner nötig
docker push ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest
```

Der Flutter-Web-Build-Schritt innerhalb von `docker build` dauert mehrere Minuten — dieselben
Kosten, die in [Abschnitt 2](#2-die-app-installieren) für eine Quellcode-Installation beschrieben
sind, hier aber nur einmal statt auf jedem Cloudron-Server jedes Admins.

Nach dem Push zieht jeder, der `cloudron update --app <subdomain> --image
ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest` ausführt (siehe
[Abschnitt 5](#5-eine-installierte-app-aktualisieren)), automatisch das neue Image — es ist kein
separates "Release" oder Versions-Bump nötig, damit sich der `latest`-Tag aktualisiert. Sollen
Installationen stattdessen auf eine feste Version statt immer `latest` gepinnt werden, zusätzlich
einen Versions-Tag pushen (z. B. `docker push
ghcr.io/nodedropweb/pb_translation_hub-cloudron:2.4.0`) und diesen Tag im Update-/Install-Befehl
referenzieren.
