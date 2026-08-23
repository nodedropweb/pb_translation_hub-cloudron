-- Migration 006: DeepL als suggestion_type erlauben
-- Erweitert den ENUM um 'deepl'.
--
-- translation_suggestions wurde ursprünglich außerhalb des Migrationssystems
-- angelegt (auf bestehenden Installationen existiert die Tabelle bereits, hier
-- läuft nur die ALTER TABLE gegen sie) — auf einer frischen Installation gab
-- es dafür aber gar keine CREATE TABLE-Migration, wodurch diese ALTER TABLE
-- mit "Table ... doesn't exist" fehlschlug und den Server-Start blockierte.
-- CREATE TABLE IF NOT EXISTS hier ergänzt, damit ein frischer Cloudron-Install
-- funktioniert; auf bestehenden Installationen ist es ein No-op.
CREATE TABLE IF NOT EXISTS translation_suggestions (
  id              INT(11)      NOT NULL AUTO_INCREMENT,
  machine_name    VARCHAR(255) NOT NULL,
  langcode        VARCHAR(10)  NOT NULL,
  title           VARCHAR(255) DEFAULT NULL,
  summary         TEXT         DEFAULT NULL,
  body            LONGTEXT     DEFAULT NULL,
  source_hash     VARCHAR(32)  DEFAULT NULL,
  created_at      TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP,
  user_id         INT(11)      DEFAULT NULL,
  suggestion_type ENUM('ai', 'manual', 'deepl') DEFAULT 'manual',
  PRIMARY KEY (id),
  KEY machine_name (machine_name, langcode)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE translation_suggestions
  MODIFY COLUMN suggestion_type ENUM('ai', 'manual', 'deepl') DEFAULT 'manual';
