-- Migration 006: DeepL als suggestion_type erlauben
-- Erweitert den ENUM um 'deepl'.
--
-- Die CREATE TABLE steht hier voran, weil translation_suggestions auf
-- Live-Systemen historisch manuell angelegt wurde und in keiner früheren
-- Migration existiert — auf einer frischen DB (z.B. Cloudron) schlug diese
-- Migration bisher mit "Table doesn't exist" fehl. IF NOT EXISTS macht das
-- auf bestehenden Live-DBs zum No-Op.

CREATE TABLE IF NOT EXISTS translation_suggestions (
  id              INT(11) NOT NULL AUTO_INCREMENT,
  machine_name    VARCHAR(255) NOT NULL,
  langcode        VARCHAR(10) NOT NULL,
  title           VARCHAR(255) DEFAULT NULL,
  summary         TEXT DEFAULT NULL,
  body            LONGTEXT DEFAULT NULL,
  source_hash     VARCHAR(32) DEFAULT NULL,
  created_at      TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  user_id         INT(11) DEFAULT NULL,
  suggestion_type ENUM('ai', 'manual', 'deepl') DEFAULT 'manual',
  PRIMARY KEY (id),
  KEY machine_name (machine_name, langcode)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE translation_suggestions
  MODIFY COLUMN suggestion_type ENUM('ai', 'manual', 'deepl') DEFAULT 'manual';
