const express = require('express');

// Resource-monitor endpoints (admin-only) — backs the sidebar's
// "Ressourcenmonitor" screen. Reads from resource_samples (periodic
// CPU/RAM/disk snapshots, see scheduleResourceSampling() in index.js) and
// api_access_daily (per-day, per-site access counts + response-time totals,
// logged from the public translation/category endpoints pb_localizer calls).
module.exports = (ctx) => {
  const { db, authenticateToken, isAdmin, readCgroupMemory, readCgroupCpuPercent } = ctx;
  const router = express.Router();

  const RANGE_DAYS = { '24h': 1, '7d': 7, '30d': 30 };
  function parseRange(req) {
    return RANGE_DAYS[req.query.range] || 7;
  }

  // Live-ish snapshot: freshly read CPU%/RAM (cheap file reads), disk figures
  // from the most recent periodic sample (a `du` scan is too slow to run on
  // every page load — see readDirSizeMb() in index.js), plus today's access
  // totals.
  router.get('/monitor/summary', authenticateToken, isAdmin, async (req, res) => {
    try {
      const [{ usedMb, limitMb }, cpuPercent] = await Promise.all([
        readCgroupMemory(),
        readCgroupCpuPercent(),
      ]);

      const [[latestSample]] = await db.execute(
        'SELECT disk_code_mb, disk_data_mb, disk_db_mb, sampled_at FROM resource_samples ORDER BY sampled_at DESC LIMIT 1'
      );

      const [[todayTotals]] = await db.execute(
        `SELECT
           COALESCE(SUM(request_count), 0) AS requests,
           COALESCE(SUM(total_duration_ms), 0) AS totalDurationMs,
           COUNT(DISTINCT CASE WHEN site_url != '' THEN site_url END) AS knownSites,
           SUM(CASE WHEN site_url = '' THEN request_count ELSE 0 END) AS unattributedRequests
         FROM api_access_daily WHERE day = CURDATE()`
      );

      res.json({
        cpuPercent,
        memUsedMb: usedMb,
        memLimitMb: limitMb,
        diskCodeMb: latestSample ? latestSample.disk_code_mb : null,
        diskDataMb: latestSample ? latestSample.disk_data_mb : null,
        diskDbMb: latestSample ? latestSample.disk_db_mb : null,
        diskSampledAt: latestSample ? latestSample.sampled_at : null,
        today: {
          requests: todayTotals.requests,
          knownSites: todayTotals.knownSites,
          unattributedRequests: todayTotals.unattributedRequests,
          avgResponseMs: todayTotals.requests > 0
            ? Math.round(todayTotals.totalDurationMs / todayTotals.requests)
            : null,
        },
      });
    } catch (error) {
      console.error('[Monitor] summary error:', error);
      res.status(500).json({ error: 'Failed to load resource summary' });
    }
  });

  // Time series for the CPU/RAM/disk charts.
  router.get('/monitor/resources', authenticateToken, isAdmin, async (req, res) => {
    try {
      const days = parseRange(req);
      const [rows] = await db.execute(
        `SELECT sampled_at, cpu_percent, mem_used_mb, mem_limit_mb, disk_code_mb, disk_data_mb, disk_db_mb
         FROM resource_samples
         WHERE sampled_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
         ORDER BY sampled_at ASC`,
        [days]
      );
      res.json(rows);
    } catch (error) {
      console.error('[Monitor] resources error:', error);
      res.status(500).json({ error: 'Failed to load resource history' });
    }
  });

  // Per-day access totals (for the "wie viele Drupal-Seiten wann" chart) plus
  // a per-site breakdown for the range, sorted by traffic.
  router.get('/monitor/access', authenticateToken, isAdmin, async (req, res) => {
    try {
      const days = parseRange(req);

      const [daily] = await db.execute(
        `SELECT day,
                SUM(request_count) AS requests,
                COUNT(DISTINCT CASE WHEN site_url != '' THEN site_url END) AS knownSites,
                SUM(total_duration_ms) AS totalDurationMs
         FROM api_access_daily
         WHERE day >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
         GROUP BY day
         ORDER BY day ASC`,
        [days]
      );

      const [sites] = await db.execute(
        `SELECT site_url AS siteUrl,
                SUM(request_count) AS requests,
                SUM(total_duration_ms) AS totalDurationMs,
                MAX(last_seen) AS lastSeen,
                MAX(last_ip) AS lastIp
         FROM api_access_daily
         WHERE day >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
         GROUP BY site_url
         ORDER BY requests DESC
         LIMIT 100`,
        [days]
      );

      res.json({
        daily: daily.map((d) => ({
          day: d.day,
          requests: d.requests,
          knownSites: d.knownSites,
          avgResponseMs: d.requests > 0 ? Math.round(d.totalDurationMs / d.requests) : null,
        })),
        sites: sites.map((s) => ({
          siteUrl: s.siteUrl || null,
          requests: s.requests,
          avgResponseMs: s.requests > 0 ? Math.round(s.totalDurationMs / s.requests) : null,
          lastSeen: s.lastSeen,
          lastIp: s.lastIp,
        })),
      });
    } catch (error) {
      console.error('[Monitor] access error:', error);
      res.status(500).json({ error: 'Failed to load access history' });
    }
  });

  return router;
};
