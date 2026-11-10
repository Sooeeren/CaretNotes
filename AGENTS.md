# AGENTS.md

Guide for AI coding agents working on CaretNotes. Read this first, then `docs/superpowers/specs/2026-11-08-caretnotes-design.md` (the product spec: what the app must do and why).

## What this is

A handwriting-first notes app for pen and touch, inspired by (not copied from) Samsung Notes. The owner takes class notes with a Samsung S Pen on a Windows laptop. **Windows first; Android comes later from the same Flutter codebase**, so keep everything portable.

The top priorities:
1. **Pen feel:** low lag, pressure, palm rejection.
2. **Never lose notes:** nothing is ever hard-deleted by sync or conflicts; it goes to Recently deleted (30 days).

## Commands

```bash
flutter pub get
flutter analyze                          # must report "No issues found!"
flutter test                             # whole suite must pass (135+ tests)
flutter test test/core/sync_test.dart    # one file
flutter run -d windows                   # debug
flutter build windows --release          # build\windows\x64\runner\Release\caret_notes.exe (+ DLLs + data\ next to it)
dart run tool/seed_demo.dart <dir>/library   # fill a throwaway demo library
powershell -File tool/single_exe/build.ps1   # one-file Windows exe: build\single_exe\CaretNotes.exe (after the release build)
flutter build apk --release              # Android APK (AGP 9.1 / Gradle 9.3.1 / Kotlin 2.4, debug-signed)
flutter test tool/screenshots/readme_screenshots_test.dart   # re-render docs/screenshots/*.png
```

Toolchain: Flutter 3.47 / Dart 3.13 and Visual Studio (2022 Build Tools or newer, C++ workload). Under Flutter 3.47, `pdfrx` must be ≥ 2.12. `win32` 6 returns `Win32Result` (check `.value`) and takes `PCWSTR` (`arena.pcwstr(...)`). Held back by other packages: `desktop_drop` 0.8 (0.9 needs `cross_file` 0.4, `file_selector` still pins 0.3) and `xml` 7.0.1 (`flutter_svg` caps it). The ATL component is **not** installed, so don't add plugins that need ATL (that's why `flutter_secure_storage` was dropped).

### Running against a separate profile

- `CARETNOTES_HOME=<dir>` makes the app use `<dir>` instead of `%APPDATA%\dev.caretnotes\caret_notes`, for tests, demos or a second "device" for sync. **Never test against the user's real library.**
- `caret_notes.exe "--open=<path relative to library>"` opens a note directly in the editor (handy for screenshots).
- To screenshot the app window only (not the whole screen), use Win32 `PrintWindow(hwnd, hdc, 2)` rather than `CopyFromScreen`, which can capture other windows on top.

## Layout

```
lib/core/   pure Dart, NO Flutter widget imports (portable, unit-testable)
  geometry.dart               Vec2, RectD, Affine, rdp, pointInPolygon
  find.dart                   find typed text in a note (markdown-insensitive), for the editor's find bar
  paper.dart                  paper geometry (lines/dots per template, shared by screen + PDF), text-on-lines frames, presets
  model/                      Note, NotePage, Template, elements (StrokeEl/TextEl/ImageEl), FolderMeta
  format/note_codec.dart      .cnote = zip: note.json + assets/<id> + thumb.png
  ink/                        stroke outline, shape recognizer, eraser, selection, paint order
  library/library_store.dart  folders, notes, trash (.trash/), search
  merge/note_merge.dart       three-way merge (base/local/remote) for "Combine both"
  sync/                       SyncEngine + RemoteStore providers (folder, WebDAV, Google Drive), DPAPI SecretStore
  export/                     vector PDF export, PDFium stamping via FFI, system fonts
  atomic_file.dart            replaceFile(): MoveFileEx on Windows (Dart's rename deletes first!)
  settings.dart               AppSettings (JSON)
lib/ui/     Flutter UI
  app.dart, wiring.dart       shell; features plug in through hooks/routes in wiring.dart
  theme.dart                  design tokens (AppTokens: desk, hairline, muted, selectedFill)
  window_chrome.dart          own title bar: CaptionArea (drag), WindowButtons, CaptionStrip
  app_logo.dart               the logo, painted (shared with CaretFlow, source docs/brand/icon.svg)
  home/                       sidebar, folder grid, dialogs
  editor/                     EditorController (state + undo, read mode), CanvasView (input + painting), toolbar.dart (NoteBar on top + floating ToolPill), find_bar, ruler, text boxes, images, PDF cache
  sync/                       SyncController, status tile, conflict dialog
  settings_screen.dart, export_dialog.dart
test/core, test/ui            unit + widget tests
tool/seed_demo.dart           demo data
tool/screenshots/             README screenshots rendered from the real widgets (Windows fonts)
docs/superpowers/             design spec + original implementation plan
```

## Rules that matter

