# Flutter-Client — Technische Referenz

*[🇬🇧 English version](FLUTTER_DOCUMENTATION.md)*

Der Flutter-Client ist das primäre (und einzige) Frontend des PB Translation Hub. Er läuft in der Entwicklung als Web-App, wird in der Docker-Produktion über Nginx ausgeliefert und kann auch als native Android- oder Desktop-Anwendung kompiliert werden.

---

## Inhaltsverzeichnis
1. [Schnellstart](#1-schnellstart)
2. [Architektur & Ordnerstruktur](#2-architektur--ordnerstruktur)
3. [State Management](#3-state-management)
4. [Design-System](#4-design-system)
5. [WYSIWYG-Editoren (Quill)](#5b-wysiwyg-editoren-quill)
6. [Screens-Referenz](#6-screens-referenz)
7. [Tastaturkürzel](#7-tastaturkürzel)
8. [Docker-Produktions-Build](#8-docker-produktions-build)
9. [Bild-Loading & CORS](#9-bild-loading--cors)
10. [Android-Build](#10-android-build)
11. [Entwickler-Richtlinien](#11-entwickler-richtlinien)

---

## 1. Schnellstart

### Voraussetzungen
- Flutter-SDK (Stable-Channel, ≥ 3.x)
- Node.js ≥ 18 (für das Backend)
- Laufende und migrierte MariaDB (siehe `DATABASE.de.md`)

### Alles starten (empfohlen)
```bash
# Vom Repo-Root aus
./hubctl.sh start
```
Das startet das Node.js-Backend auf **:9901** und den Flutter-Dev-Server auf **:5173**.
`http://localhost:5173` im Browser öffnen.

### Services einzeln starten
```bash
# Backend
wsl bash -i -c "cd /var/www/pb_translation_hub/server && node index.js"

# Flutter-Dev-Server
wsl bash -i -c "cd /var/www/pb_translation_hub-cloudron/flutter_client && flutter run -d web-server --web-port 5173 --web-hostname 0.0.0.0"
```

### Hot-Reload
`hubctl.sh start` hält eine FIFO unter `/tmp/flutter_stdin`. `r` senden, um ohne Neustart ein Hot-Reload auszulösen:
```bash
echo 'r' > /tmp/flutter_stdin
```
Oder `r` im Terminal drücken, in dem Flutter läuft.

### hubctl.sh-Referenz
```
./hubctl.sh start    # Backend + Frontend starten
./hubctl.sh stop     # Beide Services beenden
./hubctl.sh restart  # stop + start
./hubctl.sh status   # Laufzeitstatus und PIDs anzeigen
./hubctl.sh logs     # Beide Logs live verfolgen
```
Logs werden nach `/tmp/pb_hub_server.log` und `/tmp/pb_hub_client.log` geschrieben.

---

## 2. Architektur & Ordnerstruktur

```
flutter_client/
├── lib/
│   ├── main.dart                  # Einstiegspunkt; umschließt App in ProviderScope
│   ├── router.dart                # GoRouter-Routendeklarationen + Rollen-Guards
│   ├── models/                    # DTOs und Entity-Modelle
│   ├── providers/                 # Riverpod-Provider
│   │   ├── auth_provider.dart
│   │   ├── theme_provider.dart
│   │   ├── language_provider.dart
│   │   ├── project_provider.dart
│   │   └── sync_provider.dart
│   ├── services/
│   │   ├── api_client.dart        # HTTP-Client (Dio); Bild-Proxy-Helper
│   │   ├── log_service.dart       # Web-Konsolen-Logging
│   │   └── token_storage.dart     # JWT-Persistenz (localStorage)
│   ├── theme/
│   │   └── app_theme.dart         # ThemeAttributes + getAttributes()
│   ├── utils/
│   │   ├── html_sanitizer.dart    # HTML-Bereinigungs-Utilities
│   │   └── translation_prompt.dart # Gemini-Prompt-Builder
│   ├── widgets/
│   │   ├── ckeditor_field.dart    # CKEditor-HTML-Feld-Wrapper
│   │   ├── consent_youtube_player.dart  # DSGVO-konforme Video-Einbettung
│   │   ├── glass_container.dart   # Glassmorphism-Karten-Primitiv
│   │   ├── module_logo.dart       # CORS-sicherer Modul-Logo-Loader (3-stufige Kaskade)
│   │   ├── page_transition.dart   # Animierter Route-Übergangs-Helper
│   │   ├── search_with_autocomplete.dart
│   │   ├── splash_screen.dart     # Gebrandetes Splash-Widget (min. 2200 ms)
│   │   └── sync_progress_bar.dart
│   └── screens/
│       ├── auth/
│       │   ├── login_screen.dart
│       │   └── register_screen.dart   # 4-Schritte-Registrierungsassistent
│       ├── dashboard/             # Projekt-Grid, Suche, Filter, KI-Massen-Modal
│       │   └── widgets/
│       │       ├── project_card.dart      # Modul-Karte (nutzt ModuleLogo)
│       │       └── dashboard_filters.dart # Zweisprachige Filter-Buttons
│       ├── editor/                # Vollständiger WYSIWYG-Editor
│       │   ├── editor_screen.dart
│       │   ├── _editor_build_methods.dart
│       │   ├── _editor_quill_bridge.dart
│       │   └── widgets/
│       │       ├── cost_calculator_dialog.dart
│       │       ├── editor_html_toolbar.dart
│       │       └── screenshot_alts_section.dart
│       ├── review/                # Menschliche Review-Warteschlange (nur reviewer/admin)
│       │   ├── review_list_screen.dart   # Warteschlangen-Liste (zeigt übersetzte Titel)
│       │   ├── review_screen.dart        # Split-Diff-Editor + optimistische Navigation
│       │   └── widgets/
│       │       ├── review_diff_view.dart  # Original (rot) / Korrigiert (grün) Split
│       │       └── review_sidebar.dart    # StatefulWidget mit Quell-Umschalter
│       ├── layout/                # AppLayout, Sidebar, Theme-Auswahl
│       │   └── app_layout.dart
│       ├── categories/
│       │   └── categories_screen.dart
│       ├── profile/               # Nutzerinfo, Statistik, KI-Einstellungen, Passwortänderung
│       │   └── profile_screen.dart
│       ├── help/                  # DSGVO-sicheres Hilfe-Center + CRWB-Studie
│       │   ├── help_screen.dart
│       │   └── crwb_study_screen.dart
│       └── settings/              # Systemkonfiguration, Theme, Konfetti, Large UI, Auto-Autop
│           └── settings_screen.dart
├── android/                       # Android-Plattform (targetSdk 34 / Android 14)
├── web/                           # Flutter-Web-Bootstrap (index.html mit Splash-Preloader)
├── Dockerfile                     # Multi-Stage: flutter build web → nginx
└── nginx.conf                     # SPA-Routing + /api/- und /uploads/-Proxies
```

---

## 3. State Management

Die App nutzt **Riverpod** (`flutter_riverpod`). Alle Provider liegen in `lib/providers/`.

| Provider | Zuständigkeit |
|---|---|
| `authProvider` | Login-/Logout-State, JWT-Token, Auto-Login beim Start, Nutzerrolle |
| `themeProvider` | Aktive Theme-ID, Schriftstil, Konfetti, Large UI, Auto-Autop-Flag, Unsplash-Hintergrund |
| `languageProvider` | Zielsprachen-Auswahl für Übersetzung |
| `projectProvider` | Projektliste, Suchtext, aktiver Filter, Einzelprojekt-Sync |
| `syncProvider` | Sync-Fortschritt (aktuelle Seite, Gesamt-Modulzahl) |

Zugriffsmuster in Widgets:
```dart
final themeState = ref.watch(themeProvider);
final attrs = AppTheme.getAttributes(themeState.themeId);
```

---

## 4. Design-System

Alle visuellen Tokens werden über `ThemeAttributes` aufgelöst. Niemals Hex-Farben hartkodieren.

### Verfügbare Attribute
```dart
attrs.brand600       // primäre Akzentfarbe
attrs.bgCard         // Karten-/Container-Hintergrund
attrs.bgSidebar      // Sidebar-Hintergrund
attrs.bgInput        // Eingabefeld-Hintergrund
attrs.textMain       // Primärer Text
attrs.textMuted      // Sekundärer Text / Hinweistext
attrs.borderMain     // Rahmenfarbe
```

### Neues Theme hinzufügen
1. `lib/theme/app_theme.dart` öffnen.
2. Neuen Case in `AppTheme.getAttributes(themeId)` hinzufügen, der ein `ThemeAttributes(...)` zurückgibt.
3. Das Theme zur Auswahlliste in `lib/screens/layout/` oder `settings/` hinzufügen.

### GlassContainer
Das primäre Karten-Primitiv. Umschließt Inhalt in `BackdropFilter` + halbtransparenter Füllung:
```dart
GlassContainer(
  border: Border.all(color: attrs.borderMain),
  padding: const EdgeInsets.all(24),
  child: ...,
)
```

---

## 5. Glossar-Term-Highlighting

### Überblick
Der Hub hebt benutzerdefinierte Glossar-Terme in jeder CKEditor-5-Instanz hervor. Hover über einen hervorgehobenen Term zeigt ein schwebendes Tooltip mit der bevorzugten Übersetzung und einer optionalen Erklärung.

### Datenfluss
```
Flutter-Boot
  └─ AppLayout.build()
       └─ setCkEditorTheme(themeId)        ← dart:html CSS-Vars, keine JS-Bridge
  └─ ReviewScreen / EditorScreen initState
       └─ loadCkEditorGlossary(api, lang)  ← GET /api/glossary?langcode=de
            └─ _ckBridge.setGlobalGlossary(json)
                 └─ _ckApplyGlossaryMarkers(editor)  ← pro aktivem CKEditor
```

### Wortformen (Plurale, flektierte Formen)

Jeder Glossar-Eintrag kann neben der Grundform (`source_word`) beliebig viele flektierte Formen speichern (Feld `word_forms` als Komma-getrennte Liste in der DB, im API immer als Array). Die Flutter-UI zeigt diese Formen als Chips im Bearbeitungsdialog; über das Textfeld + „+"-Button lassen sich neue Formen hinzufügen, per „✕"-Chip entfernen.

Beispiel: `source_word = "Inhalt"`, `word_forms = ["Inhalte", "Inhalts", "Inhalten"]` → CKEditor erkennt alle vier Schreibweisen.

### CKEditor-5-Plugin (`web/index.html`)

#### Marker-Format
`GlossaryHighlightPlugin` registriert einen `editingDowncast`-Konverter (`markerToHighlight`), der Modell-Marker in `<span class="ck-glossary-highlight" data-matched="…" data-preferred="…" data-explanation="…">` im Bearbeitungsbereich umwandelt — **nur in der Editing View**, `getData()` bleibt unberührt (`affectsData: false`).

Marker-Name-Format: `glossaryTerm:<termId>:<uid>:<encodedMatchedForm>`

- `<termId>` — Datenbank-ID des Glossar-Eintrags
- `<uid>` — fortlaufender Zähler (garantiert Eindeutigkeit)
- `<encodedMatchedForm>` — `encodeURIComponent(match[0])`, also die exakte Zeichenkette, die im Text gefunden wurde (z.B. `Inhalte`)

#### Marker-Anwendung (`_ckApplyGlossaryMarkers`)
1. Alle bestehenden `glossaryTerm:*`-Marker werden entfernt.
2. Jedes Block-Element, das `$text` enthalten kann, wird durchlaufen.
3. Pro Term wird eine RegExp-Alternation aus `source_word` + allen `word_forms` gebaut:
   ```
   \b(Inhalt|Inhalte|Inhalts|Inhalten)\b   (gi)
   ```
4. Jeder Match wird als Marker mit der exakten gematchten Form im Namen gespeichert.
5. Der Downcast-Konverter schreibt die gematchte Form als `data-matched`-Attribut ans `<span>`.

#### Marker werden erneuert bei:
- Aufruf von `setGlobalGlossary()` (Erstload oder Sprachwechsel).
- 300 ms nach jedem `change:data`-Event (debounced) — Content-Änderungen verlieren keine Highlights.
- Neuinitialisierung eines Editors, wenn `globalGlossary` bereits befüllt ist.

### Dart-Utilities (`lib/utils/ck_glossary.dart`)
| Funktion | Zweck |
|---|---|
| `loadCkEditorGlossary(api, langcode)` | Holt `/glossary`, ruft `setGlobalGlossary` auf der Bridge auf. Fehler werden still verschluckt — das Glossar ist nicht kritisch. |
| `setCkEditorTheme(themeId)` | Aktualisiert `--ck-hl-bg`, `--ck-hl-border` auf `:root` und alle `--tip-*`-Variablen auf `#_ck_glossary_tip` direkt via `dart:html`. Keine JS-Bridge beteiligt. |

Beide Funktionen sind No-ops auf Nicht-Web-Plattformen (`kIsWeb`-Guard).

### Theme-Farben
| Theme | Highlight-Hintergrund | Highlight-Rahmen | Tooltip-Akzent |
|---|---|---|---|
| dark | Amber 22 % | `#F59E0B` | `#8B5CF6` lila |
| light | Lila 12 % | `#7F56D9` | `#7F56D9` lila |
| glassy | Cyan 18 % | `#009CDE` | `#009CDE` cyan |
| nature | Grün 18 % | `#10B981` | `#10B981` grün |
| liquid | Himmelblau 18 % | `#0EA5E9` | `#0EA5E9` himmelblau |

### Schwebendes Tooltip

Beim Hover über ein markiertes Wort erscheint `#_ck_glossary_tip`. Der Tooltip unterscheidet zwei Fälle:

**Fall A — flektierte Form gefunden** (z.B. „Inhalte" im Text, Grundform ist „Inhalt"):
```
💡  Glossar-Hinweis
    Inhalte                ← data-matched (weiß, 13 px)
    ↓ bevorzugte Übersetzung
    Inhalt                 ← data-preferred (lila, 15 px fett)
    ─────────────────────
    [Erklärungstext]
```

**Fall B — Grundform gefunden** (Matched-Form == Preferred-Word):
```
💡  Glossar-Hinweis
    Inhalt                 ← direkt lila, 15 px fett, kein Pfeil
    ─────────────────────
    [Erklärungstext]
```

Das `data-matched`-Attribut enthält immer die exakte Zeichenkette aus dem Text (Groß-/Kleinschreibung wie im Original). Der Vergleich für Fall A/B ist case-insensitive.

### Glossar-Verwaltungs-Screen (`lib/screens/glossary/glossary_screen.dart`)
Route `/glossary`, erreichbar über die Sidebar. Reviewer und Admins können:
- Alle Terme für die aktuell gewählte Zielsprache sehen.
- Einen neuen Term hinzufügen (Quellwort, bevorzugtes Wort, optionale Erklärung, Wortformen).
- Bestehende Terme bearbeiten oder löschen.

**Wortformen-UI im Dialog:**  
Unter dem Feld „Quellwort (Grundform)" befindet sich ein Chip-Eingabebereich. Formen werden über ein Textfeld + „+"-Button hinzugefügt und als Chips mit „✕" einzeln entfernt. Die Liste wird als `word_forms`-Array an die API gesendet und in der Tabellenzeile als kleinere Amber-Chips neben dem Grundform-Badge angezeigt.

Änderungen wirken sich in offenen Editoren erst beim nächsten `loadCkEditorGlossary`-Aufruf aus (z.B. bei der nächsten Screen-Navigation oder Sprachwechsel).

### REST-API
| Methode | Endpunkt | Auth | Beschreibung |
|---|---|---|---|
| `GET` | `/api/glossary?langcode=de` | jeder eingeloggte Nutzer | Terme für eine Sprache auflisten |
| `POST` | `/api/glossary` | reviewer / admin | Term erstellen |
| `PUT` | `/api/glossary/:id` | reviewer / admin | Term aktualisieren |
| `DELETE` | `/api/glossary/:id` | reviewer / admin | Term löschen |

**Request-Body (POST/PUT):**
```json
{
  "lang_code":      "de",
  "source_word":    "Inhalt",
  "word_forms":     ["Inhalte", "Inhalts", "Inhalten"],
  "preferred_word": "Inhalt",
  "explanation":    "Bitte die standardisierte deutsche Bezeichnung verwenden."
}
```
Das Backend nimmt `word_forms` als Array entgegen, speichert es als komma-getrennten String in der DB und gibt es in GET/POST/PUT-Antworten immer als Array zurück.

---

## 5b. WYSIWYG-Editoren (Quill)

Der Editor- und Review-Screen betten [Quill 1.3.6](https://quilljs.com/) via `HtmlElementView`-Platform-Views ein.

### Kritisch: Observer-Disconnect-Muster
Quills Mutation-Observer normalisiert jedes an `q.root.innerHTML` geschriebene HTML und entfernt dabei `<table>`, `<img>` innerhalb von `<td>` sowie andere Nicht-Quill-Elemente. Vor dem Schreiben immer trennen:
```javascript
try { q.scroll.observer.disconnect(); } catch(e) {}
q.root.innerHTML = htmlContent;
try {
  q.scroll.observer.observe(q.root, {
    childList: true, attributes: true,
    characterData: true, subtree: true
  });
} catch(e) {}
```

### Bild-Proxy
Alle externen Bilder laufen über den Backend-Proxy, um CORS-/Mixed-Content-Probleme zu vermeiden:
```dart
// Dart-Helper
ApiClient.proxyImageUrl(originalUrl)
// Erzeugt: http://localhost:9901/api/image-proxy?url=<encoded>
```
Proxy-URLs vor dem Speichern entfernen, damit die kanonischen `drupal.org`-URLs persistiert werden:
```dart
static String _stripProxyUrls(String html) {
  return html.replaceAllMapped(
    RegExp(r'''src=["']http://localhost:\d+/api/image-proxy\?url=([^"']+)["']''',
           caseSensitive: false),
    (m) => 'src="${Uri.decodeComponent(m[1]!)}"',
  );
}
```

### Editor-Höhen (Review-Screen)
Höhen sind proportional zum Viewport, damit die App über Desktop, Tablet und Web hinweg skaliert:
```dart
final vh = MediaQuery.of(context).size.height;
final summaryEditorHeight = (vh * 0.20).clamp(160.0, 420.0);
final bodyEditorHeight    = (vh * 0.45).clamp(320.0, 960.0);
```

---

## 6. Screens-Referenz

| Screen | Datei | Route | Zugriff |
|---|---|---|---|
| Splash | `widgets/splash_screen.dart` | (initiales Overlay) | Öffentlich |
| Login | `screens/auth/login_screen.dart` | `/login` | Öffentlich |
| Register | `screens/auth/register_screen.dart` | `/register` | Öffentlich (falls aktiviert) |
| Dashboard | `screens/dashboard/dashboard_screen.dart` | `/` | Authentifiziert |
| Editor | `screens/editor/editor_screen.dart` | `/edit/:machineName` | Authentifiziert |
| Review-Liste | `screens/review/review_list_screen.dart` | `/review` | Reviewer + Admin |
| Review | `screens/review/review_screen.dart` | `/review/:machineName` | Reviewer + Admin |
| Profil | `screens/profile/profile_screen.dart` | `/profile` | Authentifiziert |
| Einstellungen | `screens/settings/settings_screen.dart` | `/settings` | Admin |
| Hilfe | `screens/help/help_screen.dart` | `/help` | Authentifiziert |
| CRWB-Studie | `screens/help/crwb_study_screen.dart` | `/help/crwb` | Authentifiziert |
| Kategorien | `screens/categories/categories_screen.dart` | `/categories` | Admin |

### Splash-Screen
`lib/widgets/splash_screen.dart` ist ein Flutter-Widget, das das gebrandete Logo und den Namen "TRANSLATION HUB" anzeigt. Ein passender HTML-Preloader in `web/index.html` wird gezeigt, bis die Flutter-Engine das `flutter-first-frame`-Event auslöst. Die Mindestanzeigedauer beträgt 2200 ms, um ein Aufblitzen ungestylten Inhalts auf schnellen Geräten zu verhindern.

### Register-Screen — 4-Schritte-Assistent
`lib/screens/auth/register_screen.dart` implementiert den Selbstregistrierungs-Flow:
1. **Account** — Username, E-Mail, Passwort
2. **Rolle** — Translator oder Reviewer (`requested_role`)
3. **Sprachen** — Zielsprachen-Auswahl für Übersetzung
4. **API-Keys** — optionaler persönlicher Gemini-Key

Der Screen prüft `GET /auth/registration-status` beim Laden. Ist die Registrierung deaktiviert, zeigt er statt des Formulars einen Hinweis.

### Review-Screen — Architektur
Der Review-Screen (`review_screen.dart`) erhält die vollständige Warteschlange als `inheritedQueue` vom Review-List-Screen, um eine Doppel-Fetch-Race-Condition zu vermeiden. Die Navigation zwischen Warteschlangen-Einträgen nutzt `_goToNextReview()`, das synchron ist (`void`) — der Speicher-POST läuft im Hintergrund über ein unawaited Future, was sofortige optimistische Navigation erlaubt.

Die Off-Canvas-Sidebar (`review_sidebar.dart`) ist ein `StatefulWidget` mit einem booleschen `_showSourceCode`-Umschalter. Sie zeigt die englische Quelle mit einem "Vorschau / Quelle"-Umschalter und einem Kopieren-Button. Der Sidebar-Umschalt-Button sitzt links im Header.

Die Split-Diff-Ansicht (`review_diff_view.dart`) zeigt den Originaltext oben auf rot getöntem Hintergrund und den korrigierten Text unten auf grün getöntem Hintergrund. Es gibt keinen überlappenden Textmodus.

### Review-List-Screen
`review_list_screen.dart` zeigt übersetzte Titel und Kurzbeschreibungen aus `meta.translation` statt der englischen Originaltexte, sodass Reviewer den Inhalt in der Zielsprache sehen.

### Dashboard-Filter-Buttons
Jeder Filter-Button in `dashboard_filters.dart` zeigt zwei übereinander gestapelte Labels: das deutsche Label (fett, 13 px) oben und das englische Label (grau, 10 px) darunter. Diese zweisprachige Darstellung macht die Oberfläche sowohl für deutsch- als auch englischsprachige Nutzer ohne zusätzliche UI-Elemente nutzbar.

### Review-Screen — Off-Canvas-Sidebar
Der Review-Screen hat eine einklappbare Off-Canvas-Sidebar (standardmäßig geschlossen), die den englischen Quelltext mit einem Vorschau-/Quelle-Umschalter und einem Kopieren-Button enthält. Der Umschalt-Button sitzt links im Header. Der Haupt-Editor expandiert auf volle Breite, wenn die Sidebar ausgeblendet ist.

---

## 7. Tastaturkürzel

### Editor-Screen
| Kürzel | Aktion |
|---|---|
| `Strg+Alt+S` | Übersetzung speichern und zum nächsten Projekt |
| `Alt+P` | Live-HTML-Vorschau umschalten |
| `Strg+Alt+D` | Zum nächsten Projekt überspringen, ohne zu speichern |

### Review-Screen
| Kürzel | Aktion |
|---|---|
| `Strg+S` | Vorschlag speichern |
| `Strg+Enter` | Übersetzung für Produktion freigeben |
| `Strg+→` | Zum nächsten Eintrag in der Review-Warteschlange springen |

---

## 8. Docker-Produktions-Build

> Dieser Abschnitt beschreibt das Docker-Compose-Deployment (separater `client`-Container). Auf
> Cloudron ist der Flutter-Build Stage 1 des Root-`Dockerfile` und wird vom nginx desselben
> einzelnen Containers ausgeliefert (`nginx/app.conf`, proxied auf `127.0.0.1:9901` statt
> `server:9901`) — siehe [CLOUDRON_DEPLOYMENT.de.md](CLOUDRON_DEPLOYMENT.de.md).

Das `flutter_client/Dockerfile` ist ein Zweistufen-Build:
1. **Build-Stage** — kompiliert den Flutter-Web-Release mit `flutter build web --release`.
2. **Serve-Stage** — kopiert die `build/web/`-Ausgabe in einen Nginx-Container.

Die `nginx.conf` behandelt:
- SPA-Fallback (alle Pfade → `index.html`)
- `/api/` → Proxy zu `http://server:9901/api/`
- `/uploads/` → Proxy zu `http://server:9901/uploads/`

```bash
# Gesamten Stack bauen und starten
docker compose up -d --build

# Frontend erreichbar unter
http://localhost:5173
```

Um den Host-Port zu ändern, `docker-compose.yml` bearbeiten:
```yaml
client:
  ports:
    - "8080:80"   # 5173 zu einem beliebigen freien Port ändern
```

---

## 9. Bild-Loading & CORS

### Warum Bilder einen Server-Proxy brauchen

Die Flutter-Web-App läuft im Browser. Jedes Bild, das von einer externen Domain geladen wird
(z.B. `git.drupalcode.org`, `drupal.org`), unterliegt der CORS-Policy des Browsers.
Diese Domains senden keine `Access-Control-Allow-Origin`-Header, die Cross-Origin-
Requests von `pb.drupaltutorials.de` erlauben, sodass ein direkter `Image.network()`- oder
`CachedNetworkImage(imageUrl: externalUrl)`-Aufruf still mit einem CORS-Fehler fehlschlägt.

**Lösung:** Alle externen Bilder über den Backend-Proxy-Endpunkt
`GET /api/image-proxy?url=<encoded>` leiten. Der Server holt das Bild serverseitig
(keine CORS-Einschränkung) und streamt es mit `Access-Control-Allow-Origin: *` zurück.

```dart
// Immer diesen Helper nutzen — nie eine externe URL direkt an ein Bild-Widget übergeben.
final proxied = ApiClient.proxyImageUrl('https://git.drupalcode.org/...');
```

### `CachedNetworkImage` — der einzige Bild-Loader

Alle Netzwerkbilder in der App nutzen `cached_network_image`. Es bietet:
- **Disk-Cache** — Bilder überleben Page-Reloads (Flutter Web: nur Memory-Cache).
- **Placeholder-/Error-Widgets** — sauberes UX beim Laden und bei Fehlschlag.
- `CachedNetworkImageProvider` wird als `CircleAvatar.backgroundImage`-Provider genutzt.

`Image.network()` **nicht** an irgendeiner Stelle der Codebase nutzen.

### `RepaintBoundary` — um Vollbild-Hintergründe

Hintergrundbilder (Login-Screen, App-Layout) werden in `RepaintBoundary` eingepackt:

```dart
RepaintBoundary(
  child: CachedNetworkImage(
    imageUrl: ApiClient.proxyImageUrl(bgUrl),
    fit: BoxFit.cover,
    ...
  ),
)
```

Das isoliert den Hintergrund vom Rest des Render-Baums und verhindert, dass der gesamte
Widget-Baum neu gezeichnet wird, wenn sich nur der Hintergrund ändert (z.B. beim Theme-Wechsel).

### `ModuleLogo`-Widget — CORS-sicherer Modul-Logo-Loader

`lib/widgets/module_logo.dart` ist das einzige Widget zum Laden von Drupal-Modul-Logos
auf Projektkarten. Es implementiert eine **3-stufige Kaskade**:

| Stufe | Quelle | Wann |
|---|---|---|
| 1 | `logoUrl` via Proxy | Das Modul hat einen gültigen, erreichbaren GitLab-Avatar |
| 2 | `fallbackLogoUrl` via Proxy | `logoUrl` ist `null`, leer, oder der Proxy liefert einen Fehler (z.B. GitLab 404 → Proxy 502) |
| 3 | Buchstaben-Avatar (Flutter-Widget) | Beide URLs fehlen oder schlagen fehl |

```dart
ModuleLogo(
  machineName: project.machineName,   // für den Anfangsbuchstaben auf Stufe 3 genutzt
  logoUrl: project.logoUrl,           // z.B. https://git.drupalcode.org/project/token/-/avatar
  fallbackLogoUrl:                    // gezeigt, wenn logoUrl fehlt oder defekt ist
      'https://git.drupalcode.org/project/project_browser/-/avatar',
  accentColor: attrs.brand600,
  bgColor: attrs.bgCard,
)
```

**Warum project_browser als Fallback?**
Dieser Hub übersetzt die Metadaten, die vom Drupal-Project-Browser-Modul
(`project_browser`) konsumiert werden. Dessen Logo als Default zu nutzen schafft
semantische Konsistenz — Module ohne eigenen GitLab-Avatar zeigen trotzdem ein Drupal-Kontext-Icon.

**Warum viele Module defekte GitLab-Avatare haben:**
Der Server setzt `logoUrl = https://git.drupalcode.org/project/{machineName}/-/avatar`
für jedes Modul. Viele ältere oder inaktive Module haben jedoch überhaupt kein GitLab-
Repository (ihr Code liegt auf Drupal.org-CVS oder einem privaten Host), sodass GitLab
404 liefert, der Proxy 502 liefert, und `CachedNetworkImage` `errorWidget` auslöst.
`fallbackLogoUrl` fängt diesen Fall ab.

### Bild-Proxy in WYSIWYG-Inhalt

Rich-Text-Inhalt in den Feldern `summary` und `body` enthält `<img src="...">`-Tags,
die auf `drupal.org` zeigen. Beim Laden in Quill werden alle `src`-Attribute umgeschrieben,
um den Proxy zu nutzen. Vor dem Speichern stellt `_stripProxyUrls()` in `_editor_quill_bridge.dart`
die kanonischen `drupal.org`-URLs wieder her, sodass die DB immer sauberes, portables HTML speichert.

---

## 10. Android-Build

Die App zielt auf **Android 14 (API 34)**. Zentrale Konfiguration:

### `android/app/build.gradle.kts`
```kotlin
android {
    compileSdk = flutter.compileSdkVersion
    targetSdk = 34   // Android 14 — erforderlich für neue Play-Store-App-Einreichungen
    minSdk = flutter.minSdkVersion
}
```

### `android/app/src/main/AndroidManifest.xml`
```xml
<!-- Erforderlich für alle Netzwerk-Requests auf Android -->
<uses-permission android:name="android.permission.INTERNET"/>

<application
    ...
    android:enableOnBackInvokedCallback="true">  <!-- Predictive Back Gesture (Android 13+) -->
```

`android:enableOnBackInvokedCallback="true"` bindet die App in die Android-13+-
Predictive-Back-Gesture-API ein (die animierte Zurück-Navigations-Vorschau). Ohne dieses Flag
funktioniert das OS weiterhin, gibt aber eine Deprecation-Warnung ab API 33+ aus.

### Die Android-APK bauen
```bash
cd flutter_client
flutter build apk --release
# Ausgabe: build/app/outputs/flutter-apk/app-release.apk
```

---

## 11. Entwickler-Richtlinien

### Keine Farben hartkodieren
Widgets, die `attrs.*`-Farben nutzen, können nicht `const` sein. Das ist beabsichtigt — das Theme ist zur Laufzeit dynamisch.

### `.withValues(alpha:)` statt `.withOpacity()` nutzen
Die Methode `Color.withOpacity()` ist in Flutter 3.x als veraltet markiert. `.withValues(alpha:)` nutzen:
```dart
// Veraltet
attrs.brand600.withOpacity(0.2)

// Korrekt
attrs.brand600.withValues(alpha: 0.2)
```
`alpha` ist ein `double` im Bereich `0.0`–`1.0`, identisch zum alten `opacity`-Parameter.

### Responsives Layout: `Wrap` statt `Row` für Filter-Buttons
Die Dashboard-Filterleiste nutzt ein `Wrap`-Widget, damit Buttons bei schmalen
Viewports (Tablet-Hochformat ~768 px) in eine zweite Zeile fließen, statt zu überlaufen:
```dart
Wrap(
  runSpacing: 10,
  children: [
    _buildFilterBtn(...),
    ...
  ],
)
```
Filter-Zeilen **nicht** in ein `SingleChildScrollView(scrollDirection: Axis.horizontal)` einpacken —
das bricht die Tablet-Hochformat-Nutzbarkeit.

### Konfetti-Controller-Muster
`editor_screen.dart` und `review_screen.dart` nutzen das `confetti`-Package für Feier-Animationen. Der `ConfettiController` wird in `initState` initialisiert und in `dispose` freigegeben. Der Konfetti-Ausbruch wird bei Speichern/Freigeben ausgelöst, und die Navigation wird um 900 ms verzögert, damit die Animation abspielen kann, bevor die Route wechselt. Das Konfetti-Feature lässt sich über den Settings-Screen deaktivieren; die Einstellung vor dem Aufruf von `controller.play()` prüfen.

### Nutzereinstellungen (`ThemeState` / `themeProvider`)

Alle Pro-Nutzer-Einstellungen werden in `ThemeState` gespeichert und via `SharedPreferences` persistiert. Der `ThemeNotifier` lädt sie asynchron in `_loadInitialState()` und stellt für jedes Feld einen typisierten Setter bereit.

| Feld | SharedPreferences-Key | Standard | Beschreibung |
|---|---|---|---|
| `themeId` | `pb-theme` | `'glassy'` | Aktives Farbthema |
| `fontStyle` | `pb-fontStyle` | `'inter'` | UI-Schriftfamilie |
| `confettiEnabled` | `pb-confettiEnabled` | `true` | Konfetti-Animation bei Speichern/Freigeben |
| `largeUi` | `pb-largeUi` | `false` | Größerer Text und Badges |
| `autoAutop` | `pb-autoAutop` | `false` | Auto-Absatzformatierung beim Laden des Review-Screens |
| `bgImageUrl` | `pb-bgImage` | *(abgerufen)* | Unsplash-Hintergrund-URL |

#### Auto-Autop (`autoAutop`)

Wenn `autoAutop` `true` ist, ruft `_fetchData()` in `review_screen.dart` die statische `_autop()`-Methode sowohl für die Summary- als auch die Body-Controller direkt nach dem Laden allen Inhalts auf — vor `setState(() { _loading = false; })`. Das entspricht einem manuellen Klick auf den ¶-Button bei beiden Feldern. Für den automatischen Lauf wird kein Snackbar gezeigt. Die Einstellung hat keinen Effekt, wenn der Inhalt bereits `<p>`-Tags enthält (autop ist idempotent).

### Page-Transitions
`lib/widgets/page_transition.dart` stellt einen geteilten animierten Übergangs-Helper bereit. Bei der Navigation zwischen Screens nutzen, um ein konsistentes Gefühl zu erhalten.

### Dateigrößenlimit
Jede Screen-Datei unter ~500 Zeilen halten. Wächst ein Screen darüber hinaus, Sub-Widgets in ein `widgets/`-Unterverzeichnis neben der Screen-Datei extrahieren.

### Platform-View-Lifecycle
`HtmlElementView`-Widgets werden einmal via `ui_web.platformViewRegistry.registerViewFactory` registriert. Die Factory läuft einmal pro View-Typ pro Session. Die `_active*Div`-statischen Referenzen nutzen, um Inhalt bei Routenwechseln neu zu synchronisieren.

### Flutter analyze ausführen
Vor dem Commit von Flutter-Änderungen:
```bash
wsl -d drupaltv -u drupal -- bash -c "cd /var/www/pb_translation_hub/flutter_client && /home/drupal/flutter/bin/dart analyze 2>&1 | grep -E '^(error|warning)'"
```
Alle Findings der Stufen `error` und `warning` beheben, bevor deployt wird. `info`-Level-Deprecation-
Hinweise werden getrackt, sind aber nicht blockierend.
