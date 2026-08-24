-- Migration 011: Ressourcenmonitor (Sidebar-Feature).
-- Zwei Tabellen für einen Netdata-artigen, aber schlanken Verlauf:
--
-- resource_samples — Zeitreihe von CPU/RAM/Disk, alle 5 Minuten vom Server
-- selbst gesampelt (siehe sampleResources() in index.js). 5-Minuten-Auflösung
-- über 30 Tage sind ~8600 Zeilen — unproblematisch, keine Aggregation nötig.
--
-- api_access_daily — Tages-Bucket pro aufrufender Drupal-Seite für den
-- öffentlichen Übersetzungs-Endpunkt (GET /:langcode/:filename.json, von
-- pb_localizer aufgerufen). Bewusst NICHT als Rohlog pro Request: jede
-- Drupal.org-Projektübersicht mit z. B. 30 Modulen erzeugt 30 Requests pro
-- Seitenaufruf, das würde unbegrenzt wachsen. Ein Upsert pro (Tag, Site) hält
-- die Tabelle auf Tage × bekannte Seiten begrenzt und reicht für den
-- Zeitverlauf im Monitor. site_url = '' bedeutet: aufrufende pb_localizer-
-- Version ist zu alt, um den X-PB-Site-Url-Header zu senden (nur IP bekannt).
--
-- DSGVO / Privacy by Design (siehe logApiAccess() in index.js):
--   - Datenminimierung: last_ip wird NUR gespeichert, wenn site_url leer ist
--     (Fallback-Identifikator für nicht-identifizierte Aufrufer) — sobald eine
--     Site sich selbst über den Header identifiziert, wäre die IP redundant
--     und wird gar nicht erst übergeben.
--   - Wenn IP gespeichert wird: nur anonymisiert (anonymizeIp() maskiert das
--     letzte IPv4-Oktett bzw. die letzten ~80 Bit von IPv6), nie die volle
--     Adresse.
--   - Speicherbegrenzung: automatische Löschung nach 90 Tagen
--     (ACCESS_LOG_RETENTION_DAYS, läuft im selben 5-Minuten-Tick wie
--     sampleResources()).

CREATE TABLE IF NOT EXISTS resource_samples (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  sampled_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  cpu_percent   DECIMAL(6,2) DEFAULT NULL,   -- % eines Kerns, gemittelt über das Sample-Intervall; kann >100 sein (Multi-Core)
  mem_used_mb   INT DEFAULT NULL,
  mem_limit_mb  INT DEFAULT NULL,            -- NULL, wenn cgroup kein Limit setzt
  disk_code_mb  INT DEFAULT NULL,            -- App-Code selbst (/app/code)
  disk_data_mb  INT DEFAULT NULL,            -- Uploads + Übersetzungsdateien (alle Sprachen zusammen)
  disk_db_mb    INT DEFAULT NULL,
  KEY idx_sampled_at (sampled_at)
);

-- total_duration_ms/max_duration_ms: Server-Antwortzeit (echte Bearbeitungs-
-- zeit inkl. Datei-I/O), gemessen pro Request und pro (Tag, Site) aufsummiert.
-- Ø ms/Zugriff = total_duration_ms / request_count — die beste verfügbare
-- Annäherung an "wie viele Ressourcen kostet ein pb_localizer-Abruf den Hub",
-- ohne teures Per-Request-CPU-Profiling.
CREATE TABLE IF NOT EXISTS api_access_daily (
  id                 INT AUTO_INCREMENT PRIMARY KEY,
  day                DATE NOT NULL,
  site_url           VARCHAR(255) NOT NULL DEFAULT '',
  request_count      INT NOT NULL DEFAULT 0,
  total_duration_ms  BIGINT NOT NULL DEFAULT 0,
  max_duration_ms    INT NOT NULL DEFAULT 0,
  last_seen          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_ip            VARCHAR(64) DEFAULT NULL,
  UNIQUE KEY uniq_day_site (day, site_url),
  KEY idx_day (day)
);
