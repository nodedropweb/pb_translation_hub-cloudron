const express = require('express');
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Content tables included in a seed export — mirrors export_for_cloudron.sh
// --seed / seedFromBundledDataIfRequested() in index.js. Deliberately excludes
// `users` and `schema_migrations`: a seeded instance gets its own fresh admin
// account via normal registration, and migration bookkeeping stays untouched.
const SEED_TABLES = [
  'projects', 'translations', 'glossary_terms',
  'priority_projects', 'ignored_projects', 'sync_events', 'site_settings',
];

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
  const { db, authenticateToken, isAdmin, DATA_DIR } = ctx;
  const router = express.Router();
  const EXPORT_DIR = path.join(DATA_DIR, 'exports');

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

  // Export a content-only snapshot of the current DB as a gzipped SQL dump —
  // same tables/statement format the first-boot seed importer expects
  // (server/index.js: seedFromBundledDataIfRequested()), so the downloaded
  // file can be dropped straight in as server/seed/db_seed.sql.gz before the
  // next Cloudron image build. Built entirely from the already-open mysql2
  // pool (no mariadb-dump/mysqldump binary involved), so it works regardless
  // of what client tools a given deployment target ships.
  //
  // `projects` alone holds the entire Drupal.org catalog (tens of thousands
  // of rows with a JSON blob each) — an earlier version that buffered every
  // INSERT line into one big array, joined it into a string, then gzipped
  // that in one shot, OOM-crashed the Node process on a real instance
  // (heap blew past its container limit holding several full copies of the
  // same data at once). This streams rows straight from MySQL into a gzip
  // stream, still with constant memory — but now into a temp file on disk
  // instead of straight onto the response.
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
    const filename = `pb_hub_seed_${stamp}.sql.gz`;
    const filePath = path.join(EXPORT_DIR, `${crypto.randomUUID()}.sql.gz`);

    const gzip = zlib.createGzip();
    const fileStream = fs.createWriteStream(filePath);
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
          await writeAndDrain(
            `INSERT INTO \`${table}\` (${columns.map((c) => `\`${c}\``).join(',')}) VALUES (${values.join(',')});\n`
          );
        }
      }

      gzip.end();
      await new Promise((resolve, reject) => {
        fileStream.on('finish', resolve);
        fileStream.on('error', reject);
      });

      const token = crypto.randomBytes(32).toString('hex');
      pendingExports.set(token, { filePath, filename, expiresAt: Date.now() + EXPORT_TTL_MS });
      res.json({ token, filename });
    } catch (err) {
      console.error('[Export-Seed]', err.message);
      gzip.destroy();
      fileStream.destroy();
      fs.unlink(filePath, () => {});
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
      'Content-Type': 'application/gzip',
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
