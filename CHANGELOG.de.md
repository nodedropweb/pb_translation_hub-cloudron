# Änderungsprotokoll

*[🇬🇧 English version](CHANGELOG.md)*

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Daten im Format `YYYY-MM-DD`.

---

## [Unreleased]

### Added

#### Analyse-Dashboard — Kompatibilität, Übersetzungsbedarf & Wochen-Verläufe
- **`server/migrations/009_sync_events.sql`** — neue Tabelle `sync_events` (Verlauf von `new_module` / `description_changed` / `stale` mit `event_date`).
- **`server/index.js`** — Helper `recordSyncEvents()` protokolliert vor jedem `projects`-Upsert neue Module, geänderte Beschreibungen und dadurch veraltete Übersetzungen (pro Sprache); in `syncProjects()` und allen Sync-Pfaden in **`server/routes/sync.js`** eingebunden.
- **`server/routes/dashboard.js`** — neuer Endpoint `GET /dashboard/weekly?type=new_description|stale&weeks=&langcode=` (Wochenbuckets + Modullisten). Kompatibilität/Bedarf nutzt weiterhin `/projects/filter-counts`.
- **`server/scripts/backfill_sync_events.js`** — einmaliger, idempotenter Backfill des Verlaufs aus `projects.changed`.
- **`flutter_client/lib/screens/analytics/analytics_screen.dart`** + **`providers/analytics_provider.dart`** — neuer „Statistik"-Screen (Route `/analytics`, Nav-Eintrag): Übersetzungsbedarf-Karten, Kompatibilitäts-Balken pro Drupal 9–12, zwei ausklappbare Wochenlisten (neue Beschreibungen / veraltet markiert).

#### Vollständiges Backup & Restore (DB + Übersetzungs-/Kategorie-Dateien)
- **`backup.sh`** / **`restore.sh`** — sichern bzw. restaurieren DB-Dump **und** den `data/translations/`-Baum (inkl. `_categories.json`, das nur als Datei existiert) in/aus einem Archiv `backups/pb_hub_backup_<stamp>.tar.gz`. Modi `--local` und Live-Server per SSH.

#### Stale-Massen-Übersetzung — alle veralteten Module per Knopfdruck neu übersetzen
- **`server/routes/ai.js`** — neuer Endpoint `GET /ai/stale-machine-names?langcode=X`: liefert alle Machine-Names, deren `source_hash` nicht mehr mit dem aktuellen englischen Text übereinstimmt, direkt aus der DB (kein Pagination-Limit).
- **`flutter_client/lib/screens/dashboard/dashboard_screen.dart`** — `_showStaleBulkTranslateDialog()`: spezieller Dialog für den Stale-Filter, der alle veralteten Module vorab abruft, Gesamtanzahl und Kostenschätzung anzeigt und ohne Count-Dropdown direkt startet.
- **`_executeBulkTranslationWithNames()`** — neue Methode, die eine explizite Machine-Name-Liste in Batches à 4 an `/ai/translate-bulk` schickt; orangefarbener Progress-Dialog; aktualisiert nach Abschluss automatisch den Stale-Filter.

#### Stale-Erkennung — veraltete Übersetzungen anzeigen & beheben
- **`server/routes/projects.js`** — `/projects/:machine_name` berechnet jetzt einen MD5-Hash über `title + body.summary + body.value` und vergleicht ihn mit `translations.source_hash`. Weicht der Hash ab, liefert die API `status: 'stale'`.
- **`flutter_client/lib/screens/editor/editor_screen.dart`** — neues Feld `_isStale`; wird beim Laden gesetzt, wenn der API-Status `'stale'` ist. Bei veralteter Übersetzung öffnet sich die englische Quell-Seitenleiste automatisch.
- **`flutter_client/lib/screens/editor/_editor_build_methods.dart`** — orangefarbener „Veraltet — Details"-Button in der Editor-Toolbar; öffnet `_showStaleDialog()`. Neue Methode `_useEnglishSource()` ersetzt Zusammenfassung und Body mit dem aktuellen englischen Original und setzt `_isStale` zurück.

#### Diff-Ansicht — Übersetzung vs. englische Quelle
- **`flutter_client/lib/utils/diff_utils.dart`** — Wort-Diff-Algorithmus (`DiffSpan`, `DiffOp`: equal / insert / delete). Liefert eine Liste von `DiffSpan`-Objekten für zwei Texte.
- **`flutter_client/lib/widgets/diff_view.dart`** — `DiffView`-Widget (inline farbkodierter Diff) und `showDiffSheet()` (Bottom-Sheet mit zweispaltigem Vergleich). Grün = Einfügung, Rot = Löschung.
- **`flutter_client/lib/screens/review/review_screen.dart`** — neuer „DIFF"-Button im Review-Screen-Header: öffnet `showDiffSheet()` mit Übersetzung (links) vs. englischer Quelle (rechts).

#### Debug-Sync-Endpunkte (geschützt via `PB_DEBUG_KEY`)
- **`server/routes/sync.js`** — drei neue Routen, nur erreichbar mit korrektem `X-PB-Debug-Key`-Header:
  - `GET /debug/sync/inspect/:machine_name` — vergleicht DB-Stand mit Live-Daten von Drupal.org (Title, Changed, Body-Länge).
  - `POST /debug/sync/force/:machine_name` — erzwingt Einzelmodul-Sync von Drupal.org in DB + Metadaten-Verzeichnis.
  - `POST /debug/sync/quick` — führt Quick-Sync für ein konfigurierbares Zeitfenster (`days`, Standard: 7) durch und gibt ein detailliertes Log zurück.

