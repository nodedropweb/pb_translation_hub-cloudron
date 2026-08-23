-- Migration 010: projects.changed (Drupal.org-Änderungszeitstempel)
--
-- Wurde ursprünglich außerhalb des Migrationssystems direkt auf der
-- Live-DB angelegt (index.js/routes/sync.js schreiben und lesen die Spalte
-- seit langem, INSERT INTO projects (..., changed) ...) — fehlte hier aber
-- komplett, wodurch ein frischer Install mit "Unknown column 'changed'"
-- fehlschlug, sobald die App das erste Mal in `projects` schreiben wollte.
ALTER TABLE projects
  ADD COLUMN changed VARCHAR(50) DEFAULT NULL;

CREATE INDEX idx_changed ON projects (changed);
