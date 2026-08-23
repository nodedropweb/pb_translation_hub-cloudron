-- Migration 002: DeepL API Key für Benutzer
-- Fügt deepl_api_key zur users-Tabelle hinzu.

-- Kein "IF NOT EXISTS" (MariaDB-only, MySQL 8 lehnt die Syntax komplett ab —
-- Parse-Error, nicht "Spalte existiert schon"). db_migrate.js fängt die
-- portable "Duplicate column name"-Fehlermeldung ab, die beide DBs bei einem
-- erneuten ADD COLUMN auf eine bereits vorhandene Spalte werfen.
ALTER TABLE users
  ADD COLUMN deepl_api_key VARCHAR(255) DEFAULT NULL;
