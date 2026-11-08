# CaretNotes — Design

Date: 2026-11-08
Status: Draft for approval

## 1. Intent

A handwriting-first note-taking app inspired by Samsung Notes: similar in feel, not a pixel copy. The owner uses it to take notes **in class, mostly by hand with a Samsung S Pen**, usually on blank templated pages (lined, grid) and sometimes on top of PDFs.

The main workflow: **write on the tablet in class, then open the same note on the desktop with no sharing step**. Sync goes through ordinary cloud storage.

**Platforms:** Windows first, to test and refine the app. Android follows later from the same codebase, so every decision now must keep the Android port cheap.

**Devices:** day to day, handwriting happens on a tablet, and the desktop is mostly for opening and reviewing notes. During the Windows phase, the owner writes with the S Pen on their Windows laptop. That laptop is the reference device for pen feel and the test hardware. The owner wants writing on the laptop to stay a fully supported option, not just a stopgap. The full tablet-to-desktop workflow only arrives with the Android port. Until then, sync is tested between Windows machines.

**What makes or breaks it:** the pen experience. If writing feels laggy, imprecise or clumsy, the app has failed, however many features it has.

## 2. Goals

1. Pen writing that feels as good as Samsung Notes on a Galaxy Book with the S Pen: low lag, pressure, palm rejection, side-button shortcuts.
2. The pen tools described in §5, including the ruler that Samsung Notes is missing.
3. Three note layouts: paged, endless vertical, and infinite canvas.
4. Typed text with live Markdown, plus images.
5. PDF import and annotation, plus PDF and image export.
6. Nested, colored folders with icons.
7. Offline-first sync to Google Drive and to any locally synced folder (Proton Drive, OneDrive, Dropbox desktop clients), with user-controlled conflict resolution.

## 3. Non-goals (for this version)

- **Audio recording** (the owner said explicitly that nobody needs it).
- Reading or writing Samsung Notes' own file format (`.sdocx`).
- Real-time collaboration or sharing with other people.
- Searching inside handwriting (handwriting recognition). Possible later; the file format should not rule it out.
- An Android build. The architecture must make it straightforward, but it isn't shipped now.
- macOS, Linux, iOS.

## 4. Anti-goals (would count as failure even if everything technically works)

- Noticeable lag or jitter between the pen tip and the ink.
- Losing notes: through sync, conflicts, crashes or accidental deletes.
- Lower-quality PDF exports (blurry raster ink, rasterized imported PDFs).
- A UI that's an exact copy of Samsung Notes. It should be inspired by it, not cloned.
- Building an app that can't reasonably be ported to Android.

## 5. Pen and editing tools

**Input**
- Pen pressure controls stroke width (and opacity where it fits the pen type). Tilt support is optional, the builder's call.
- Palm rejection: while the pen is in range or touching, touch input never draws.
- Fingers scroll, pinch-zoom and pan. My call: a setting allows finger drawing for people without a pen; off by default.
- S Pen side button: hold for a temporary eraser while pressed (default); configurable to lasso instead.
- Undo/redo (toolbar plus Ctrl+Z / Ctrl+Y), with a deep history per note session.

**Tools**
- **Pens:** several styles (at least a fountain/ballpoint-style pressure pen, a fine pen and a pencil-like texture), color palette with custom colors and saved favorites, adjustable size.
- **Highlighter:** translucent and drawn *behind* ink so writing stays readable, with several preset colors. Owner: "being able to mark stuff is VERY important."
- **Eraser:** whole-stroke mode and partial (pixel-like, splits strokes) mode, adjustable size.
- **Hold-to-straighten:** draw a line and keep the pen still for a short moment at the end; it snaps to a straight line. Before lifting the pen you can still move the end point, as in Samsung Notes.
- **Auto shapes:** the same hold gesture turns a rough rectangle/square, circle/ellipse, triangle or arrow into a clean shape. Works with pen and highlighter.
- **Ruler (the feature Samsung is missing):** an on-screen ruler placed, moved and rotated with two fingers. The current angle is shown, and it snaps to 0/45/90°. Ink drawn near its edge sticks to that edge. It shows centimeter marks for measuring. A protractor is a nice-to-have for later.
- **Selection:** freehand lasso **and** rectangle (box) select. Selected items (ink, text boxes, images) can be moved, resized, rotated, recolored, copied/pasted, duplicated or deleted.
- **Text tool** and **image tool:** see §7.

