# Cloudron Deployment Guide

This document describes how to install, migrate data into, and update PB Translation Hub as a
Cloudron app. It is written for a Drupal e.V. administrator taking over the packaged app for the
first time.

For the original (non-Cloudron) docker-compose deployment, see [DEPLOYMENT.md](DEPLOYMENT.md) —
that document still applies to the [unmodified upstream repo](https://github.com/nodedropweb/pb_translation_hub),
not this Cloudron-packaged variant.

---

## 1. Architecture

Cloudron apps run as a **single container with a single port** — there is no docker-compose
equivalent here. This package consolidates the original three services into one:

```
Internet → Cloudron reverse proxy (443) → app container (httpPort 3000)
                                              │
                                    nginx (serves the Flutter web build,
                                    proxies /api/, /uploads/, and the raw
                                    /{lang}/{file}.json routes)
                                              │ 127.0.0.1:9901
                                    Node.js backend (server/index.js)
                                              │
                          ┌───────────────────┴───────────────────┐
                          │                                       │
                 Cloudron MySQL addon                   Cloudron localstorage addon
                 (CLOUDRON_MYSQL_* env vars)                    (/app/data)
```

The container filesystem is **read-only except `/app/data`, `/tmp`, and `/run`** — see
`start.sh` and `Dockerfile` for how nginx's temp/log paths and the Node backend's upload
directory are redirected accordingly.

---

## 2. Installing the app

### Option A — build from source (slower, no prerequisites beyond the Cloudron CLI)

```bash
git clone https://github.com/nodedropweb/pb_translation_hub-cloudron.git
cd pb_translation_hub-cloudron
cloudron login my.<your-domain>
cloudron install --location <subdomain>
```

The Flutter web build alone takes several minutes; the whole install typically takes 5–10
minutes. Cloudron builds the image directly on your Cloudron server.

### Option B — install a prebuilt image (recommended, seconds instead of minutes)

If a prebuilt image has been published to `ghcr.io/nodedropweb/pb_translation_hub-cloudron`:

```bash
cloudron install --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest --location <subdomain>
```

No build step, no Flutter SDK download — Cloudron just pulls and runs the image.

### DNS

Cloudron needs an A record for `<subdomain>.<your-domain>` (and, if this is the first app on a
fresh Cloudron instance, one for `my.<your-domain>` too) pointing at the server's IP **before**
installing — the install step provisions a Let's Encrypt certificate via HTTP validation.

---

## 3. Post-install: importing existing data

A fresh install has an **empty** database and no translation files. If you're taking over an
existing deployment (e.g. migrating off the docker-compose setup), import its data once, right
after install:

### 3a. Database

Get the MySQL addon credentials Cloudron injected into the container:

```bash
cloudron exec --app <subdomain> -- env | grep CLOUDRON_MYSQL
```

Import a dump (see the [MariaDB → MySQL compatibility notes](#4-mariadb--mysql-8-compatibility-notes)
below — a dump straight from the original MariaDB deployment will **not** import cleanly as-is):

```bash
gunzip -c dump.sql.gz | cloudron exec --app <subdomain> -- \
  mysql -h "$CLOUDRON_MYSQL_HOST" -u "$CLOUDRON_MYSQL_USERNAME" -p"$CLOUDRON_MYSQL_PASSWORD" "$CLOUDRON_MYSQL_DATABASE"
```

(Substitute the actual values from step 1 — `cloudron exec` doesn't expand the container's own
env vars in a piped-in shell one-liner like this from outside.)

### 3b. Translation files & uploads

The app's data directory layout under `/app/data` is:

```
/app/data/
  status.json
  metadata/       ← one JSON file per synced Drupal.org project
  translations/
    de/           ← one JSON file per translated project, per language
    fr/
    ...
  uploads/
    avatars/
```

Copy an existing `server/data/{metadata,translations,status.json}` and `server/uploads/` from
the source deployment into `/app/data` on the Cloudron app:

```bash
cloudron push --app <subdomain> path/to/metadata     /app/data/metadata
cloudron push --app <subdomain> path/to/translations /app/data/translations
cloudron push --app <subdomain> path/to/status.json  /app/data/status.json
cloudron push --app <subdomain> path/to/uploads       /app/data/uploads
```

> **⚠️ Known pitfall — directory nesting.** The app creates empty placeholder directories
> (`metadata/`, `translations/`, `uploads/`) on its very first boot (`fs.ensureDirSync(...)` in
> `server/index.js`). If you copy data in *after* the app has started even once — which it will
> have, since the install's health check requires it — and your copy method is a plain directory
> move/copy rather than a proper merge (this bit us during testing: `mv extracted/translations
> /app/data/translations` when `/app/data/translations` already existed as an empty dir silently
> nested it one level deeper as `/app/data/translations/translations` instead of replacing its
> contents), the app will find nothing and behave as if the import never happened. **After
> copying, always verify the structure directly** — e.g. `cloudron exec --app <subdomain> -- ls
> /app/data/translations` should list language codes (`de`, `fr`, ...) directly, not another
> `translations` folder.

After importing both the database and the files, restart the app so it picks everything up:

```bash
cloudron restart --app <subdomain>
```

Verify with:

```bash
curl -s "https://<subdomain>.<your-domain>/api/projects/filter-counts?langcode=de"
```

Counts should be nonzero and match the source deployment.

---

## 4. MariaDB → MySQL 8 compatibility notes

The original deployment runs **MariaDB 11.8**; Cloudron's MySQL addon is **MySQL 8.0.31**. A raw
`mysqldump` from the MariaDB side will fail to import as-is. Two concrete incompatibilities were
found and must be patched in the dump before importing (both already fixed in this repo's own
`server/migrations/*.sql`, which apply automatically on a fresh/empty database — but a **restored
dump** bypasses the migration runner and needs the same fixes applied to the SQL file directly):

1. **Collation** `utf8mb4_uca1400_ai_ci` (MariaDB-only) → replace with `utf8mb4_0900_ai_ci`
   (MySQL 8's native equivalent) or `utf8mb4_unicode_ci` (portable, used by this repo's own
   migrations) throughout the dump.
2. **Generated columns** (`projects.semver_min` / `semver_max`, `STORED GENERATED ALWAYS AS`):
   `mysqldump` includes their computed values directly in `INSERT` statements. MariaDB tolerates
   this; MySQL 8 raises `ER_GENERATED_COLUMN_NOT_ALLOWED` (error 3105) because it strictly
   forbids supplying an explicit value for a generated column. Fix: strip `semver_min`/
   `semver_max` from the `CREATE TABLE projects` statement and from every row's `INSERT` values,
   then re-add both columns via `ALTER TABLE projects ADD COLUMN ... GENERATED ALWAYS AS (...)
   STORED` **after** the data has loaded — MySQL computes the values itself at that point, no
   explicit values needed.

If starting from an **empty** database instead of a dump, none of this applies — the bundled
migrations in `server/migrations/` are already MySQL-8-safe and run automatically on first boot.

---

## 5. Updating an installed app

```bash
cd pb_translation_hub-cloudron   # wherever you cloned it
git pull
cloudron update --app <subdomain>
```

Or, if using a prebuilt image:

```bash
cloudron update --app <subdomain> --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest
```

`cloudron update` always takes an automatic backup snapshot first and performs a rolling restart
— but unlike the docker-compose deployment's rolling restart, **there is only one container**, so
there is a brief downtime window while it rebuilds and restarts (typically under a minute once
the image is built).

---

## 6. Known Cloudron packaging quirks (found during testing)

These cost real debugging time and are worth knowing before you go digging yourself:

- **`iconUrl` (the documented, non-deprecated manifest field) does not work** for CLI-driven
  installs — it's schema-validated but the CLI (`@cloudron` `actions.js`) never actually
  fetches it, on install *or* update. What actually works is the officially-"deprecated"
  `icon` field, pointing at a **local file** in the package (e.g. `"icon": "logo.png"`), which
  the CLI reads and uploads directly as part of the install request.
- **The icon only gets attached on a genuine fresh install**, not on `cloudron update` or
  `cloudron repair` of an already-installed app — even though the CLI code path for `update`
  reads and sends the icon field too. If an app was ever installed without a working icon, the
  only fix found was `cloudron uninstall` + fresh `cloudron install`.
- **`cloudron inspect`'s JSON output doesn't reflect the icon** even when it's actually stored
  and served correctly — verify via the real icon endpoint
  (`https://my.<domain>/api/v1/apps/<app-id>/icon`) instead of trusting `inspect`.
- **`cloudron push` has a path-resolution bug on Windows** — even a trivial local file fails
  with a misleading `bash: line 1: <mangled-path>: No such file or directory`. Workaround: use
  `cloudron exec` piping data in via SSH/docker from a Linux host instead (see §3 above), or run
  the CLI from WSL/Linux rather than native Windows.
- **nginx's default temp and log paths are on the read-only part of the filesystem** —
  `/var/lib/nginx/*` and `/var/log/nginx/*` both need redirecting (to `/run/*` and
  stdout/stderr respectively) or the container crash-loops immediately on start. Already
  handled in this repo's `nginx/app.conf` and `Dockerfile`.
- **Directory permissions can be lost when the build context is uploaded from a Windows/WSL
  host** — `routes/`, `migrations/` etc. arrived in the built image without the execute bit
  (`drw-rw-rw-`), breaking `require()`'s directory traversal with a misleading "Cannot find
  module" error even though the file was physically present. Fixed with a blanket
  `chmod -R a+rX` after all `COPY` steps in the `Dockerfile`.
