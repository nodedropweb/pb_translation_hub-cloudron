# Datenstruktur & Sync-Logik

*[🇬🇧 English version](DATA_STRUCTURE.md)*

Dieses Dokument erklärt die JSON-Datenstrukturen im PB Translation Hub und wie sie Synchronisation und "veraltete" ("stale") Übersetzungserkennung ermöglichen.

> **Cloudron-Hinweis:** Die Pfade unten sind als `server/data/...` geschrieben, passend zum
> Docker-Compose-Deployment. Auf Cloudron liegen dieselben Dateien stattdessen unter
> `/app/data/...` (siehe [CLOUDRON_DEPLOYMENT.de.md](CLOUDRON_DEPLOYMENT.de.md)) — alles andere
> auf dieser Seite (Schema, Sync-Logik, Stale-Erkennung) ist in beiden Fällen identisch.

## 1. Quell-Metadaten (Drupal.org)

Gespeichert in `server/data/metadata/*.json` (`/app/data/metadata/*.json` auf Cloudron). Diese Dateien sind Spiegelungen der Drupal.org-JSON:API-Antworten.

| Key | Typ | Beschreibung | Zweck im Hub |
| :--- | :--- | :--- | :--- |
| `attributes.title` | String | Original-englischer Titel. | Quelle für die Übersetzung. |
| `attributes.changed` | Unix-Timestamp | Letzter Aktualisierungszeitpunkt auf Drupal.org. | **Kritisch für den Sync.** Wird in der Spalte `projects.changed` gespeichert. Erkennt, ob sich die Quelle seit der letzten Übersetzung geändert hat. |
| `attributes.body.value` | HTML | Vollständige Projektbeschreibung. | Quelle für die Übersetzung. |
| `attributes.body.summary` | Text | Kurzbeschreibung des Projekts. | Quelle für die Übersetzung. |
| `field_project_machine_name` | String | Eindeutiger Maschinenname (z. B. `webform`). | Primärschlüssel zur Datenverknüpfung. |

## 2. Hub-interne Übersetzungen

Gespeichert in `server/data/translations/[langcode]/*.json` (`/app/data/translations/[langcode]/*.json` auf Cloudron) — eine dateibasierte Backup-Ebene.
Die `translations`-Datenbanktabelle (MariaDB bei Docker-Compose, MySQL 8 auf Cloudron) ist die maßgebliche Quelle für die API.

| Key | Typ | Beschreibung | Zweck im Hub |
| :--- | :--- | :--- | :--- |
| `machine_name` | String | Referenz auf das Projekt. | Verknüpfung. |
| `title`, `summary`, `body` | Lokalisiert | Der übersetzte Inhalt. | Zieldaten. |
| `langcode` | String | Zielsprachcode, z. B. `de`. | Sprach-Routing. |
| `updated_at` | Timestamp | Letzter Speicherzeitpunkt im Hub. | Versionierung. |
| `source_hash` | MD5-Hash | Hash der englischen Quelle (Titel + Body). | **Stale-Erkennung.** Stellt sicher, dass die Übersetzung exakt zu der Content-Version passt, gegen die sie erstellt wurde. |
| `is_reviewed` | Boolean (0/1) | Produktions-Freigabestatus. | Qualitätskontrolle. Nur Datensätze mit `is_reviewed = 1` werden über die Shadow-API an Drupal-Sites ausgeliefert. |
| `reviewed_by` | String | Username des freigebenden Reviewers. | Audit-Trail. |

## 3. Synchronisations- & Stale-Detection-Logik

### A. Inkrementeller Datenbank-Sync
Beim Synchronisieren von Modul-Daten von Drupal.org in die Datenbank speichert der Hub den `attributes.changed`-Timestamp in `projects.changed`. Bei jedem Sync-Durchlauf werden nur Module aktualisiert, deren `changed`-Wert gestiegen ist. Das vermeidet unnötiges Neuschreiben unveränderter Datensätze.

### B. Intelligente Stale-Erkennung
Eine Übersetzung wird nur dann als **veraltet** markiert, wenn der berechnete MD5-Hash der aktuellen englischen Quelle (`projects.data`) nicht mehr mit dem `source_hash` übereinstimmt, der zum Zeitpunkt der Übersetzung gespeichert wurde. Diese zweistufige Prüfung verhindert, dass Übersetzungen fälschlich als veraltet markiert werden, wenn sich auf Drupal.org nur nicht-textliche Metadaten ändern (z. B. eine Maintainer-Neuzuweisung).

Die Stale-Query:
```sql
SELECT t.machine_name, t.langcode
FROM translations t
JOIN projects p ON t.machine_name = p.machine_name
WHERE t.source_hash != MD5(p.data);
```

## 4. Shadow-API-Antwortformat

Wenn das `pb_localizer`-Drupal-Modul eine übersetzte Modul-Auflistung anfragt, liefert der Hub eine JSON-Struktur, die das Drupal.org-JSON:API-Format spiegelt — folgende Felder werden dabei, wenn vorhanden, durch die Hub-Übersetzungen überschrieben:

```json
{
  "data": [
    {
      "id": "...",
      "attributes": {
        "title": "<übersetzter Titel>",
        "body": {
          "value": "<übersetztes Body-HTML>",
          "summary": "<übersetzte Kurzbeschreibung>"
        }
      },
      "meta": {
        "translation": {
          "title": "<übersetzter Titel>",
          "summary": "<übersetzte Kurzbeschreibung>",
          "body": "<übersetztes Body-HTML>",
          "is_reviewed": true,
          "langcode": "de"
        }
      }
    }
  ]
}
```

Der `meta.translation`-Block wird vom Flutter-Review-List-Screen genutzt, um übersetzte Titel und Kurzbeschreibungen in der Review-Warteschlange anzuzeigen — Reviewer lesen so den zielsprachlichen Inhalt statt des englischen Originals.
