const express = require('express');
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const AdmZip = require('adm-zip');

// Content tables included in a seed export — mirrors export_for_cloudron.sh
// --seed / seedFromBundledDataIfRequested() in index.js. Deliberately excludes
// `users` and `schema_migrations`: a seeded instance gets its own fresh admin
// account via normal registration, and migration bookkeeping stays untouched.
//
// Every table here except `glossary_terms` has a real natural primary/unique
// key (checked against server/migrations/*.sql), so the generated INSERTs use
// ON DUPLICATE KEY UPDATE — the same export works both to seed an empty DB
// (first boot) and to re-import into an already-populated live instance
// (admin-triggered, via POST /upload-backup), upserting instead of crashing
// on the first duplicate key. `glossary_terms` only has an auto-increment
// `id` with no other unique constraint, so it stays a plain INSERT — a repeat
// import will duplicate glossary entries rather than update them. Fixing that
// would need a real UNIQUE(lang_code, source_word) constraint added via a new
// migration, which isn't safe to add blind against unknown live data (could
// already contain duplicates that the migration would then fail on) — left
// as a known limitation rather than risking a migration that breaks on
// deploy.
const SEED_TABLES = [
  'projects', 'translations', 'glossary_terms',
  'priority_projects', 'ignored_projects', 'sync_events', 'site_settings',
];
const NO_UPSERT_TABLES = new Set(['glossary_terms']);

// Pending exports built by GET /admin/export-seed, waiting to be picked up by
// GET /admin/export-seed/download/:token. token -> { filePath, filename, expiresAt }.
// In-memory is fine here: this app runs as a single process/container (see the
// 0.4.1 changelog entry on the export OOM fix), so there's no multi-instance
// case where a token minted on one node wouldn't be found on another.
const pendingExports = new Map();
const EXPORT_TTL_MS = 5 * 60 * 1000;

function cleanupExpiredExports() {
  const now = Date.now();
  for (const [token, entry] of pendingExports) {
    if (entry.expiresAt < now) {
      fs.unlink(entry.filePath, () => {});
      pendingExports.delete(token);
    }
  }
}