## 6. Notes, pages and templates

**Three layouts, chosen when a note is created:**
1. **Paged:** A4 or Letter, portrait or landscape. Pages can be added, deleted, duplicated and reordered, with a page overview strip.
2. **Endless:** one page of fixed width that grows downward as you write.
3. **Canvas:** infinite in every direction, like OneNote or a whiteboard. Zooms from far out (to see everything) to very close.

My call: an existing note can switch between paged and endless. Switching to or from canvas isn't required.

**Templates:** blank, lined, grid, dot grid. Line or grid spacing and paper color (including a dark paper) are adjustable. Templates are set per note, with an option to override a single page. On a canvas the template pattern repeats across the whole area.

**PDF import:** each PDF page becomes a note page you can write on. It stays sharp at any zoom, because the PDF is rendered as vector, not as a fixed bitmap. Blank pages can be inserted between PDF pages.

## 7. Typed text and images

**Text boxes** go anywhere on a page and can be moved and resized like other objects; lasso and box select pick them up.

**Live Markdown** (Obsidian/Typora style): syntax renders as you type, and the raw syntax shows again on the line being edited. Supported: headings, bold, italic, strikethrough, bullet and numbered lists, checkboxes, inline code, code blocks with syntax highlighting, block quotes, tables, links, and **LaTeX math** (`$…$` inline, `$$…$$` block). A small formatting toolbar is available for people who don't want to type syntax.

**Images:** add from a file, by pasting from the clipboard, or by drag-and-drop. Move, resize, rotate and crop. Images can sit behind the ink so you can write on them. They're stored inside the note, so they sync with it. On Android later, a "take a photo" button (for the whiteboard).

## 8. Export

- **PDF:** the whole note or selected pages. Ink is exported as vector paths, typed text stays real, selectable text, and imported PDF pages keep their original quality. Endless notes are split into A4 pages. Canvas notes export the area that's in use, either as one large page or tiled into A4 sheets (user's choice).
- **Image:** PNG or JPG, one image per page, or of a selection, at a chosen resolution.
- Export uses the system share/save dialog.

## 9. Organization

