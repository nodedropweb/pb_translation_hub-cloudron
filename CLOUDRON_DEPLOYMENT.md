# Cloudron Deployment Guide

*[🇩🇪 Deutsche Version](CLOUDRON_DEPLOYMENT.de.md)*

This document describes how to install, migrate data into, and update PB Translation Hub as a
Cloudron app. It is written for a Drupal e.V. administrator taking over the packaged app for the
first time.

For the original (non-Cloudron) docker-compose deployment, see [DEPLOYMENT.md](DEPLOYMENT.md) —
that document still applies to the [unmodified upstream repo](https://github.com/nodedropweb/pb_translation_hub),
not this Cloudron-packaged variant.

---

## Quickstart: fresh install with the GitHub image

Concrete example: the app should run at `pb.drupal.de`, using the prebuilt GHCR image.

**0. One-time prerequisites**

1. On your **own machine** (not the Cloudron server), install Node.js/npm and the Cloudron CLI:
   ```bash
   npm install -g cloudron
   ```
2. Connect the CLI to the Cloudron instance (opens a browser login flow):
   ```bash
   cloudron login my.drupal.de
   ```

**1. Set up DNS**

A record for `pb.drupal.de` → the Cloudron server's IP (and `my.drupal.de` too, if this is the
first app on the instance). Let it propagate before the next step, or Let's Encrypt issuance
will fail. **If the server has an IPv6 address, a matching AAAA record is also required** — see
the [DNS section below](#dns) for details.

**2. Install**

```bash
cloudron install --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0 --location pb
```

`:latest` also works for a fresh install, but **always pin a specific version tag** (matching the
`version` field in `CloudronManifest.json` at the time you install) rather than relying on
`:latest` — see the note in [Section 5](#5-updating-an-installed-app) about why `:latest` doesn't
reliably drive `cloudron update`.

If `drupal.de` isn't the Cloudron instance's default domain but one of several configured
domains, add `--domain drupal.de`.

After roughly 26 seconds, the (empty) app is reachable at `https://pb.drupal.de`.

**3. Set the app secrets**

```bash
cloudron env set --app pb.drupal.de JWT_SECRET=<your-own-random-value>
```

The app runs fine without a custom `JWT_SECRET`, but it then signs login tokens with a fallback
value visible in the public source — set your own before going live. For Unsplash image search
and help videos, see the full command in the
[App secrets section below](#app-secrets-env-values).

**4. Next step depends on the situation**

- **Fresh/empty install** → done. Open `https://pb.drupal.de`, register the first account,
  trigger a sync from Drupal.org.
- **Migrating existing data** (e.g. moving off the previous docker-compose deployment) → continue
  with [Section 3](#3-post-install-importing-existing-data) below (import the database dump plus
  `translations`/`metadata`/`uploads`), then run `cloudron restart --app pb.drupal.de`.

**5. Updating later**

```bash
cloudron update --app pb.drupal.de --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:<new-version>
```

Use the **new** version's tag (e.g. `0.3.0`), not `:latest` — see the note in
[Section 5](#5-updating-an-installed-app) below.

Everything below is reference material (data import in detail, MariaDB/MySQL compatibility,
known Cloudron quirks) — for a plain fresh install with no data migration, the five steps above
are all you need.

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

### Recommended: install the prebuilt image

A prebuilt image is published to `ghcr.io/nodedropweb/pb_translation_hub-cloudron` after every
release. **Use this path unless you have a specific reason to build from source** — it's the
default we recommend for a production install:

```bash
cloudron login my.<your-domain>
cloudron install --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0 --location <subdomain>
```

No build step, no Flutter SDK download on your Cloudron server — Cloudron just pulls and runs
the image. Measured on a clean install: **~26 seconds**, versus 5–10 minutes building from
source (the Flutter web release build alone takes several minutes). Same result either way —
this is purely about install/update speed.

Pin a real version tag rather than `:latest` — `:latest` is fine for a one-off fresh install, but
`cloudron update` needs the tag string to actually change between runs to know there's something
new to pull (see [Section 5](#5-updating-an-installed-app)), so starting from a version tag keeps
install and update commands consistent.

### Alternative: build from source

Only needed if you're developing the package itself, or `ghcr.io` is unreachable from your
Cloudron server for some reason:

```bash
git clone https://github.com/nodedropweb/pb_translation_hub-cloudron.git
cd pb_translation_hub-cloudron
cloudron login my.<your-domain>
cloudron install --location <subdomain>
```

Cloudron builds the image directly on your Cloudron server — no local Docker required, but
noticeably slower and it ties up CPU on the server while building.

### DNS

Cloudron needs an A record for `<subdomain>.<your-domain>` (and, if this is the first app on a
fresh Cloudron instance, one for `my.<your-domain>` too) pointing at the server's IP **before**
installing — the install step provisions a Let's Encrypt certificate via HTTP validation.

> **IPv6 note:** if the Cloudron server has an IPv6 address, Cloudron detects this automatically
> and additionally requires a matching **AAAA record** for the same subdomain as part of the
> certificate check. If that record is missing, or points at a stale/wrong address, certificate
> issuance or renewal can fail or hang — even though the A record is correct. Two options: add a
> correct AAAA record for the subdomain, or disable IPv6 support in Cloudron's network settings
> to skip the check. If the server has no IPv6 address at all, the check is skipped automatically
> and a plain A record is enough.

### App secrets (.env values)

The docker-compose deployment reads secrets (Unsplash API keys, `JWT_SECRET`, …) from a local
`server/.env` file — deliberately not part of the repo, and not baked into the built image
either (especially now that the GHCR image is public). So a freshly installed Cloudron container
has **none of these values set**, and nothing about that fails loudly — Unsplash image search,
the help videos, and the debug endpoints just stay silently disabled.

Cloudron has a purpose-built mechanism for this — `cloudron env` — which works exactly like the
addon variables (`CLOUDRON_MYSQL_*`) and requires no code change, since the app already reads
`process.env.X` everywhere:

```bash
cloudron env set --app <subdomain> \
  JWT_SECRET=<your-own-random-value> \
  UNSPLASH_ACCESS_KEY=<...> \
  HELP_VIDEO_DE=<youtube-link> \
  HELP_VIDEO_EN=<youtube-link> \
  PB_DEBUG_KEY=<your-own-value>
```

`cloudron env set` restarts the container automatically; the values are active immediately
afterward (verified with `cloudron exec --app <subdomain> -- printenv <NAME>`). Use `cloudron env
list --app <subdomain>` to see what's currently set, and `cloudron env unset` to remove a value.
Any single value can be changed the same way at any time (e.g. a new video link) — that's a plain
config change and needs **no** new image, no rebuild, no `cloudron update`.

**What does each value do?**

| Variable | Purpose | If not set |
|---|---|---|
| `JWT_SECRET` | Signs the login tokens for **every** user (auth). The code only checks the signature, never re-checks the role against the database — anyone who knows the value can build themselves a token with `role: admin`. | Falls back to a value visible in the public source — **set this before the app goes live.** |
| `UNSPLASH_ACCESS_KEY` | Random background image for the theme (`/api/unsplash/random-bg`). | App falls back to a fixed set of background image URLs — cosmetic only, no error. |
| `HELP_VIDEO_DE` / `HELP_VIDEO_EN` | YouTube tutorial video on the help screen, per language. | Video panel is hidden, no error. |
| `PB_DEBUG_KEY` | Unlocks two debug endpoints (preview of not-yet-approved translations, sync inspection) — meant for contributors, not end users. | Both endpoints return 403, safely disabled — optional. |

`UNSPLASH_APP_ID` and `UNSPLASH_SECRET_KEY` (listed in `server/.env.example`) are currently
**not** used anywhere in the code and don't need to be set.

Get the actual values (Unsplash credentials, etc.) — same as the data export in
[Section 3](#3-post-install-importing-existing-data) — from the current maintainer over a private
channel.

---

## 3. Post-install: importing existing data

A fresh install has an **empty** database and no translation files. If you're taking over an
existing deployment (e.g. migrating off the docker-compose setup), import its data once, right
after install.

**Where do I get the data export from?** There's no automated download for this — you get a
ready-made archive (DB dump plus `metadata`/`translations`/`status.json`/`uploads`) from whoever
currently operates the production deployment. Ask the current maintainer; they'll share a current
export with you over a private channel (not linked publicly here). A dump taken straight from a
running MariaDB deployment is usually **not** MySQL-8-compatible as-is — explicitly ask whether
the export has already been adapted for MySQL 8 (see the
[compatibility notes](#4-mariadb--mysql-8-compatibility-notes) below); if so, it saves you the
manual fixes entirely.

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

**Always specify the new version's tag, never `:latest`.** `cloudron update` decides whether
there's anything to do by comparing the image reference you pass against what's currently
installed — if you pass `:latest` both times, the tag string hasn't changed as far as Cloudron
is concerned, and the update can silently no-op even though a newer image was pushed under that
same tag. `:latest` only reliably works for the *first* install of an app, not for updating one
that's already running. Always pull the target version from
[the changelog](CHANGELOG.md)/[releases](https://github.com/nodedropweb/pb_translation_hub-cloudron/releases)
or the `version` field in `CloudronManifest.json` at the commit you're updating to.

```bash
cloudron update --app <subdomain> --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0
```

If you built from source instead:

```bash
cd pb_translation_hub-cloudron   # wherever you cloned it
git pull
cloudron update --app <subdomain>
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

---

## 7. For maintainers: publishing a code change

This section is for whoever maintains the package (not the Drupal e.V. admin running it) — how
to get a code change from a local commit into the `ghcr.io` image that `cloudron update` pulls.

**Prerequisites:** Docker installed wherever you build (your machine or any Linux host — it
doesn't have to be the Cloudron server itself), and a GitHub personal access token with
`write:packages` scope for `docker login ghcr.io`.

**First, bump the version** — `CloudronManifest.json`'s `version` field, following semver (patch
for fixes, minor for features, matching what you'd write in `CHANGELOG.md`). This version number
*is* the image tag you'll push below; it's how `cloudron update` recognizes there's something new
(see the note in [Section 5](#5-updating-an-installed-app) — `:latest` does **not** reliably
trigger an update on an already-installed app, only on a fresh install).

```bash
cd pb_translation_hub-cloudron
# bump "version" in CloudronManifest.json, e.g. 0.1.0 → 0.2.0; add a CHANGELOG.md entry
git add -A && git commit -m "..." && git push origin master   # land the change first

docker build -t ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0 .

docker login ghcr.io -u <your-github-username>   # only needed once per machine
docker push ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0

# Optional: also move the floating `latest` tag, purely for the convenience of a *fresh* install
# command that doesn't need to specify a version. Never rely on this alone for updates.
docker tag ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0 ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest
docker push ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest
```

The Flutter web build step inside `docker build` takes several minutes — this is the same cost
described in [Section 2](#2-installing-the-app) for a from-source install, just done once here
instead of on every admin's Cloudron server.

Once the push finishes, anyone running `cloudron update --app <subdomain> --image
ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.2.0` (see [Section 5](#5-updating-an-installed-app))
picks up the new image, using the **exact version tag you just pushed** — not `:latest`.