module.exports = (ctx) => {
  const { db, authenticateToken, isAdmin, DATA_DIR, TRANSLATIONS_DIR } = ctx;
  const router = express.Router();
  const EXPORT_DIR = path.join(DATA_DIR, 'exports');
  const CATEGORIES_FILENAME = '_categories.json'; // keep in sync with routes/categories.js's CAT_FILENAME

  // Get active (approved) users — excludes the requesting admin
  router.get('/admin/users/active', authenticateToken, isAdmin, async (req, res) => {
    try {
      const [rows] = await db.execute(
        'SELECT id, username, name, email, user_type, target_languages, avatar_url, created_at FROM users WHERE is_active = 1 AND role != "admin" ORDER BY username'
      );
      const users = rows.map(u => ({
        ...u,
        target_languages: u.target_languages ? (() => { try { return JSON.parse(u.target_languages); } catch { return []; } })() : []
      }));
      res.json(users);
    } catch (err) {
      res.status(500).json({ error: 'Failed to fetch active users' });
    }
  });

  // Deactivate (lock) a user without deleting
  router.patch('/admin/users/:id/deactivate', authenticateToken, isAdmin, async (req, res) => {
    try {
      await db.execute('UPDATE users SET is_active = 0 WHERE id = ? AND role != "admin"', [req.params.id]);
      res.json({ success: true });
    } catch (err) {
      res.status(500).json({ error: 'Deactivation failed' });
    }
  });

  // Get pending users
  router.get('/admin/users/pending', authenticateToken, isAdmin, async (req, res) => {
    try {
      const [rows] = await db.execute('SELECT id, username, name, email, user_type, requested_role, target_languages, avatar_url, created_at FROM users WHERE is_active = 0');
      const users = rows.map(u => ({
        ...u,
        target_languages: u.target_languages ? (() => { try { return JSON.parse(u.target_languages); } catch { return []; } })() : []
      }));
      res.json(users);
    } catch (err) {
      res.status(500).json({ error: 'Failed to fetch pending users' });
    }
  });

  // Approve a user — defaults to 'translator' regardless of requested role.
  // Admin can explicitly pass user_type to override.
  router.post('/admin/users/:id/approve', authenticateToken, isAdmin, async (req, res) => {
    try {
      const { user_type } = req.body;
      const grantedType = (user_type && ['translator', 'reviewer'].includes(user_type))
        ? user_type
        : 'translator';
      await db.execute('UPDATE users SET is_active = 1, user_type = ? WHERE id = ?', [grantedType, req.params.id]);
      res.json({ success: true });
    } catch (err) {
      res.status(500).json({ error: 'Approval failed' });
    }
  });

  // Delete a user
  router.delete('/admin/users/:id', authenticateToken, isAdmin, async (req, res) => {
    try {
      await db.execute('DELETE FROM users WHERE id = ? AND role != "admin"', [req.params.id]);
      res.json({ success: true });
    } catch (err) {
      res.status(500).json({ error: 'Deletion failed' });
    }
  });

  // Get settings
  router.get('/admin/settings', authenticateToken, isAdmin, async (req, res) => {
    try {
      const [rows] = await db.execute('SELECT * FROM site_settings');
      const settings = {};
      rows.forEach(r => settings[r.setting_key] = r.setting_value);
      res.json(settings);
    } catch (err) {
      res.status(500).json({ error: 'Failed to fetch settings' });
    }
  });

  // Save settings
  router.put('/admin/settings', authenticateToken, isAdmin, async (req, res) => {
    const { registration_enabled } = req.body;
    try {
      await db.execute(
        'INSERT INTO site_settings (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = ?',
        ['registration_enabled', registration_enabled, registration_enabled]
      );
      res.json({ success: true });
    } catch (err) {
      res.status(500).json({ error: 'Failed to update settings' });
    }
  });

  // Export a content snapshot of the current instance — a zip bundling:
  //   - db_seed.sql.gz: gzipped SQL dump of SEED_TABLES, same statement
  //     format the first-boot seed importer expects
  //     (server/index.js: seedFromBundledDataIfRequested() /
  //     importSqlDump()), upsert-safe (see NO_UPSERT_TABLES above) so the
  //     same file works both to seed an empty DB and to re-import into an
  //     already-populated live instance.
  //   - translations/<langcode>/_categories.json for every language that has
  //     one: module-category name translations. These live ONLY on disk —
  //     there's no DB table backing them (see routes/categories.js) — so a
  //     DB-only export used to silently drop them entirely. Discovered
  //     2026-08-23 while testing this feature: with ~116 target languages,
  //     re-baking a fresh image for every content change isn't workable, so
  //     this export/import round-trip needs to carry everything, not just
  //     what happens to live in the database.
  //
  // Built entirely from the already-open mysql2 pool (no mariadb-dump/
  // mysqldump binary involved), so it works regardless of what client tools a
  // given deployment target ships.
  //
  // `projects` alone holds the entire Drupal.org catalog (tens of thousands
  // of rows with a JSON blob each) — an earlier version that buffered every
  // INSERT line into one big array, joined it into a string, then gzipped
  // that in one shot, OOM-crashed the Node process on a real instance
  // (heap blew past its container limit holding several full copies of the
  // same data at once). This streams rows straight from MySQL into a gzip
  // stream, still with constant memory — into a temp file on disk, which
  // then gets bundled into the final zip alongside the category files.
  //
  // Two-phase on purpose: building the dump takes a while (tens of MB), and
  // an earlier version that streamed it directly as the response of this
  // same authenticated request had the client hold the whole thing in memory
  // as bytes and forced a browser "Save As" dialog whose window of valid
  // user-activation can expire during a multi-second transfer. This endpoint
  // now only builds the file and hands back a short-lived, single-use
  // download token; the client then does a plain, unauthenticated navigation
  // to GET /admin/export-seed/download/:token, which is what actually
  // triggers the browser's native download — instant, no bytes buffered in
  // the app, no stale-gesture risk.
  router.get('/admin/export-seed', authenticateToken, isAdmin, async (req, res) => {
    cleanupExpiredExports();
    await fs.promises.mkdir(EXPORT_DIR, { recursive: true });

    const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const filename = `pb_hub_seed_${stamp}.zip`;
    const sqlPath = path.join(EXPORT_DIR, `${crypto.randomUUID()}.sql.gz`);
    const zipPath = path.join(EXPORT_DIR, `${crypto.randomUUID()}.zip`);

    const gzip = zlib.createGzip();
    const fileStream = fs.createWriteStream(sqlPath);
    gzip.pipe(fileStream);

    const writeAndDrain = (chunk) => {
      if (gzip.write(chunk)) return Promise.resolve();
      return new Promise((resolve) => gzip.once('drain', resolve));
    };

    let conn;
    try {
      await writeAndDrain('SET NAMES utf8mb4;\n');

      conn = await db.getConnection();
      for (const table of SEED_TABLES) {
        const rowStream = conn.connection.query(`SELECT * FROM \`${table}\``).stream();
        for await (const row of rowStream) {
          const columns = Object.keys(row);
          const values = columns.map((col) => db.escape(row[col]));
          const columnList = columns.map((c) => `\`${c}\``).join(',');
          let stmt = `INSERT INTO \`${table}\` (${columnList}) VALUES (${values.join(',')})`;
          if (!NO_UPSERT_TABLES.has(table)) {
            stmt += ` ON DUPLICATE KEY UPDATE ${columns.map((c) => `\`${c}\`=VALUES(\`${c}\`)`).join(',')}`;
          }
          await writeAndDrain(`${stmt};\n`);
        }
      }

      gzip.end();
      await new Promise((resolve, reject) => {
        fileStream.on('finish', resolve);
        fileStream.on('error', reject);
      });

      const zip = new AdmZip();
      zip.addLocalFile(sqlPath, '', 'db_seed.sql.gz');

      const langcodes = await fs.promises.readdir(TRANSLATIONS_DIR).catch(() => []);
      for (const lc of langcodes) {
        const catPath = path.join(TRANSLATIONS_DIR, lc, CATEGORIES_FILENAME);
        if (await fs.promises.stat(catPath).then(() => true).catch(() => false)) {
          zip.addLocalFile(catPath, `translations/${lc}`, CATEGORIES_FILENAME);
        }
      }
      zip.writeZip(zipPath);
      await fs.promises.unlink(sqlPath);

      const token = crypto.randomBytes(32).toString('hex');
      pendingExports.set(token, { filePath: zipPath, filename, expiresAt: Date.now() + EXPORT_TTL_MS });
      res.json({ token, filename });
    } catch (err) {
      console.error('[Export-Seed]', err.message);
      gzip.destroy();
      fileStream.destroy();
      fs.unlink(sqlPath, () => {});
      fs.unlink(zipPath, () => {});
      res.status(500).json({ error: 'Export failed' });
    } finally {
      if (conn) conn.release();
    }
  });

  // Actual download step for the export built above. Deliberately not behind
  // authenticateToken: it's reached via a plain browser navigation/anchor
  // click (so the native download UI fires), which can't carry the app's
  // Bearer token. Security instead comes from the token itself — 256 bits of
  // crypto.randomBytes, single-use (deleted from the map before streaming
  // starts), and expiring after EXPORT_TTL_MS regardless of use.
  router.get('/admin/export-seed/download/:token', (req, res) => {
    const entry = pendingExports.get(req.params.token);
    if (!entry || entry.expiresAt < Date.now()) {
      pendingExports.delete(req.params.token);
      return res.status(404).json({ error: 'Download link expired or invalid — trigger a new export' });
    }
    pendingExports.delete(req.params.token);

    res.set({
      'Content-Type': 'application/zip',
      'Content-Disposition': `attachment; filename="${entry.filename}"`,
    });

    const stream = fs.createReadStream(entry.filePath);
    stream.pipe(res);
    // Clean up the generated file from disk as soon as the download finishes
    // (or the client aborts it) — nothing about this export is meant to
    // outlive the single download it was built for.
    const cleanup = () => fs.unlink(entry.filePath, () => {});
    stream.on('close', cleanup);
    stream.on('error', (err) => {
      console.error('[Export-Seed Download]', err.message);
      res.destroy();
      cleanup();
    });
  });

  return router;
};
