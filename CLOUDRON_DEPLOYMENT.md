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
cloudron install --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.4.21 --location pb
```

`:latest` also works for a fresh install, but **always pin a specific version tag** (matching the
`version` field in `CloudronManifest.json` at the time you install) rather than relying on
`:latest` — see the note in [Section 5](#5-updating-an-installed-app) about why `:latest` doesn't
reliably drive `cloudron update`.

If `drupal.de` isn't the Cloudron instance's default domain but one of several configured
domains, add `--domain drupal.de`.

After roughly 26 seconds, the (empty) app is reachable at `https://pb.drupal.de`.

**3. Find (or set) the first admin account**

There's no in-app path to this on a fresh install: the registration form only creates
translator/reviewer accounts, and every new account starts `is_active=0`, pending approval by an
admin — who doesn't exist yet on a brand-new instance. The app handles this itself on first boot,
the same way it handles a missing `JWT_SECRET` — no action required, but there are two outcomes
depending on whether you configured it:

- **You didn't set anything** → the app generated a random password for the username `admin` and
  printed it once to the startup log:
  ```bash
  cloudron logs --app pb.drupal.de | grep -A3 "generated an admin account"
  ```
  It's also saved at `/app/data/.admin_credentials` on the app if you missed the log line:
  ```bash
  cloudron exec --app pb.drupal.de -- cat /app/data/.admin_credentials
  ```
  Log in with those and change the password from the app.
- **You want to choose your own values** — set these before the first boot (or any time before an
  admin account exists):
  ```bash
  cloudron env set --app pb.drupal.de ADMIN_USERNAME=<username> ADMIN_PASSWORD=<password>
  ```

Either way this only ever fires once — as soon as an admin account exists, nothing here runs again
on a later boot, generated password or not, so it can't reset anyone's password out from under
them.

**4. Set the remaining app secrets (optional)**

The app self-generates a random `JWT_SECRET` on first boot and persists it under its data
directory if you don't configure one — no manual step required for a working install. Set your
own only if you specifically need a portable, known value (e.g. to share one secret across
multiple app instances):

```bash
cloudron env set --app pb.drupal.de JWT_SECRET=<your-own-random-value>
```

For Unsplash image search and help videos, see the full command in the
[App secrets section below](#app-secrets-env-values).

**5. Next step depends on the situation**

- **Fresh/empty install** → done. Open `https://pb.drupal.de`, log in with the admin account from
  step 3, trigger a sync from Drupal.org.
- **Migrating existing data** (e.g. moving off the previous docker-compose deployment) → continue
  with [Section 3](#3-post-install-importing-existing-data) below (import the database dump plus
  `translations`/`metadata`/`uploads`), then run `cloudron restart --app pb.drupal.de`.

**6. Updating later**

```bash
cloudron update --app pb.drupal.de --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:<new-version>
```

Use the **new** version's tag (e.g. `0.4.22`), not `:latest` — see the note in
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
cloudron install --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.4.21 --location <subdomain>
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
  ADMIN_USERNAME=<username> \
  ADMIN_PASSWORD=<password> \
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
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | Bootstraps the first admin account on startup if no admin exists yet — there's no in-app path to create one (registration only creates translator/reviewer accounts, and they start pending approval by an admin who doesn't exist on a fresh install). Only acts once; ignored on every subsequent boot once an admin exists, so it's safe to leave set. | App generates username `admin` and a random password, prints it once to the startup log, and saves it to `/app/data/.admin_credentials` — see [step 3 of the Quickstart](#quickstart-fresh-install-with-the-github-image). Not a silent failure like the old behavior; you always end up with a working login. |
| `ADMIN_EMAIL` | Email for the bootstrapped admin account (optional, the column allows `NULL`). | Admin account has no email set. |
| `JWT_SECRET` | Signs the login tokens for **every** user (auth). The code only checks the signature, never re-checks the role against the database — anyone who knows the value can build themselves a token with `role: admin`. | App self-generates a random value on first boot and persists it under the data directory — no action needed. Set your own only for a known, portable value (e.g. shared across instances). |
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

