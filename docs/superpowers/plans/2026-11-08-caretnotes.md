# CaretNotes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A handwriting-first Flutter notes app for Windows (Android-ready) with pen tools, three note layouts, Markdown text, images, PDF import/export, nested folders and offline-first sync with three-way merge.

**Architecture:** Pure-Dart core (`lib/core/`: model, geometry, storage, merge, sync) with no Flutter widget imports, so it can be unit-tested and reused unchanged on Android. Flutter UI (`lib/ui/`) on top, using `ChangeNotifier` controllers exposed with `provider`. Notes are zip containers (`.cnote`) inside real folders. A local library is the working copy, and sync reconciles it with one remote store at a time, using stored base copies for three-way merge.

**Tech Stack:** Flutter 3.32 / Dart 3.8, provider, archive, uuid, path, path_provider, file_selector, pdfrx (PDFium, BSD-3), pdf (Apache-2), image (MIT), googleapis + googleapis_auth, http, url_launcher, flutter_secure_storage, pasteboard, desktop_drop, flutter_markdown_plus, flutter_math_fork, highlight.

**Spec:** `docs/superpowers/specs/2026-11-08-caretnotes-design.md`

## Global Constraints

- Document units are PDF points (1/72 in). A4 = 595.28 × 841.89, Letter = 612 × 792. 1 cm = 28.3465 pt.
- `lib/core/**` must not import Flutter widget libraries; it uses its own `Vec2`/`RectD` types.
- Every note object (page, stroke, text box, image) has a stable UUID v4 `id`.
- No AGPL or commercial-only dependencies (MIT project license).
- Nothing is ever hard-deleted by sync or conflict resolution: it goes to Recently Deleted (`.trash/`), kept 30 days.
- One sync provider per library at a time.
- Google Drive uses scope `https://www.googleapis.com/auth/drive.file` and a user-supplied desktop OAuth client ID.
- Highlighter strokes render beneath all pen strokes on the same page.
- Default toolbar dock: top. Default accent: orange `#FF8A1F`. Theme follows system by default.

## Review Focus

1. A sync client leaves a half-written `.cnote` in the synced folder → the app skips it this round (invalid zip), never imports or overwrites with it.
2. A sync client creates its own conflict copy (`Note (conflicted copy).cnote`, `Note-DESKTOP-ABC.cnote`, `Note (# Name clash …).cnote`) → it's treated as a remote version of the original note and queued as a conflict, not shown as a stray note.
3. Corrupt or unreadable note file in the library → the home screen still loads and the note shows as "damaged", without crashing.
4. Touch while the pen is down or hovering → never draws or erases (palm rejection), even when finger drawing is enabled.
5. A note deleted on one device while it was edited on another → the edited version survives, with its folder restored.

Each item has a test in the task that owns it (Tasks 3, 9, 4, 6, 9).

---

## File Structure

```
lib/
  main.dart                       app bootstrap, providers
  core/
    geometry.dart                 Vec2, RectD, Affine, polygon math, RDP simplify
    ids.dart                      newId()
    model/                        elements.dart, page.dart, note.dart, folder_meta.dart
    format/note_codec.dart        encode/decode .cnote zip (note.json, assets/, thumb.png)
    ink/                          stroke_geometry, shape_recognizer, eraser, selection
    library/library_store.dart    folder tree, CRUD, trash, favorites, recent, search
    merge/note_merge.dart         three-way merge (base, local, remote)
    sync/                         remote_store, folder_remote, webdav_remote, gdrive_remote,
                                  sync_engine, sync_state
    export/                       pdf_export, image_export (render via ui layer)
    settings.dart                 AppSettings + JSON persistence
  ui/
    app.dart, theme.dart
    home/                         home_screen, sidebar, folder_grid, dialogs
    editor/                       editor_screen, editor_controller, canvas_view, painters,
                                  toolbar, tool_options, ruler, text_box, image_box, page_strip
    sync/                         sync_controller, conflict_dialog
    settings_screen.dart
test/                             mirrors lib/core + controller tests
```

---

### Task 1: Project scaffold, geometry, model, codec

**Produces:** `Vec2`, `RectD`, `Affine`, `rdp(points, eps)`, `pointInPolygon(p, poly)`; sealed `Element` (`StrokeEl`, `TextEl`, `ImageEl`) with `id`, `bounds()`, `transformed(Affine)`, `toJson/fromJson`; `NotePage {id,width,height,templateOverride,pdf,elements}`; `Note {id,title,layout,paper,landscape,template,pages,created,modified,modifiedBy,favorite,assets}`; `encodeNote(Note,{thumb})`, `decodeNote(bytes)` throws `NoteFormatException`, `readThumb(bytes)`.

- [ ] git init, flutter create (windows, android), deps, `.gitignore` with `.superpowers/`.
- [ ] Tests: rdp straight line → 2 pts; pointInPolygon; codec round-trip (stroke, text, image asset) JSON-equal; garbage → `NoteFormatException`.
- [ ] Implement → `flutter test` green → commit.

### Task 2: Ink geometry, shapes, eraser, selection

**Produces:** `strokeOutline(points, width, tool)`; `recognizeShape(points) → RecognizedShape? {kind: line|rect|ellipse|triangle|arrow, points}`; `eraseStroke(stroke, center, radius) → List<StrokeEl>`; `lassoHits(elements, polygon)`, `boxHits(elements, rect)`.

