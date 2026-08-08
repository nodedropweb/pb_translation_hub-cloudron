# Database Schema — PB Translation Hub

*[🇩🇪 Deutsche Version](DATABASE.de.md)*

MariaDB 11.8 (docker-compose) or MySQL 8.0.31 (Cloudron, see [CLOUDRON_DEPLOYMENT.md](CLOUDRON_DEPLOYMENT.md)) · Database: `pb_translation_hub` · User: `pb_hub`

Schema and queries below are identical for both engines — the concrete differences (collation,
generated columns during dump import) are documented in
[CLOUDRON_DEPLOYMENT.md, Section 4](CLOUDRON_DEPLOYMENT.md#4-mariadb--mysql-8-compatibility-notes).

---

## Table Overview

| Table | Purpose |
|---|---|
| `projects` | Mirrored module metadata from Drupal.org |
| `translations` | Translated content (multi-language) |
| `priority_projects` | Curated list of "important" modules. Since the Cloudron migration, the priority filter itself no longer means "on the list + untranslated" but "on the list + not yet Drupal-12-compatible" (`semver_max < 12000000`) |
| `ignored_projects` | Modules permanently hidden from queues |
| `site_settings` | Global app settings (key-value) |
| `users` | User accounts with roles, API keys, language assignment |
| `glossary_terms` | Terminology for CKEditor glossary highlighting |
| `sync_events` | Historical log of sync events (for the analytics dashboard) |
| `schema_migrations` | Versioning log of applied DB migrations |

---

## Table: `projects`

Local mirror of the Drupal.org JSON:API metadata.

| Field | Type | Null | Description |
|---|---|---|---|
| `machine_name` | VARCHAR(255) | NO PK | Unique Drupal machine name (e.g. `ctools`) |
| `title` | VARCHAR(255) | YES | Human-readable module name |
| `data` | LONGTEXT | YES | Full JSON:API object (categories, maintainers, images, etc.) |
| `updated_at` | TIMESTAMP | NO | Automatically updated on every sync |

---

## Table: `translations`

All localized content. Primary key is `(machine_name, langcode)`.

| Field | Type | Null | Description |
|---|---|---|---|
| `machine_name` | VARCHAR(255) | NO PK | FK → `projects.machine_name` |
| `langcode` | VARCHAR(10) | NO PK | Language code (e.g. `de`, `fr`, `ja`) |
| `title` | VARCHAR(255) | YES | Translated module title |
| `summary` | TEXT | YES | Short description (HTML) |
| `body` | LONGTEXT | YES | Full description (HTML) |
| `screenshot_alts` | TEXT | YES | JSON: UUID → alt-text mapping |
| `source_hash` | VARCHAR(32) | YES | MD5 of the English source text at translation time |
| `is_reviewed` | TINYINT(1) | NO (0) | 0 = in review queue · 1 = approved |
| `reviewed_by` | VARCHAR(50) | YES | Username of the reviewer |
| `updated_at` | TIMESTAMP | NO | Last save time |

**Stale detection:** If the English source text in `projects` changes, `source_hash` no longer matches the current MD5 → the module shows as "stale" on the dashboard.

---

## Table: `priority_projects`

Defines priority lists for the translation workflow.

| Field | Type | Description |
|---|---|---|
| `machine_name` | VARCHAR(255) PK | Module name |
| `list_name` | VARCHAR(50) PK | List identifier (default: `drupal11` — historical name, no longer read by the filter logic; list membership itself is decided solely by `machine_name`) |

---

## Table: `ignored_projects`

Modules permanently hidden from review and missing-translation lists.

| Field | Type | Description |
|---|---|---|
| `machine_name` | VARCHAR(255) PK | Module name |
| `langcode` | VARCHAR(10) PK | Language code |

---

## Table: `site_settings`

Key-value store for global settings.

| Field | Type | Description |
|---|---|---|
| `setting_key` | VARCHAR(100) PK | Setting name |
| `setting_value` | TEXT | Value |

**Known keys:**

| Key | Values | Meaning |
|---|---|---|
| `registration_enabled` | `'1'` / `'0'` | Registration form globally on/off |

---

## Table: `users`

User accounts with roles, languages, and API keys.

| Field | Type | Null | Description |
|---|---|---|---|
| `id` | INT AUTO_INCREMENT | NO PK | Internal ID |
| `username` | VARCHAR(50) | NO UNIQUE | Login name |
| `password` | VARCHAR(255) | NO | bcrypt hash |
| `name` | VARCHAR(100) | YES | Display name |
| `email` | VARCHAR(100) | YES | Email address |
| `target_languages` | LONGTEXT | YES | JSON array of target languages (e.g. `["de","fr"]`) |
| `user_type` | ENUM('translator','reviewer') | NO ('translator') | Role: translators have no review-queue access |
| `avatar_url` | VARCHAR(255) | YES | Relative path under `/uploads/avatars/` |
| `created_at` | TIMESTAMP | YES | Registration time |
| `role` | VARCHAR(20) | YES ('user') | `'admin'` or `'user'` |
| `is_active` | TINYINT(4) | YES (0) | 0 = pending activation · 1 = active |
| `google_ai_key` | VARCHAR(255) | YES | Personal Google Gemini API key |
| `ai_batch_limit` | INT(11) | YES (5) | Max modules per AI bulk translation |
| `ai_prompt` | TEXT | YES | Custom AI translation prompt |
| `deepl_api_key` | VARCHAR(255) | YES | Personal DeepL API key |
| `last_reviewed_project` | VARCHAR(255) | YES | Most recently reviewed module |

**Access logic:**

| `role` | `user_type` | Review Queue | Admin Panel |
|---|---|---|---|
| `admin` | – | ✓ | ✓ |
| `user` | `reviewer` | ✓ | ✗ |
| `user` | `translator` | ✗ | ✗ |

---

## Table: `glossary_terms`

Terminology per target language. The CKEditor glossary plugin reads this table when an editor opens and highlights all matches in the editing area.

| Field | Type | Null | Description |
|---|---|---|---|
| `id` | INT AUTO_INCREMENT | NO PK | Internal ID |
| `lang_code` | VARCHAR(10) | NO | Target language (e.g. `de`, `fr`) |
| `source_word` | VARCHAR(255) | NO | Base form of the term to detect (e.g. `Inhalt`) |
| `word_forms` | TEXT | YES | Comma-separated inflected forms (e.g. `Inhalte,Inhalts,Inhalten`). All forms including `source_word` are matched via regex alternation. |
| `preferred_word` | VARCHAR(255) | NO | Preferred translation / recommended term |
| `explanation` | TEXT | YES | Optional explanatory text (shown in a tooltip) |
| `created_by` | INT | YES | FK → `users.id` |
| `created_at` | TIMESTAMP | NO | Creation time |

**Indexes:** `lang_code`, `source_word`

**API:** `GET/POST/PUT/DELETE /api/glossary` — write access requires role `reviewer` or `admin`. GET always returns `word_forms` as a JSON array (backend normalizes from comma-string to array).

---

## Table: `sync_events`

Logs what changed about a module during each sync — the basis for the weekly trends on the analytics dashboard. Populated by the `recordSyncEvents()` helper in `server/index.js` (before every `projects` upsert, in all sync paths).

| Field | Type | Null | Description |
|---|---|---|---|
| `id` | INT AUTO_INCREMENT | NO PK | Internal ID |
| `machine_name` | VARCHAR(255) | NO | Module name |
| `event_type` | ENUM | NO | `new_module` · `description_changed` · `stale` |
| `langcode` | VARCHAR(10) | YES | Only set for `stale` (affected language) |
| `event_date` | DATE | NO | Day of the event (basis for weekly bucketing) |
| `created_at` | TIMESTAMP | NO | Insert time |

**Unique key** `(machine_name, event_type, langcode, event_date)` + `INSERT IGNORE` prevent duplicate events per day. On the dashboard, `new_module` + `description_changed` are counted together as "module with new project description".

**Backfill:** `node server/scripts/backfill_sync_events.js` reconstructs the history once, approximately, from `projects.changed` (ISO 8601 string). Idempotent. True "new vs. changed" distinction only from the first new sync onward.

**API:** `GET /api/dashboard/weekly?type=new_description|stale&weeks=12&langcode=de` returns `{ week_start, count, modules[] }` per week. Compatibility per Drupal version + translation need is still served by `/api/projects/filter-counts`.

---

## Table: `schema_migrations`

Logs all executed DB migrations. Managed by `db_migrate.js`.

| Field | Type | Description |
|---|---|---|
| `version` | VARCHAR(20) PK | Numeric version (e.g. `003`) |
| `filename` | VARCHAR(255) | Migration filename |
| `applied_at` | TIMESTAMP | Execution time |

---

## Migration System

Schema changes are managed as numbered SQL files in `server/migrations/`:

```
server/migrations/
  001_initial_schema.sql              — base schema (all core tables)
  002_users_deepl_key.sql             — deepl_api_key column
  003_users_registration_fields.sql   — target_languages + user_type
  004_users_requested_role.sql        — requested_role column (registration wish)
  005_create_glossary_terms.sql       — glossary_terms table + indexes
  006_suggestion_type_deepl.sql       — ENUM extension for DeepL suggestions + translation_suggestions CREATE (backfilled, see the migration itself)
  007_glossary_word_forms.sql         — word_forms TEXT column on glossary_terms
  008_semver_columns.sql              — semver_min/max generated columns + index
  009_sync_events.sql                 — sync_events table (dashboard history)
```

### Adding a new migration

```bash
# Choose the next available number and create the file:
cat > server/migrations/010_my_change.sql << 'EOF'
-- Migration 010: Description
ALTER TABLE translations ADD COLUMN reviewer_note TEXT DEFAULT NULL;
EOF
```

**Rules:**
- Filename always `NNN_description.sql` (zero-padded, snake_case)
- Only additive changes: `ADD COLUMN` (**without** `IF NOT EXISTS` — MariaDB-only, not supported by MySQL 8/Cloudron), `CREATE TABLE IF NOT EXISTS`
- No `DROP` or `RENAME` operations without explicit coordination
- Each migration runs inside a **transaction** — rolled back on failure

### Automatic execution

On server start (`node index.js` or Docker container start), `db_migrate.js` automatically calls all pending migrations:

```
[Migration] ✓ 003_users_registration_fields.sql applied
[Migration] Database is up to date — no pending migrations.
```

If a migration fails, the server aborts with `process.exit(1)` — no silent ignoring.

### Deploying a migration to the production server

> **On Cloudron** this works differently — no `deploy.sh`, no separate containers. See
> [CLOUDRON_DEPLOYMENT.md, Section 5](CLOUDRON_DEPLOYMENT.md#5-updating-an-installed-app)
> (`cloudron update`). Migrations run automatically on server start there too.

```bash
# Recommended: back up the DB before schema changes
./deploy.sh --db-backup

# Or explicitly with the backup flag
./deploy.sh --db-backup
```

The deploy script performs a **rolling restart**:
1. The DB container stays online the whole time
2. The server container is rebuilt and started
3. Migrations run automatically on server start
4. The client container is rebuilt afterward

---

## Useful SQL Queries

### Missing translations for a language

```sql
SELECT p.machine_name, p.title
FROM projects p
LEFT JOIN translations t ON p.machine_name = t.machine_name AND t.langcode = 'de'
WHERE t.machine_name IS NULL;
```

### Stale translations (source_hash no longer matches)

```sql
SELECT t.machine_name, t.langcode, t.source_hash
FROM translations t
JOIN projects p ON t.machine_name = p.machine_name
WHERE t.source_hash != MD5(p.data);
```

### Check migration status

```sql
SELECT * FROM schema_migrations ORDER BY version;
```

### Active users by type

```sql
SELECT username, email, user_type,
       JSON_UNQUOTE(target_languages) AS languages
FROM users
WHERE is_active = 1
ORDER BY user_type, username;
```

---

## Backup & Restore

> **On Cloudron:** `backup.sh`/`restore.sh` assume docker-compose containers, which don't exist
> there. Cloudron automatically backs up the app on every `cloudron update` (snapshot). For
> DB import/export, see instead
> [CLOUDRON_DEPLOYMENT.md, Section 3a](CLOUDRON_DEPLOYMENT.md#3a-database) (`cloudron exec`
> instead of `docker exec`).

### Full backup (recommended): `backup.sh` / `restore.sh`

Backs up **both** the complete DB **and** the `data/translations/` tree into a **single**
archive. Important: **category names** (`_categories.json`) only exist as files and are missing
from a plain DB dump.

```bash
./backup.sh             # Live server (drupaltutorials.de) via SSH
./backup.sh --local     # local instance (mysqldump on 127.0.0.1)
# → backups/pb_hub_backup_<YYYYMMDD_HHMMSS>.tar.gz  (db.sql.gz + translations.tar.gz + manifest.txt)

./restore.sh <archive.tar.gz> --target local|remote --yes
# remote afterward: ./deploy.sh --no-build  (server restart → migrations run)
```

### DB-only backup (quick save, e.g. before migrations)

`deploy.sh --db-backup` creates a plain DB dump on the server before the deploy, under
`~/backups/pb_db_backup_<stamp>.sql.gz` (password from `server/.env`, fallback `drupal`). Handy
as a pre-migration safety net.

> Note: This path only backs up **the DB**, not the category/translation files
> (`data/translations/`, including `_categories.json`). Use `backup.sh` for a fully restorable
> backup. `backup.sh` uses the same password resolution as `deploy.sh`.

### Create a backup (production)

```bash
# Manually on the server
docker exec pb_translation_hub-db-1 \
  mysqldump -u pb_hub -p'PASSWORD' pb_translation_hub \
  | gzip > ~/backups/pb_db_$(date +%Y%m%d_%H%M%S).sql.gz

# Via deploy.sh
./deploy.sh --db-backup
```

### Restore

```bash
# Import the dump
gunzip < backup.sql.gz | docker exec -i pb_translation_hub-db-1 \
  mysql -u pb_hub -p'PASSWORD' pb_translation_hub
```

### Initial setup on a new server (empty volume)

On the first `docker compose up`, MariaDB automatically imports `server/data/db_export.sql.gz`
(via `docker-entrypoint-initdb.d`). Migrations then run on top of that to bring it to the
current state.

> **Important:** `db_export.sql.gz` contains the schema as of the export time. Migrations bring
> it up to date. Both together guarantee a consistent database on any new server.
