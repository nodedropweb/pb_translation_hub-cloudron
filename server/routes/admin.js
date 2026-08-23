const express = require('express');
const zlib = require('zlib');

// Content tables included in a seed export — mirrors export_for_cloudron.sh
// --seed / seedFromBundledDataIfRequested() in index.js. Deliberately excludes
// `users` and `schema_migrations`: a seeded instance gets its own fresh admin
// account via normal registration, and migration bookkeeping stays untouched.
const SEED_TABLES = [
  'projects', 'translations', 'glossary_terms',
  'priority_projects', 'ignored_projects', 'sync_events', 'site_settings',
];

module.exports = (ctx) => {
  const { db, authenticateToken, isAdmin } = ctx;
  const router = express.Router();

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
  router.get('/admin/export-seed', authenticateToken, isAdmin, async (req, res) => {
    try {
      const lines = ['SET NAMES utf8mb4;'];
      for (const table of SEED_TABLES) {
        const [rows] = await db.query(`SELECT * FROM \`${table}\``);
        for (const row of rows) {
          const columns = Object.keys(row);
          const values = columns.map((col) => db.escape(row[col]));
          lines.push(
            `INSERT INTO \`${table}\` (${columns.map((c) => `\`${c}\``).join(',')}) VALUES (${values.join(',')});`
          );
        }
      }

      const gz = zlib.gzipSync(Buffer.from(lines.join('\n') + '\n', 'utf8'));
      const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

      res.set({
        'Content-Type': 'application/gzip',
        'Content-Disposition': `attachment; filename="pb_hub_seed_${stamp}.sql.gz"`,
      });
      res.send(gz);
    } catch (err) {
      console.error('[Export-Seed]', err.message);
      res.status(500).json({ error: 'Export failed' });
    }
  });

  return router;
};