- [ ] Tests: jittered line → line; jittered square → rect; circle → ellipse; triangle → triangle; scribble → null; erasing middle splits in 2; lasso picks only enclosed stroke (≥ 50 % points).
- [ ] Implement → green → commit.

### Task 3: Library store, folders, trash

**Produces:** `LibraryStore(rootDir)` with `tree()`, `listFolder(relDir)`, `createNote`, `loadNote`, `saveNote`, `rename`, `move`, `duplicate`, `createFolder`, `setFolderMeta`, `trashItem`, `listTrash`, `restore`, `purgeOlderThan`, `recent`, `favorites`, `search`. `NoteEntry {relPath,title,modified,favorite,damaged}`; folder meta in `<dir>/.folder.json`; dot-names ignored; unique names get ` (2)`.

- [ ] Tests: nested folders listed folders-first; trash → restore round-trip; purge > 30 days; **corrupt note → `damaged: true`, no throw** (RF 3); search hits title and text.
- [ ] Implement → green → commit.

### Task 4: Three-way note merge

**Produces:** `mergeNotes({base, local, remote}) → Note`. Added on either side → kept. Missing on one side & unchanged on other → deleted. Missing on one side & changed on other → kept. Changed differently on both → keep local, remote copy with new id. Page order: local order, remote-only pages inserted after nearest preceding remote page. Note fields: later `modified` wins. Assets union.

- [ ] Tests: one per rule, page order, base null → union.
- [ ] Implement → green → commit.

### Task 5: Settings, shell, theme, home screen

**Produces:** `AppSettings` (themeMode, accent, fingerDrawing=false, sideButton eraser|lasso, toolbarDock, floatingPos, sync provider + config, deviceName) JSON-persisted; `LibraryController` (ChangeNotifier). Home: sidebar (Recent, Favorites, tree, Recently Deleted, sync status/Sync now; rail < 900 px, drawer < 600 px), breadcrumbs, search, sort, grid/list, "+" menu, folder tiles then note thumbnails, context menu, drag-drop to folders.

- [ ] Widget test: folder tile + note card render; tapping folder updates breadcrumbs.
- [ ] Implement → green → commit.

### Task 6: Editor canvas, pen input, tools, undo

**Produces:** `EditorController` (tool state, strokes, erase, ops with undo/redo, autosave 1.5 s debounce + on close, viewport). `CanvasView` routes via `Listener`: stylus → tool, invertedStylus → eraser, stylus + secondary button → side-button action, touch → pan/pinch (draws only if fingerDrawing and no stylus in last 500 ms), mouse → draw/pan/Ctrl+wheel zoom. Live stroke on its own repaint layer; committed ink cached as `ui.Picture` per page. Layouts paged/endless/canvas.

- [ ] Tests: stroke add; undo/redo; **touch while stylus active → no stroke** (RF 4); highlighters paint before pens.
- [ ] Implement → green → commit.

### Task 7: Hold-to-shape, ruler, selection tools, toolbar docking

Hold: still ≤ 4 px for 450 ms → shape/line; further motion moves end point / scales from anchor. Ruler: 20 cm, two-finger move/rotate, snap 0/45/90 within 3°, angle label, cm/mm ticks, pen within 18 pt of edge projects onto it. Selection: lasso + box, move/scale/rotate, action bar (color, duplicate, copy, paste, delete). Toolbar: long-press drag; dock top/left/right or float; persisted.

- [ ] Tests: ruler projection; 44° → 45°; selection move; delete undoable.
- [ ] Implement → green → commit.

### Task 8: Text (live Markdown), images, PDF import, pages, templates

`MarkdownEditingController` styles syntax live; unfocused boxes render with flutter_markdown_plus + math + highlighted code; checkboxes toggle. Images via picker/paste/drop, move/resize/rotate/crop, behind-ink. PDF import via pdfrx, each page a `NotePage` with `PdfRef`. Page strip add/delete/duplicate/reorder/insert blank. Template picker per note/page; switch paged ↔ endless.

- [ ] Test: `**x**` → bold span; `# h` → larger font.
- [ ] Implement → green → commit.

### Task 9: Sync engine and providers

**Produces:** `RemoteStore {listAll, read, write → token, delete}`; `SyncEngine(library, remote, state).run() → SyncReport`; `resolve(conflict, Resolution)`. Bases in `.sync/base/`. Conflict-copy detection (Dropbox, OneDrive host suffix, Proton name clash, generic "conflict"). Invalid remote zip skipped. `.folder.json` newer wins. Deleted-vs-modified keeps modified. Unresolved conflicts persist. Providers: synced folder, WebDAV (PROPFIND depth 1, ETag), Google Drive (loopback OAuth, refresh token in secure storage, md5 token). Triggers: start, note close, 3 min, Sync now. Conflict dialog with thumbnails & four choices.

- [ ] Tests: upload, download, conflict + combine, **partial file skipped** (RF 1), **conflict copy → conflict** (RF 2), **remote delete + local edit keeps local** (RF 5), keep-remote trashes local.
- [ ] Implement → green → commit.

### Task 10: Export, settings screen, README, Windows build

PDF: vector stroke outlines, real text (Segoe UI from Windows fonts, fallback Helvetica), images, PDF pages embedded (fallback 300 dpi). Endless → A4 slices; canvas → one page or A4 tiles. Image export PNG/JPG, 1–4×. README with build, Google OAuth and Proton folder setup. MIT LICENSE.

- [ ] Test: export starts with `%PDF`; 2000 pt endless → 3 pages.
- [ ] `flutter build windows --release` succeeds; smoke-test; commit.
