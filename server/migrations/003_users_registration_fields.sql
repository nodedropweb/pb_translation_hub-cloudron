-- Migration 003: Registrierungs-Felder für Benutzer
-- Fügt target_languages (JSON) und user_type (translator/reviewer) hinzu.

ALTER TABLE users
  ADD COLUMN target_languages LONGTEXT DEFAULT NULL
    COMMENT 'JSON array of language codes the user works on',
  ADD COLUMN user_type ENUM('translator', 'reviewer') NOT NULL DEFAULT 'translator'
    COMMENT 'translator = no review queue access; reviewer = can approve translations';