#### Automatischer Quick-Sync alle 7,5 Tage
- **`server/index.js`** — `scheduleQuickSync()` startet einen `setInterval` (7,5 Tage) nach dem Server-Start. Überspringt automatisch, wenn bereits ein Sync läuft oder kein `lastFullSync`-Timestamp vorhanden ist.

#### App-Icons (Android / iOS / Windows)
- **`appicons/`** — vollständige Icon-Sets für alle Plattformen hinzugefügt (Android Launcher-Icons, iOS-Größen 16–1024 px, Windows Tiles, Splash Screens, Store Logo).

#### Deutsches Intro-Audio
- **`flutter_client/web/audio/crwb_de.mp3`** — deutschsprachige Audioversion des Project-Browser-Localizer-Intros (ElevenLabs-Generierung) aktualisiert.

### Fixed

#### CKEditor — `<img>`-Tags erhalten
- **`flutter_client/web/index.html`** — `img` zur `htmlSupport.allow`-Konfiguration hinzugefügt, damit CKEditor 5 `<img>`-Tags beim Initialisieren oder Speichern nicht mehr entfernt.

#### Docker — PM2-Cluster deaktiviert
- **`server/Dockerfile`** — PM2 läuft jetzt mit `-i 1` (Single-Instance) statt `-i max`. Cluster-Modus würde konkurrierende Sync-Prozesse erzeugen, da der Sync-Status im RAM gehalten wird.

---

## [2.3.0] — 2026-06-09

### Added

