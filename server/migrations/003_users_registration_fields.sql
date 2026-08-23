-- Migration 003: Registrierungs-Felder für Benutzer
-- Fügt target_languages (JSON) und user_type (translator/reviewer) hinzu.

-- Kein "IF NOT EXISTS" (MariaDB-only, MySQL 8 lehnt die Syntax komplett ab —
-- Parse-Error, nicht "Spalte existiert schon"). db_migrate.js fängt die
-- portable "Duplicate column name"-Fehlermeldung ab, die beide DBs bei einem
-- erneuten ADD COLUMN auf eine bereits vorhandene Spalte werfen.
ALTER TABLE users
  ADD COLUMN target_languages LONGTEXT DEFAULT NULL
    COMMENT 'JSON array of language codes the user works on',
  ADD COLUMN user_type ENUM('translator', 'reviewer') NOT NULL DEFAULT 'translator'
    COMMENT 'translator = no review queue access; reviewer = can approve translations';
