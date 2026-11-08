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
flutter test                             # whole suite must pass (115+ tests)
flutter test test/core/sync_test.dart    # one file
flutter run -d windows                   # debug
flutter build windows --release          # build\windows\x64\runner\Release\caret_notes.exe (+ DLLs + data\ next to it)
dart run tool/seed_demo.dart <dir>/library   # fill a throwaway demo library
```

Toolchain: Flutter 3.32 / Dart 3.8 and Visual Studio 2022 Build Tools (C++ workload). The ATL component is **not** installed, so don't add plugins that need ATL (that's why `flutter_secure_storage` was dropped).

### Running against a separate profile

- `CARETNOTES_HOME=<dir>` makes the app use `<dir>` instead of `%APPDATA%\dev.caretnotes\caret_notes`, for tests, demos or a second "device" for sync. **Never test against the user's real library.**
- `caret_notes.exe "--open=<path relative to library>"` opens a note directly in the editor (handy for screenshots).
- To screenshot the app window only (not the whole screen), use Win32 `PrintWindow(hwnd, hdc, 2)` rather than `CopyFromScreen`, which can capture other windows on top.

## Layout

```
lib/core/   pure Dart, NO Flutter widget imports (portable, unit-testable)
  geometry.dart               Vec2, RectD, Affine, rdp, pointInPolygon
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
  home/                       sidebar, folder grid, dialogs
  editor/                     EditorController (state + undo), CanvasView (input + painting), toolbar, ruler, text boxes, images, PDF cache
  sync/                       SyncController, status tile, conflict dialog
  settings_screen.dart, export_dialog.dart
test/core, test/ui            unit + widget tests
tool/seed_demo.dart           demo data
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
- **Palm rejection** (`InputRouter`): touches are ignored while the pen is down or hovering, and within 500 ms after it lifts. Touches already down when the pen arrives are cancelled. Highlighters always paint under ink (`paintOrder`).
- **UI style (calm "paper and ink"):** graphite neutrals and one restrained accent (default `#D9772B`), used only for the active tool and the primary action. Thin outlined Material icons, never `*_rounded`. Corner radii 8–10, Segoe UI Variable, colors from `AppTokens`/`ColorScheme` rather than hard-coded. No emoji as icons.

## Gotchas

- **A release build fails with `LNK1104`** when `caret_notes.exe` is running. Close the app first.
- **In widget tests, file IO must run inside `tester.runAsync`.** Futures started in the fake clock never complete.
- `PdfPageCache` evicts and disposes images (LRU, 24 pages). Don't keep `ui.Image` references from it across frames.
- `PdfiumStamper` calls PDFium directly on the main isolate, while pdfrx renders on its own worker. Avoid exporting while pages are rendering.
- Google Drive needs a user-supplied OAuth desktop client (README explains). There are no automated Drive tests, so verify Drive changes by hand.

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
- The `pubspec.yaml` description is still the Flutter default.
- Android port: needs its own secret store (DPAPI is Windows-only) and a Proton Drive route (the Android client has no synced folder).

## Working with the owner

The owner (they/them) prefers plain-language updates and is fine with the agent making sensible calls. Ask only when a decision really changes what gets built. Commit with clear messages; push to `origin main` (private GitHub repo `Sooeeren/CaretNotes`) only when asked.