#### Glossary — Wortformen (Plurale & flektierte Formen)
- **`server/migrations/007_glossary_word_forms.sql`** — neue Spalte `word_forms TEXT NULL` in `glossary_terms`. Speichert kommagetrennte flektierte Formen (Plural, Genitiv, Dativ usw.), z.B. `"Inhalte,Inhalts,Inhalten"`.
- **`server/routes/glossary.js`** — GET normalisiert `word_forms` von Komma-String zu Array; POST/PUT nehmen ein `word_forms`-Array entgegen, speichern als String, geben in der Antwort wieder Array zurück.
- **`flutter_client/web/index.html`** — `_ckApplyGlossaryMarkers` baut pro Term eine RegExp-Alternation aus `source_word` + allen `word_forms`: `\b(Inhalt|Inhalte|Inhalts|Inhalten)\b`. Die exakte gematchte Form wird als `encodeURIComponent`-kodiertes Segment in den Marker-Namen geschrieben (`glossaryTerm:<id>:<uid>:<encodedForm>`).
- **`GlossaryHighlightPlugin`** — dekodiert die gematchte Form aus dem Marker-Namen und schreibt sie als `data-matched`-Attribut ans Highlight-`<span>`. Zusätzlich zu den bestehenden `data-preferred` und `data-explanation`.
- **Glossar-Tooltip** — zeigt jetzt die konkrete im Text gefundene Wortform an:
  - *Flektierte Form* (z.B. „Inhalte"): kleiner weißer Label „Inhalte" + Pfeil „↓ bevorzugte Übersetzung" + lila/fett „Inhalt".
  - *Grundform* (matched == preferred): nur die Grundform lila/fett, kein Pfeil.
- **`flutter_client/lib/screens/glossary/glossary_screen.dart`** — Chip-UI für Wortformen im Bearbeitungsdialog: Textfeld + „+"-Button zum Hinzufügen, „✕"-Chips zum Entfernen. In der Tabellenzeile werden Wortformen als kleinere Amber-Mini-Chips neben dem Grundform-Badge angezeigt.

#### Einstellung: Automatische Absatzformatierung (Auto-P)
- **`flutter_client/lib/providers/theme_provider.dart`** — neues Feld `autoAutop: bool` in `ThemeState`, persistiert als `pb-autoAutop` in `SharedPreferences`. Standard: `false`. Neue Methode `setAutoAutop(bool)`.
- **`flutter_client/lib/screens/settings/settings_screen.dart`** — Switch-Toggle im Bereich „Workflow & Spaß", direkt unter dem Large-UI-Toggle. Zweisprachig: DE „Automatische Absatzformatierung (¶ Auto-P)" / EN „Automatic Paragraph Formatting (¶ Auto-P)".
- **`flutter_client/lib/screens/review/review_screen.dart`** — am Ende von `_fetchData()`, nachdem alle Felder mit Inhalt befüllt wurden, wird `_autop()` automatisch auf Summary und Body angewendet, wenn `themeState.autoAutop == true`. Identisches Verhalten zum manuellen ¶-Button, aber ohne Snackbar-Meldung.

### Fixed

#### CKEditor — Init-Race-Condition
- **`flutter_client/web/index.html`** (`_ckBridge.init`) — `document.getElementById('cke_editor_<id>')` wird jetzt bis zu 10× mit 200 ms Abstand wiederholt, falls das DOM-Element beim ersten Aufruf noch nicht im Dokument ist. Zusätzlicher Retry (bis zu 3×, 500 ms) bei `ClassicEditor.create()`-Rejection.
- **`flutter_client/lib/widgets/ckeditor_field_web_impl.dart`** — 3-Sekunden-Safety-Net: falls `onReady` nach dem `bridge.init`-Aufruf nie feuert, wird der Editor zerstört und neu initialisiert. `didUpdateWidget` aktualisiert `_lastContent` nun immer, auch wenn `_editorReady` noch `false` ist.

#### Glossar-Tooltip — Stabilität (mouseover/mouseout)
- **`flutter_client/web/index.html`** — `mouseover`- und `mouseout`-Handler nutzen jetzt `relatedTarget`, um zu prüfen ob die Maus den Highlight-Span wirklich verlässt. Interne Bewegungen innerhalb des Spans lösen kein Hide mehr aus. `clearTimeout` wird im `mouseover`-Handler nur noch aufgerufen wenn die Maus tatsächlich über einem Highlight-Element ist.

---

## [2.2.0] — 2026-06-02

### Added

#### DeepL-Integration
- **`POST /ai/deepl-translate`** — übersetzt Kurzbeschreibung und Body eines einzelnen Moduls über die DeepL-API mit dem persönlichen `deepl_api_key` des authentifizierten Nutzers. Wählt automatisch `api-free.deepl.com` für Keys mit `:fx`-Endung und `api.deepl.com` für Pro-Keys. Sendet `tag_handling: 'html'`, um Markup zu erhalten. Speichert das Ergebnis sowohl als `translations`-Datensatz als auch als `translation_suggestions`-Zeile (Typ `'deepl'`).
- **`GET /ai/deepl-usage`** — proxied einen Aufruf von `GET /v2/usage` auf der DeepL-API mit dem Key des Nutzers. Liefert `character_count`, `character_limit` und (für Pro-Accounts) Aufschlüsselung pro Produkt sowie Abrechnungszeitraum-Timestamps. Wird vom Sidebar-Nutzungs-Widget verwendet.
- **DeepL-Sidebar-Widget** (`_DeeplUsageWidget`) — erscheint in der Navigations-Sidebar, sobald der eingeloggte Nutzer einen `deepl_api_key` im Profil gespeichert hat. Zeigt einen farbkodierten Fortschrittsbalken (grün → orange → rot bei 70 %/90 %) plus formatierte Zeichenzahlen. Hat einen manuellen Aktualisieren-Button. Bei unbegrenzten Keys wird „unbegrenzt / unlimited" statt eines Balkens angezeigt.
- **`server/migrations/006_suggestion_type_deepl.sql`** — erweitert das `suggestion_type`-ENUM auf `translation_suggestions` von `('ai','manual')` auf `('ai','manual','deepl')`. Diese Migration verursachte den ursprünglichen 500er-Fehler ("Data truncated") und wird jetzt automatisch beim Server-Start angewendet.
- **DeepL-Button im Editor** — reiht sich neben den bestehenden Gemini- und DeepL-Buttons in der Übersetzungspanel-Kopfzeile ein. Deaktiviert, während eine andere KI-Übersetzung läuft.
- **`User-Agent: PBTranslationHub/1.0`**-Header zu allen DeepL-API-Requests hinzugefügt (`/v2/translate` und `/v2/usage`), wie von den DeepL-API-Richtlinien gefordert.

#### Review-Screen — Tablet-Layout
- **`_buildReviewHeaderTablet`** — neue responsive Header-Variante für Bildschirmbreiten zwischen 600 dp und 1099 dp (deckt das BEYNIVAN-M986-EEA-Tablet bei ~1000 dp Querformat ab). Identisches einzeiliges Layout wie der Desktop-Header, aber Tastaturkürzel-Hinweise (`Strg+→`, `Strg+Enter`) werden aus den Button-Labels weggelassen, um Overflow zu vermeiden.

#### Editor — Off-Canvas-Quellpanel
- **Clipboard/Prompt-Button** zur „Englische Quelle"-Off-Canvas-Drawer-Kopfzeile hinzugefügt, identisch zum bereits vorhandenen PROMPT-Button im Review-Screen-Header. Kopiert `buildTranslationPrompt(…)` mit dem aktuellen englischen Quelltext.

#### Übersetzungs-Prompt-Verbesserungen
- Labels `"Summary:"` und `"Main Description:"` aus dem kopierten Clipboard-Text entfernt; die zwei Blöcke werden jetzt durch eine Leerzeile und einen nackten `---`-Separator getrennt. Die KI-Anweisung erklärt weiterhin, dass der erste Block die Kurzbeschreibung und der zweite der Body ist.
- Explizite Regel hinzugefügt: **Ausgabe nicht in Markdown-Code-Fences einpacken** (keine Triple-Backtick-HTML-Blöcke). Behebt, dass Gemini/Deepseek gefencte Code-Blöcke statt rohem HTML zurückgeben.

#### Ignorierte Module — Massen-Wiedereinreihung
- **`DELETE /projects/ignore-all`** — neuer Server-Endpunkt (Auth erforderlich). Löscht alle Zeilen aus `ignored_projects` und liefert `{success, count}`.
- **Dashboard-Button „Alle wieder einreihen"** — erscheint nur, wenn der „Ignoriert"-Filter aktiv ist. Öffnet einen sprachbewussten Bestätigungsdialog (DE/EN). Bei Bestätigung wird der Massen-Wiedereinreihungs-Endpunkt aufgerufen und der Filter auf „Alle" umgeschaltet.
- **Editor-Button „Einreihen"** — im Editor-Header angezeigt, sobald `meta.is_ignored === true` für das aktuelle Modul. Ruft `DELETE /projects/:name/ignore` für das einzelne Modul auf.

#### Login-Screen — Bilder-Slideshow
- **Manueller Bild-Slider** mit `‹`/`›`-Navigationspfeilen, animierten Fortschritts-Punkten und Crossfade-Übergängen. Jeder `›`-Klick zeigt entweder den nächsten gecachten Slide oder holt ein neues Bild von `/unsplash/random-bg`.
- **Auto-Play-Umschalter**-Button über den Punkten; startet/stoppt einen 6-Sekunden-Auto-Advance-Timer (nutzt denselben Lazy-Fetch-Mechanismus, um unnötige API-Aufrufe zu vermeiden).
- **Verpflichtende Unsplash-Attribution** unten links für jedes API-bezogene Bild angezeigt: Fotografenname und "Unsplash" verlinken beide mit `?utm_source=pb_translation_hub&utm_medium=referral`, um die Unsplash-API-Bedingungen einzuhalten und Production-Tier-Zugriff (50.000 Requests/Stunde) zu erhalten.

#### Themes
- **Pearl-Theme** (`'pearl'`) — cleanes flaches Design mit solidem Lavendel-Hintergrund (`#ECE8F9`, 100 % deckendes Overlay), reinweißen Karten, minimalem Blur (`glassBlur: 1.0`) und sanftem Lila-Akzent (`#8B7FD4`). Ersetzt das bisherige "Hell/Light"-Theme.
- **Stage-Theme** (`'stage'`) — Konzert-/Event-Ästhetik: dunkler Smaragd-Türkis-Hintergrund (`#0C2222`), warmer Orange-Akzent (`#F58620`), 80 % Türkis-Overlay. Hintergrund-Keyword: `concert,neon,stage,festival,dark`.
- **"Hell/Light"-Button** in Sidebar und Einstellungen mappt jetzt auf `pearl` (die interne Theme-ID). Nutzer, die `light` in `SharedPreferences` gespeichert hatten, werden beim nächsten Laden automatisch auf `pearl` migriert.

#### Review-List-Screen — Toolbar
- **"Aktualisieren / Refresh"** und **"Freigaben zurücksetzen / Reset published"** von schwebenden Icon-Buttons im Seiten-Header in die Such-Toolbar verschoben. Beide sind jetzt `OutlinedButton.icon` mit sichtbaren Labels und Lade-Spinnern.

### Fixed
- **DeepL-500er-Fehler** — das Einfügen eines Vorschlags mit `suggestion_type = 'deepl'` hat die ENUM-Spalte abgeschnitten. Behoben durch Migration 006.
- **Light-Theme-Lesbarkeit** — `GlassContainer`-Bereiche im Study- und Help-Screen nutzten `Colors.white.withValues(alpha: 0.04)`-Hintergründe (unsichtbar im hellen Modus). Alle hartkodierten fast-transparenten weißen Container durch `attrs.bgCard` ersetzt.
- **Sichtbarkeit der Tastatur-Chips** im Help-Screen (Shortcut-Bereich) — `Colors.white.withOpacity(0.1)`-Hintergründe durch `attrs.bgInput` / `attrs.borderMain` ersetzt.

---

## [2.1.0] — 2026-06-02

### Added

#### Glossar-Term-Highlighting (CKEditor-5-Plugin)
- **`server/migrations/005_create_glossary_terms.sql`** — neue Tabelle `glossary_terms` (`id`, `lang_code`, `source_word`, `preferred_word`, `explanation`, `created_by`, Timestamps). Indexiert auf `lang_code` und `source_word`.
- **`server/routes/glossary.js`** — REST-API: `GET /glossary` (filterbar via `?langcode=`), `POST /glossary`, `PUT /glossary/:id`, `DELETE /glossary/:id`. Schreibende Endpunkte erfordern Rolle `reviewer` oder `admin`.
- **`GlossaryHighlightPlugin`** in `web/index.html` — CKEditor-5-Plugin, das `markerToHighlight` nutzt (nur beim Editieren, verunreinigt `getData()` nie). Marker tragen `affectsData: false`, sodass Undo/Redo sie ignoriert.
- **`_ckApplyGlossaryMarkers(editor)`** — wendet `glossaryTerm:<id>:<uid>`-Modell-Marker auf jedes Block-Element an; nutzt `\b`-Wortgrenzen-Regex (case-insensitive). Läuft innerhalb von `model.change()`.
- **`_ckBridge.setGlobalGlossary(termsJson)`** — globaler Glossar-Store. Der Aufruf dieser Methode wendet Marker in allen aktiven CKEditor-Instanzen sofort neu an.
- **Schwebendes Tooltip** (`#_ck_glossary_tip`) — erscheint bei Hover über `.ck-glossary-highlight`-Spans; zeigt bevorzugte Übersetzung und Erklärung. Positioniert, um im Viewport zu bleiben.
- **`flutter_client/lib/utils/ck_glossary.dart`** — geteilte Dart-Utilities:
  - `loadCkEditorGlossary(api, langcode)` — holt `/glossary` und ruft `setGlobalGlossary` auf der Bridge auf. Wird sowohl von `ReviewScreen` als auch `EditorScreen` beim Mount und Sprachwechsel aufgerufen.
  - `setCkEditorTheme(themeId)` — setzt CSS-Custom-Properties auf `#_ck_glossary_tip` und `:root` direkt via `dart:html` (keine JS-Bridge nötig). Deckt alle 5 Themes ab.
- **`flutter_client/lib/screens/glossary/glossary_screen.dart`** — Verwaltungs-UI für Glossar-Terme. Reviewer und Admins können Terme hinzufügen, bearbeiten und löschen. Zeigt die Terme der aktuellen Zielsprache mit Quellwort, bevorzugter Übersetzung und Erklärung. Erreichbar über Sidebar-Navigationseintrag.
- **Glossar-Laden in `EditorScreen`** — `_loadGlossary()` hinzugefügt (war bisher nur in `ReviewScreen`); wird 400 ms nach `initState` und bei Sprachwechsel via `ref.listen` ausgelöst.
- **Glossar-Laden in `ReviewScreen`** — refaktoriert, um das geteilte `loadCkEditorGlossary` aufzurufen; wird ebenfalls bei Sprachwechsel ausgelöst.
- **Marker nach `setData` neu angewendet** — ein 300 ms debouncter Aufruf von `_ckApplyGlossaryMarkers` läuft innerhalb des `change:data`-Listeners, sodass Marker nach jeder Inhaltsänderung aufgefrischt werden.

#### Theme-bewusstes Glossar-Styling
- **CSS-Custom-Properties** `--ck-hl-bg` und `--ck-hl-border` auf `:root` steuern die Highlight-Markierungsfarbe; `--tip-*`-Variablen auf `#_ck_glossary_tip` steuern das schwebende Tooltip. Beide werden von `setCkEditorTheme()` aktualisiert.
- **Farb-Sets pro Theme** in `ck_glossary.dart`: dark (Amber-Highlight, lila Tooltip), light (lila Highlight + Tooltip), glassy (Cyan), nature (Grün), liquid (Himmelblau).
- **`app_layout.dart`** ruft `setCkEditorTheme(themeState.themeId)` bei jedem `build()` auf — Tooltip- und Highlight-Farben aktualisieren sich sofort beim Theme-Wechsel.

#### Entwicklungs-Erfahrung
- **`api_client.dart` WSL-/Nicht-Standard-Port-Erkennung** — `baseUrl` und `serverOrigin` erkennen jetzt jeden Nicht-Standard-Port (nicht 80/443) als Entwicklungsumgebung und lösen zu `host:9901` auf. Zuvor wurden nur `localhost` / `127.0.0.1` erkannt, was beim Zugriff über die WSL-IP zu Login-Fehlern führte.

#### Logging & Diagnose
- **`LogService`** (`lib/services/log_service.dart`) — In-Memory-Ringpuffer für `INFO`-/`WARNING`-/`ERROR`-Einträge mit Timestamps und optionalen Details. Integriert in Dio-Interceptors.
- **Log-Download** (`lib/services/log_downloader_web.dart` / `_stub.dart`) — exportiert den Log-Puffer als JSON-Datei via `dart:html`-Blob-Download im Web.

#### Audio-Player
- **`audio_player_web.dart` / `audio_player_stub.dart`** — bedingter Import, der `dart:html AudioElement` für Web umschließt. Wird vom CRWB-Study-Screen für TTS-Audio-Wiedergabe ohne native Abhängigkeiten verwendet.

#### CKEditor-5-Web-Implementierung
- **`ckeditor_field_web_impl.dart`** — vollständige Web-only-CKEditor-5-Implementierung, aus `ckeditor_field.dart` extrahiert. Registriert via `ui_web.platformViewRegistry`. Behandelt `init`, `setData`, `destroy`, Suppression-CSS und `didUpdateWidget`-Pushes.
- **`ckeditor_field_stub.dart`** — Nicht-Web-Stub, der den bedingten Import auf Desktop erfüllt.

### Fixed
- **Glossar-Marker nicht in `EditorScreen` gezeigt** — `loadCkEditorGlossary` wurde nur von `ReviewScreen` aufgerufen. Jetzt auch von `EditorScreen` aufgerufen.

---

## [2.0.0] — 2026-05-31

### Breaking Changes
- **Nutzerverwaltungssystem** — Nutzer haben jetzt einen `user_type` (`translator` / `reviewer`) und ein `is_active`-Flag. Bestehende Nutzer in der Datenbank müssen `is_active = 1` manuell gesetzt bekommen, falls sie vor diesem Release angelegt wurden, oder über das Admin-Panel reaktiviert werden.
- **Rollenbasierter Zugriff auf die Review-Warteschlange** — Nutzer mit `user_type = 'translator'` können nicht mehr auf die Review-Warteschlange zugreifen. Der Router leitet sie zum Dashboard um, und der Server liefert HTTP 403 auf Review-Endpunkten.
- **DB-Migrationen erforderlich** — Migrationen `003_users_registration_fields.sql` und `004_users_requested_role.sql` fügen neue Spalten zur `users`-Tabelle hinzu. Der Migrations-Runner wendet sie automatisch beim Server-Start an.

### Added
- **4-Schritte-Registrierungsassistent** (`register_screen.dart`) — Self-Service-Account-Erstellung: Account → Rolle → Sprachen → API-Keys. Registrierung kann global über `site_settings.registration_enabled` deaktiviert werden.
- **Panel "Wartende Nutzer"** — Admin-Screen, der Accounts mit `is_active = 0` auflistet. Admins weisen eine Rolle zu (`translator` / `reviewer`) und aktivieren jeden Account. Neben Nutzern, die die Rolle `reviewer` angefragt haben, erscheint ein Badge.
- **Panel "Aktive Nutzer"** — Admin-Screen, der Accounts mit `is_active = 1` auflistet. Admins können Nutzer deaktivieren (sperren) oder dauerhaft löschen.
- **`GET /auth/registration-status`** — öffentlicher Endpunkt; liefert `{ enabled: true/false }`.
- **`GET /admin/users/active`** — listet aktive Nutzer.
- **`PATCH /admin/users/:id/deactivate`** — deaktiviert einen aktiven Nutzer.
- **Konfetti** — `confetti`-Package integriert. `ConfettiController` in Editor- und Review-Screens feuert bei Speichern/Freigeben. Eine 900-ms-Navigationsverzögerung stellt sicher, dass die Animation sichtbar ist, bevor die Route wechselt. Umschalter im Settings-Screen.
- **Splash-Screen** — `lib/widgets/splash_screen.dart` (Flutter-Widget) + HTML-Preloader in `web/index.html`. Mindestanzeigedauer 2200 ms. Wird beim `flutter-first-frame`-Event ausgeblendet.
- **Logo** — `assets/images/logo.png` in Sidebar (44×44) und Topbar-Mini-Logo (34×34) angezeigt. App-Name von "TRANSLATION SUITE" zu "TRANSLATION HUB" geändert.
- **Zweisprachige Filter-Buttons** — jeder Dashboard-Filter zeigt das deutsche Label (fett, 13 px) und das englische Label (grau, 10 px) vertikal übereinander.
- **Split-Diff-Ansicht** — `review_diff_view.dart`: Originaltext oben (rot getönter Hintergrund), korrigierter Text unten (grün getönt). Ersetzt die vorherige überlappende Diff-Anzeige.
- **Optimistische Navigation im Review-Screen** — `_goToNextReview()` ist synchron (`void`); der Speicher-POST läuft im Hintergrund, während die App sofort zum nächsten Eintrag in der Warteschlange navigiert.
- **`inheritedQueue` im Review-Screen** — die vollständige Review-Warteschlange wird von `review_list_screen.dart` an `review_screen.dart` übergeben, um die Race-Condition zu beseitigen, die doppelt angezeigte Module verursachte.
- **Review-Liste zeigt übersetzte Titel** — `review_list_screen.dart` nutzt `meta.translation.title` und `meta.translation.summary` statt der englischen Originale, sodass Reviewer den zielsprachlichen Inhalt sehen.
- **`review_sidebar.dart` als `StatefulWidget`** — Sidebar hat einen internen `_showSourceCode`-Umschalter, um zwischen gerenderter Vorschau und roher HTML-Quellansicht zu wechseln. Enthält einen Copy-to-Clipboard-Button.
- **Off-Canvas-Umschalt-Button nach links verschoben** — der Sidebar-Umschalt-Button im Review-Screen ist jetzt auf der linken Seite des Headers.
- **Englische Quelle aus dem Haupt-Editor-Bereich entfernt** — im Review-Screen wird die englische Quelle ausschließlich innerhalb der Sidebar gezeigt. Die Tabs "Visueller Vergleich" und "Quellcode" wurden entfernt; nur "Direkter Editor" und "Vorschau" bleiben. Der "Nur vergleichen"-Button wurde entfernt.
- **Sync-Fortschritt zeigt echte Gesamtzahl** — `total` wird aus `meta.count` in der ersten Drupal.org-API-Antwort gelesen. Der Fortschrittsbalken zeigt "X Module …", solange die Gesamtzahl noch nicht bekannt ist, und wechselt dann zu "X / Y", sobald die erste Seite antwortet.
- **DB-Migrationssystem** — `server/db_migrate.js` + `server/migrations/NNN_*.sql`. Trackt angewendete Versionen in `schema_migrations`. Läuft automatisch beim Server-Start. Beendet sich mit Code 1 bei Fehlschlag.
- **Neue DB-Spalten** — `users.target_languages` (JSON-Array), `users.user_type` (ENUM), `users.requested_role` (VARCHAR), `users.deepl_api_key` (VARCHAR), `projects.changed` (BIGINT).
- **`deploy.sh` Rolling Restart** — Server- und Client-Container werden neu gebaut, ohne die Datenbank offline zu nehmen. Kein `docker compose down`.
- **`deploy.sh --db-backup`-Flag** — erstellt vor Deploy-Beginn einen komprimierten `mysqldump` in `~/backups/`.
- **Migrations-Log in deploy.sh** — das Deploy-Skript wartet auf das Server-Container-Log, um zu bestätigen, dass Migrationen erfolgreich abgeschlossen sind.
- **`watch_stale.sh`** — Shell-Skript zur Überwachung veralteter Übersetzungen auf dem Server.
- **Neue Flutter-Dateien:** `register_screen.dart`, `splash_screen.dart`, `page_transition.dart`.
- **Neue Server-Dateien:** `db_migrate.js`, `migrations/001–004_*.sql`, `watch_stale.sh`.

### Changed
- **Bulk-Übersetzungslimit** — von 200 auf 150 Module pro Request reduziert, für bessere Server-Stabilität.
- **Dio-`receiveTimeout` für Bulk-Route** — auf 10 Minuten erhöht, um große Bulk-Übersetzungs-Batches abzudecken.
- **Server-Antwort-Performance** — `res.json()` wird direkt nach dem DB-Write gesendet. `fs.writeJson` (Dateisystem-Backup) läuft asynchron im Hintergrund.

### Fixed
- **Doppelte Module in Review-Warteschlange** — verursacht durch eine Race-Condition, bei der der Review-Screen die Warteschlange unabhängig vom List-Screen abgerufen hat. Warteschlange wird jetzt als `inheritedQueue` übergeben.
- **Sync-Fortschritt zeigte "1731 / 100"** — die Gesamtzahl war auf 100 hartkodiert. Wird jetzt aus `meta.count` der ersten API-Antwort gelesen.
- **Konfetti im Review-Screen nicht sichtbar** — sofortige Navigation nach Freigabe ließ keine Zeit für die Animation. Eine 900-ms-Verzögerung wird jetzt vor der Navigation angewendet.
- **Splash-Screen-Logo nicht sichtbar** — `frameBuilder` wurde für das asynchrone Asset-Bild nicht genutzt, wodurch das Logo im ersten Frame unsichtbar war. Behoben mit korrektem asynchronem Asset-Laden.
- **Review-Karten zeigten englischen Text** — `review_list_screen.dart` liest Titel und Kurzbeschreibungen jetzt aus `meta.translation` statt aus den englischen `attributes`.

---

## [1.5.0] — 2026-05-25

### Changed
- **Fleather ersetzt Quill.js als WYSIWYG-Editor** im gesamten Flutter-Client.
  - `fleather: ^1.26.0` und `parchment: ^1.25.1` zu `pubspec.yaml` hinzugefügt.
  - Die Quill-CDN-`<link>`- und `<script>`-Tags aus `web/index.html` entfernt.
  - `editor_html_toolbar.dart` neu geschrieben — nimmt jetzt einen `FleatherController` statt
    einen `onExecCommand`-Callback entgegen. Toolbar-Buttons nutzen `ParchmentStyle.containsSame()` /
    `controller.formatSelection()` für korrekte Toggle-Semantik bei jedem Attribut.
  - `_editor_quill_bridge.dart` (Part-Datei) zu einer reinen HTML-Utility-Datei umgeschrieben;
    aller DOM-/`dart:html`-Quill-Bridge-Code entfernt.
  - `editor_screen.dart` auf `FleatherController` + `FleatherEditor` für sowohl das
    Summary- als auch das Body-Feld migriert. `TextEditingController` bleibt die HTML-Source-of-Truth
    fürs API-Speichern; ein Listener auf `FleatherController` kodiert das Parchment-Dokument
    bei jeder Bearbeitung automatisch via `ParchmentHtmlCodec` nach HTML.
  - `_editor_build_methods.dart` neu geschrieben — visuelle Container nutzen jetzt `FleatherTheme` +
    `FleatherEditor` (Dark-Theme, alle erforderlichen `FleatherThemeData`-Felder). Fest-höhige
    `SizedBox`-Wrapper durch `constraints: BoxConstraints(minHeight: …)` ersetzt, sodass
    Editoren mit dem Inhalt wachsen.
  - `review_screen.dart` vollständig migriert: Quill-Visual-Editor-`HtmlElementView`-Platform-
    Views entfernt; `FleatherEditor` an ihrer Stelle eingefügt. CodeMirror-HTML-Quell-Iframes
    für den Quellansicht-Umschalter beibehalten. Der `quill-change`-DOM-Event-Listener, `_execCommand`,
    `_setJsPendingContent` und alle `_syncHtmlToReviewIFrame`-/`_syncHtmlToReviewVisual`-
    Aufrufe durch `_reloadFleatherControllers()` und `_syncToSourceIFrame()` ersetzt.

### Removed
- Quill.js-CDN-Abhängigkeiten (`quill.snow.css`, `quill.js` 1.3.6) — werden nicht mehr geladen.
- Alle `dart:html`-basierten `document.createElement`-/`ScriptElement`-Hacks, die genutzt wurden,
  um Inhalt in Quill-Iframes zu übergeben.

---

## [1.4.0] — 2026-05-24

### Added
- **"Can't Read, Won't Buy"-Studien-Screen** (`lib/screens/help/crwb_study_screen.dart`)
  — Alle 32 Seiten der Common-Sense-Advisory-(2006)-Studie als native Flutter-
  Inhalte eingebettet. Der Screen ist immer offline verfügbar und unabhängig von der externen
  PDF-URL. Inhalt umfasst: Executive Summary, Umfrage-Demografie (2.430 Konsumenten /
  8 Länder), alle 8 Kernaussagen mit animierten Balkendiagrammen, den Besucher-Abbruch-
  Funnel (aufklappbare Kacheln), vier Fazit-Karten und einen formalen Zitationsblock.
- Route `/help/crwb` in GoRouter registriert (innerhalb der authentifizierten ShellRoute).
- **Video-Panel-Fehler-/Ladezustände** in `HelpScreen` — ein Skeleton-Spinner wird gezeigt,
  während der Server antwortet; ein bernsteinfarbenes Warnbanner ersetzt den leeren Bereich, wenn der
  Server nicht erreichbar ist oder `HELP_VIDEO_DE` / `HELP_VIDEO_EN` nicht in `.env` gesetzt sind.

### Changed
- Button "Originalstudie lesen (PDF)" in `HelpScreen` navigiert jetzt zu `/help/crwb`
  (interner Screen) statt die externe PDF-URL zu öffnen.
- `help_screen.dart` importiert jetzt `go_router` für `context.push()`; der ungenutzte
  `TokenStorage`-Import wurde entfernt.

---

## [1.3.1] — 2026-05-24

### Fixed
- **Tastaturkürzel im Help-Screen korrigiert** — drei Shortcuts (`Strg+Alt+K`, `Strg+Alt+H`, `Strg+Alt+O`), die nie im Editor implementiert wurden, wurden aus dem Shortcuts-Panel entfernt.
- **Vorschau-Shortcut-Modifikator korrigiert** — Help-Screen zeigt jetzt `Alt+P` (nicht `Strg+Alt+P`) für "Vorschau umschalten", passend zur tatsächlichen Bindung in `editor_screen.dart`.

### Changed
- `_shortcutRow()` in `HelpScreen` akzeptiert einen optionalen `showCtrl`-Parameter für Zeilen mit Nicht-Standard-Modifikatoren.
- Die Behauptung "Alle Shortcuts nutzen STRG + ALT" aus der Shortcuts-Panel-Beschreibung entfernt.

---

## [1.3.0] — 2026-05-24

### Added
- **`ModuleLogo`-Widget** (`lib/widgets/module_logo.dart`) — einheitlicher, CORS-sicherer Modul-
  Logo-Loader mit dreistufiger Kaskade: primäre `logoUrl` → `fallbackLogoUrl` → Buchstaben-Avatar.

### Fixed
- **Projekt-Karten-Logos im Browser unsichtbar** — alle Logo-Requests laufen jetzt über `/api/image-proxy`.
- **Buchstaben-Fallback für Module mit defektem GitLab-Avatar** — Module ohne GitLab-Repository zeigen jetzt das `project_browser`-Logo über die `fallbackLogoUrl`-Kaskade.

---

## [1.2.0] — 2026-05-22

### Added
- **Dashboard-Filter-Umbruch** — Filter-Buttons nutzen ein `Wrap`-Widget; fließen bei Tablet-Hochformat-Viewports (~768 px) in eine zweite Zeile.
- **Android-14-Unterstützung** — `targetSdk = 34`; `INTERNET`-Berechtigung und `android:enableOnBackInvokedCallback="true"` hinzugefügt.

### Changed
- **KI-Massenübersetzungs-Dialog — Fortschrittsmeldungen** — Fortschritt meldet jetzt Modulnummern statt Batch-Nummern.
- **KI-Massenübersetzungs-Dialog — Standardwerte** — Standardauswahl von 24 auf 25 geändert; Optionsliste zu `[25, 50, 100, 200]` geändert.
- **Profil-Screen** — den redundanten "Max Batch Size"-Schieberegler entfernt (das Steuerelement im KI-Dialog reicht).

### Fixed
- **`dart analyze`-Warnungen** — ungenutzte Variablen entfernt; `activeColor` → `activeThumbColor` bei `Switch`-Widgets korrigiert.

---

## [1.1.0] — 2026-05-20

### Added
- **`CachedNetworkImage` durchgängig** — jeden `Image.network()`-Aufruf ersetzt.
- **`RepaintBoundary` auf Hintergrundbildern** — Login-Screen- und App-Layout-Hintergründe vom Haupt-Render-Baum isoliert.
- **Help-Screen** (`screens/help/help_screen.dart`) — DSGVO-konformes Hilfe-Center mit Consent-gated YouTube-Video-Einbettungen.

### Changed
- **`Color.withOpacity()` → `.withValues(alpha:)`** — alle Flutter-Farb-Opazitäts-Aufrufe auf die nicht-veraltete API migriert.

### Fixed
- **`GlassContainer` defekte Opazität** — `.withValues(alpha: )` (leerer Wert) zu `0.1` korrigiert.

---

## [1.0.0] — 2026-04-xx

### Added
- **Flutter-Client** — vollständiger Ersatz des vorherigen React-Clients. Gebaut mit Riverpod, GoRouter, Dio und einer Glassmorphism-Dark-Mode-first-UI.
- **Server-Modularisierung** — `server/index.js` in separate Routen-Module aufgeteilt.
- **ProxyManager** — `is_reviewed`-Qualitäts-Gate, URL-Normalisierung, Port-Erkennungslogik.
- **MariaDB** als primärer Datenspeicher, ersetzt das vorherige SQLite-Setup.
- **Docker-Compose**-Dreier-Service-Stack (`db`, `server`, `client`).
- **`deploy.sh`** — automatisiertes rsync-+-Docker-Build-+-Hot-Swap-Skript; unterstützt `--client-only`-Flag.

---

## Versionsnummerierung

Versionen folgen [Semantic Versioning](https://semver.org/):
- **MAJOR** — Breaking Changes am Shadow-API-Vertrag, DB-Schema oder Zugriffskontrollmodell
- **MINOR** — neue Features, neue Endpunkte, neue UI-Screens
- **PATCH** — Bugfixes, Performance-Verbesserungen, Dokumentations-Updates
