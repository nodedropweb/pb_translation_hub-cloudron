-- Migration 004: Gewünschte Rolle bei Registrierung speichern
-- requested_role speichert den Wunsch des Nutzers dauerhaft,
-- user_type enthält die tatsächlich gewährte Rolle nach Freischaltung.

-- Kein "IF NOT EXISTS" (MariaDB-only, MySQL 8 lehnt die Syntax komplett ab —
-- Parse-Error, nicht "Spalte existiert schon"). db_migrate.js fängt die
-- portable "Duplicate column name"-Fehlermeldung ab, die beide DBs bei einem
-- erneuten ADD COLUMN auf eine bereits vorhandene Spalte werfen.
ALTER TABLE users
  ADD COLUMN requested_role ENUM('translator', 'reviewer') NOT NULL DEFAULT 'translator'
    COMMENT 'Role requested at registration — shown in pending list for admin reference';