- **`lib/core` must not import Flutter widgets** (only Dart and pure packages). The Android port depends on it.
- **Test-first** for logic changes: write the failing test, watch it fail, then fix. Every bug fix gets a regression test.
- **Licenses:** the project is MIT. No AGPL or commercial-only dependencies (e.g. MuPDF and Syncfusion are out). PDF rendering uses pdfrx (PDFium).
- **Document units are PDF points** (A4 = 595.28 × 841.89; 1 cm = 28.3465 pt). Every page, stroke, text box and image has a stable UUID `id`; merging relies on it.
- **Note file format** (`.cnote`): bump `Note.formatVersion` and keep reading old files if you change `note.json`. `decodeNote` must throw `NoteFormatException` on bad input; the home screen shows such files as "damaged" instead of crashing.
- **Saving:** always atomic (temp file + `replaceFile`). The editor autosaves 1.5 s after changes, and also on close, hide and app exit. `EditorController.save()` checks whether the file changed on disk since loading. If it did, the other version goes to Recently deleted before overwriting.
- **Sync** (`SyncEngine`):
  - It compares local hash and remote token against stored base copies in `<library>/.sync/`.
  - An edit always beats a delete.
  - When both sides edited a note, it's queued as a `PendingConflict` that only the user resolves (combine / keep this / keep other / keep both).
  - Notes open in the editor are skipped (`isOpen` callback, checked per file).
  - Conflict copies from sync clients (Proton `(# Name clash … #)`, Dropbox `(… conflicted copy …)`, OneDrive `-HOST`) are only treated as copies when the **note id matches**.
  - Half-written zips are skipped.
  - Changing provider cancels the running engine and resets state.
- **Text on lines:** a `TextEl` with `lineHeight` set is typed on the paper's lines (`TextMode.lines`); without it, it's a free text box. Every line of ruled text is exactly `lineHeight` tall (forced strut) and shifted so baselines sit on the ruled lines (`ruledBaselineShift`). The screen widget, the painter and the PDF export must agree; moves snap to the lines and template changes refit it (`fitTextToLines`).
- **Paper:** add new kinds in `lib/core/paper.dart` (`paperGeometry`), never separately in the painter and the PDF export. Format 2 added `cornell`/`staff` and `lh`; unknown kinds read as lined.
- **Palm rejection** (`InputRouter`): touches are ignored while the pen is down or hovering, and within 500 ms after it lifts. Touches already down when the pen arrives are cancelled. Highlighters always paint under ink (`paintOrder`).
- **Editor layout (Samsung Notes–style split):** note actions live in the top `NoteBar`; only drawing tools go in the `ToolPill`. Each tool's settings (type, size, colors) belong in its tap-again panel (`tool_options.dart`), not in the bar. Insert things via the `+` menu, page actions via the pages button; keep `⋮` short.
- **Sister app CaretFlow** (`Sooeeren/CaretFlow`, local folder `folio`): same logo (`docs/brand/icon.svg`, `app_icon.ico`, Android `ic_launcher.png` are copies of CaretFlow's) and the same window chrome. On Windows there is no system title bar (`window_manager`, `TitleBarStyle.hidden`): every screen's header wraps its row in `CaptionArea` and ends with `WindowButtons` (46 px Fluent glyph buttons, red close hover); `CaptionStrip` (a 34 px "Title — CaretNotes" bar) is there for any future screen without a top header. Close goes through `WindowChrome.requestClose` (exit request, so the editor saves). Settings → "Use the system title bar" turns it off. CaretNotes keeps its own, more playful look otherwise.
- **UI style (calm "paper and ink"):** graphite neutrals and one restrained accent (default `#D9772B`), used only for the active tool and the primary action. Thin outlined Material icons, never `*_rounded`. Corner radii 8–10, Segoe UI Variable, colors from `AppTokens`/`ColorScheme` rather than hard-coded. No emoji as icons.

## Gotchas

- **Some Material icons vanish in release builds** (icon tree-shaking drops their glyphs; e.g. `keyboard_outlined`, `chrome_reader_mode_outlined`) while tests and debug show them. After adding an icon, check the release exe.
- **A release build fails with `LNK1104`** when `caret_notes.exe` is running. Close the app first.
- **In widget tests, file IO must run inside `tester.runAsync`.** Futures started in the fake clock never complete.
- `PdfPageCache` evicts and disposes images (LRU, 24 pages). Don't keep `ui.Image` references from it across frames.
- `PdfiumStamper` calls PDFium directly on the main isolate, while pdfrx renders on its own worker. Avoid exporting while pages are rendering.
- Google Drive needs a user-supplied OAuth desktop client (docs/SYNC.md explains). There are no automated Drive tests, so verify Drive changes by hand.

## Known open issues (deferred, good next tasks)

- PDF pages render at most 3000 px, so they blur above roughly 4–5× zoom (needs tiled rendering).
- With "draw with finger" on, two-finger pan/zoom and ruler moves don't work.
- A selection dragged past a page edge stays on its page and gets clipped.
- `SyncEngine._record` stats the file after reading it, so an edit landing in between can be marked as synced.
- The conflict dialog has no busy guard (a double tap can throw).
- An expired Google token shows a raw error instead of "sign in again". Each engine rebuild leaks an `http.Client`.
- Google Drive can end up with duplicate same-name files if two devices create the same path.
- Merged notes never drop unused assets.
- Markdown checkboxes can't be ticked by tapping; you edit `[ ]` → `[x]`.
- Android port: needs its own secret store (DPAPI is Windows-only) and a Proton Drive route (the Android client has no synced folder).

## Working with the owner

The owner (they/them) prefers plain-language updates and is fine with the agent making sensible calls. Ask only when a decision really changes what gets built. Commit with clear messages; push to `origin main` (private GitHub repo `Sooeeren/CaretNotes`) only when asked.