- Nested folders, any depth. A folder can hold subfolders and notes side by side.
- Each folder has a name, a color and an optional icon from a built-in set.
- Sorting by name, date created, date edited, or manual drag order. My call: the sort is set per folder.
- Move by drag-and-drop or "Move to…", with multi-select.
- Favorites/pinning, Recent, and search by title (and by typed text, which is cheap to add since it's real text). My call: Recently Deleted keeps items for 30 days.
- The folder structure maps directly to folders in the cloud storage.

## 10. UI

Inspired by Samsung Notes: soft, rounded, light, friendly. Not a copy of its icons or exact layout.

**Home screen** (combines both mockup options, as the owner chose):
- **Sidebar:** Recent, Favorites, expandable folder tree, Recently Deleted, and sync status with "Sync now" at the bottom. Can collapse to an icon strip or hide entirely. Hides automatically on narrow windows (for phones later).
- **Main area:** the current folder shows subfolders as colored icon tiles first, then notes as thumbnails of their first page. Tap a tile to go in. A breadcrumb trail at the top goes back up. Clicking a folder in the sidebar jumps straight there.
- **Top bar of the main area:** search, sort menu, grid/list toggle, and "+" for a new note (paged / endless / canvas) or a new folder.
- **Context menu** (long-press or right-click): rename, color/icon, favorite, move, duplicate, export, delete.

**Editor:**
- The tool toolbar sits at the **top by default**. **Long-press and drag** it to dock it to the left or right side, or let it float anywhere. All three positions are full options for the user. The position is remembered.
- The toolbar shows back, note title, tools (pen, highlighter, eraser, lasso/box select, ruler, text, image), undo/redo, and a more-menu. A second row or popover shows the colors and size for the active tool.

**Theme:** light and dark mode that follow Windows by default, and one accent color the user can change (default orange).

Mockups from the brainstorming session are in `.superpowers/brainstorm/`. They're rough wireframes for layout only, not visual specs.

## 11. Sync

**Principles**
- Offline-first: the app always works offline, and every change is saved on the device first.
- Sync runs when a note is closed, every few minutes while one is open, at app start, and from "Sync now".
- Notes must never be lost by sync. Anything overwritten or discarded goes to Recently Deleted.

**Providers (Windows, first version)**
- **Google Drive:** in-app sign-in, using the official API. Works on Android later too.
- **Local synced folder:** the user picks a folder that a desktop sync client (Proton Drive, OneDrive, Dropbox…) already syncs, and the app reads and writes there. This is how Proton Drive is supported on Windows, because Proton Drive has no official public API.
- **WebDAV** (my call: it covers Nextcloud and similar services cheaply).
- Providers sit behind a common interface so more can be added.
- **One provider per library at a time** (my call). Switching provider in settings is a one-way move of the library to the new location. Each note keeps a single "last common sync point".
- **Priority:** the owner prefers Proton Drive and is fine with Google Drive. So the **local synced folder via the Proton Drive desktop client is the first provider to build and test against**, with Google Drive second and WebDAV third. The folder provider has to cope with how sync clients behave: changes arrive late, files are replaced whole, partial files can appear mid-upload, and the client may create its own "conflict copy" files. The app must detect and absorb those, not show them as stray notes.
- **Known risk:** Android has no synced folder from the Proton Drive client. Proton Drive on Android will need an unofficial route (for example the protocol behind rclone's Proton Drive support), or the owner switches to Google Drive at that point. Decide when the Android port starts. It doesn't block the Windows phase.

**Conflicts (same note changed in two places before syncing)**
The app detects the conflict and asks the user, showing a preview of both versions:
1. **Combine both:** keep every addition from both sides. New pages from both devices are kept in order; additions to the same page stay where they were written. If one side erased an item the other side didn't change, the erase wins. If both sides changed the same item (rare, e.g. both moved the same text box), my call is to keep both copies of that item.
2. **Keep tablet version** / **keep desktop version** (labelled with device names).
3. **Keep both as separate notes** (e.g. "VL 4 (desktop copy)").

The version not chosen goes to Recently Deleted. Folder changes (create, rename, move, color) merge automatically. My call: if a folder was deleted on one side while a note in it was edited on the other, the edited note is kept and the folder restored.

To support "combine both", every object in a note (stroke, text box, image, page) needs a stable unique ID and enough change tracking to tell additions, edits and deletes apart since the last common sync point.

## 12. How it's built (decided)

- **Flutter** (Dart), with targets for Windows now and Android later from one codebase. Ink rendering goes through Flutter's own canvas, so pressure and stylus handling behave the same on both platforms. (Claude's call; the owner agreed.)
- **Own open file format**, not Samsung's. My call: each note is one file (a zip-style container) holding the structured note data, embedded images and imported PDFs. Folders are real folders, and folder metadata (color, icon, sort) is stored in a small file inside each folder. This keeps sync simple and cloud files readable.
- The app is named **CaretNotes** (from the project folder; my call).

## 12a. Distribution and licensing (owner decided)

- Open source on GitHub, with no app store releases and no public package listings. Users build it themselves or grab a release zip from GitHub.
- **Google Drive sign-in:** the app ships without a shared Google client ID. Each user creates their own Google Cloud OAuth client (desktop type) and enters its ID in settings, with a step-by-step guide in the README. Use the narrowest scope that works (`drive.file`, limited to the app's own folder). Known limitation: an OAuth client left in "testing" mode has refresh tokens that expire after about 7 days, so the app has to handle re-sign-in smoothly. My call; no Google verification needed.
- **License:** my call is MIT. All dependencies must be compatible with it, so no AGPL or commercial-only libraries (for example, use PDFium-based PDF rendering rather than MuPDF or Syncfusion).
- No code signing, installer or auto-update in this version. A portable zip or an unsigned MSIX is fine.

## 13. Left to the builder

- State management, persistence library, package choices.
- The exact schema of the note format and the change-tracking method that makes merging possible (§11).
- Stroke smoothing algorithm, rendering strategy for low latency (e.g. live layer for the active stroke, cached tiles for finished ink), and Windows pen API specifics if Flutter's built-in stylus input turns out to fall short (a native Windows Ink plugin is acceptable).
- Shape recognition approach and hold-gesture timing values (tuned by feel).
- PDF rendering and PDF writing libraries.
- Markdown/LaTeX rendering approach.
- Icon set, exact colors, typography, within §10.
- Sync interval, retry and backoff behavior.
- Build order and how to split the work into milestones. The builder may cut the first milestone down to pen + pages + folders + local storage, as long as the format already supports merging.