**Where do I get the data export from?** The main repo (`pb_translation_hub`) ships
`export_for_cloudron.sh`, which pulls a fresh dump straight from the live MariaDB deployment and
already applies both fixes from the [compatibility notes](#4-mariadb--mysql-8-compatibility-notes)
below (collation rewrite + generated-column strip/re-add) — no manual SQL surgery needed:

```bash
# from within pb_translation_hub/
./export_for_cloudron.sh                       # writes exports/pb_hub_cloudron_<stamp>.sql.gz
./export_for_cloudron.sh --import-to <subdomain> [--yes]   # also imports it directly (see 3a)
```

It only touches translation/DB data — `metadata`/`status.json`/`uploads` (section 3b) still need
a manual copy. If someone hands you an export produced any other way (e.g. a raw `mysqldump`),
explicitly ask whether it's already MySQL-8-adapted; if not, the fixes in section 4 apply.

### 3a. Database

**Recommended — via the script:** `./export_for_cloudron.sh --import-to <subdomain>` runs a
`cloudron backup create` for the target app first, then pipes the transformed dump straight into
its MySQL addon. Requires `--yes` to skip the confirmation prompt in non-interactive use; the
default interactive prompt is the safety net, so don't add `--yes` unless you mean it.

**Manual alternative:** get the MySQL addon credentials Cloudron injected into the container:

```bash
cloudron exec --app <subdomain> -- env | grep CLOUDRON_MYSQL
```

Import an already-transformed dump (see the
[MariaDB → MySQL compatibility notes](#4-mariadb--mysql-8-compatibility-notes) below — a dump
straight from the original MariaDB deployment will **not** import cleanly as-is):

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
`mysqldump` from the MariaDB side will fail to import as-is. `pb_translation_hub/export_for_cloudron.sh`
automates both fixes below (verified end-to-end against a real MySQL 8 container — full data set,
all tables, apostrophes/multi-byte content intact); this section documents what it does, for anyone
patching a dump by hand instead:

1. **Collation** `utf8mb4_uca1400_ai_ci` (MariaDB-only) → replaced with `utf8mb4_unicode_ci`
   (portable, already used by this repo's own migrations and by `glossary_terms`, which avoids
   mixed-collation join errors against tables created via the normal migration path) throughout
   the dump. `utf8mb4_0900_ai_ci` (MySQL 8's native default) also works if you're patching by hand.
2. **Generated columns** (`projects.semver_min` / `semver_max`, `STORED GENERATED ALWAYS AS`):
   `mysqldump`/`mariadb-dump` includes their computed values directly in `INSERT` statements.
   MariaDB tolerates this; MySQL 8 raises `ER_GENERATED_COLUMN_NOT_ALLOWED` (error 3105) because it
   strictly forbids supplying an explicit value for a generated column. Fix: create `projects`
   *without* `semver_min`/`semver_max`, load its data via `INSERT`s that name only the real
   columns, then add both columns via `ALTER TABLE projects ADD COLUMN ... GENERATED ALWAYS AS
   (...) STORED` **after** the data has loaded — MySQL computes the values itself at that point.
   (Text-editing a `mysqldump`-produced multi-row `INSERT` to strip trailing fields is fragile
   against JSON content containing commas/quotes; the script instead regenerates `projects`' rows
   itself via `SELECT ... QUOTE(...)`, sidestepping that entirely.)
   - **Gotcha if you build this yourself:** generating those `INSERT`s via `mysql -B` (batch mode)
     double-escapes them — batch mode applies its own TSV-style backslash escaping on top of
     `QUOTE()`'s already-correct SQL escaping, corrupting any value containing a literal backslash
     (e.g. JSON text with embedded `\r\n`) and breaking on import with `Unknown command '\\'`.
     Add `-r`/`--raw` to suppress batch mode's re-escaping.

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
cloudron update --app <subdomain> --image ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.4.21
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
# bump "version" in CloudronManifest.json, e.g. 0.4.21 → 0.4.22; add a CHANGELOG.md entry
git add -A && git commit -m "..." && git push origin master   # land the change first

docker build -t ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.4.22 .

docker login ghcr.io -u <your-github-username>   # only needed once per machine
docker push ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.4.22

# Optional: also move the floating `latest` tag, purely for the convenience of a *fresh* install
# command that doesn't need to specify a version. Never rely on this alone for updates.
docker tag ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.4.22 ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest
docker push ghcr.io/nodedropweb/pb_translation_hub-cloudron:latest
```

The Flutter web build step inside `docker build` takes several minutes — this is the same cost
described in [Section 2](#2-installing-the-app) for a from-source install, just done once here
instead of on every admin's Cloudron server.

### 7a. Baking a data seed into the image (optional)

A fresh install normally has an empty database — see [Section 3](#3-post-install-importing-existing-data)
for the manual post-install import. As an alternative, the image can seed itself automatically on
first boot, so a fresh install already has the full translation corpus without any manual step:

```bash
# from pb_translation_hub/ (the main repo), before docker build:
./export_for_cloudron.sh --seed ../pb_translation_hub-cloudron/server/seed/db_seed.sql.gz
```

Then `docker build` as above — `server/seed/` is inside the build context and gets baked into the
image automatically (no separate `COPY` needed, it's nested under `server/`). If the file isn't
present, the build still works fine; seeding is simply a no-op at runtime in that case.

The seed is **content only** — `projects`, `translations`, `glossary_terms`, `priority_projects`,
`ignored_projects`, `sync_events`, `site_settings`. It deliberately excludes `users` (so a seeded
instance still gets its own fresh admin account via normal registration, not your live password
hash) and `schema_migrations` (so the migration runner's own bookkeeping is untouched). Translation
JSON files aren't part of the seed either — the existing startup logic
(`ensureTranslationFilesFromDb()`) already regenerates them from the `translations` table whenever
the translations directory is empty, so nothing extra is needed there.

Seeding itself only runs when explicitly requested — set `SEED_ON_FIRST_BOOT=true` on the app
(Cloudron dashboard → app → Environment Variables, or `cloudron env set`). It checks whether
`projects` is still empty before doing anything, so it's safe to leave the variable set
permanently: it never touches an already-populated database, on any later restart or update.

Once the push finishes, anyone running `cloudron update --app <subdomain> --image
ghcr.io/nodedropweb/pb_translation_hub-cloudron:0.4.22` (see [Section 5](#5-updating-an-installed-app))
picks up the new image, using the **exact version tag you just pushed** — not `:latest`.
