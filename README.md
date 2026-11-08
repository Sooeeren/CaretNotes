# CaretNotes

A handwriting-first note app for pen and touch, inspired by Samsung Notes. Windows first, Android later (same Flutter codebase).

- **Pen:** pressure-sensitive pen, fineliner and pencil; highlighter that stays behind your writing; whole-stroke and partial eraser; S Pen side button (hold for eraser or selection); palm rejection.
- **Hold to straighten:** keep the pen still at the end of a line and it snaps straight. Rough rectangles, circles, triangles and arrows become clean shapes. Keep moving the pen before lifting to adjust.
- **Ruler:** move and rotate it with two fingers (snaps to 0°/45°/90°, shows the angle and cm marks). Lines drawn near its edge stick to it.
- **Selection:** freehand lasso or box. Move, resize, rotate, recolor, copy, paste, duplicate, delete, or save as an image.
- **Three layouts:** pages (A4/Letter), one endless page, or an infinite canvas.
- **Paper:** blank, lined, grid, dots; adjustable spacing; white, cream, mint or dark paper. Set it for a whole note or a single page.
- **Typed text with live Markdown:** headings, bold, italic, lists, checkboxes, code with highlighting, tables, quotes, links and LaTeX math (`$x^2$`).
- **Images:** insert from a file, paste (Ctrl+V) or drag in. Move, resize, rotate, crop, put behind the ink.
- **PDF:** import lecture slides and write on them, add blank pages in between.
- **Export:** PDF (vector ink, real text, imported PDFs at original quality) or PNG/JPG.
- **Folders:** nested, with colors and icons, sortable, drag and drop. Favorites, Recent, search, and Recently deleted (30 days).
- **Sync, offline-first:** Proton Drive / OneDrive / Dropbox (through their desktop sync folder), Google Drive, or WebDAV (Nextcloud). When a note changed on two devices you choose: combine both, keep one, or keep both.

## Build and run (Windows)

1. Install [Flutter](https://docs.flutter.dev/get-started/install/windows) (3.32 or newer) and Visual Studio 2022 Build Tools with the **Desktop development with C++** workload.
2. In this folder:
   ```
   flutter pub get
   flutter run -d windows            # debug
   flutter build windows --release   # build\windows\x64\runner\Release\caret_notes.exe
   ```
3. To share a build, zip the whole `build\windows\x64\runner\Release` folder. The `.exe` needs the DLLs and the `data` folder next to it.

Run the tests with `flutter test`.

Notes are stored in `%APPDATA%\dev.caretnotes\caret_notes\library` (Settings → Device & storage shows the exact path). Each note is one `.cnote` file, a zip with `note.json`, embedded images/PDFs and a thumbnail.

> Don't keep the project folder itself inside a synced cloud folder while building. Sync clients like Proton Drive can rename build files mid-build ("Name clash" copies).

## Sync setup

Sync runs when the app starts, every 3 minutes, when you close a note, and when you press **Sync now** in the sidebar. You can always write offline.

### Proton Drive (or OneDrive / Dropbox)

1. Install the provider's Windows app and sign in.
2. Create a folder inside the synced drive, e.g. `Proton Drive\CaretNotes`.
3. CaretNotes → Settings → Sync → **Synced folder** → choose that folder.
4. On every other computer, choose the same folder.

CaretNotes writes its files there and the Proton Drive app uploads them. If the Proton Drive app creates its own "Name clash" copies, CaretNotes recognizes them and asks you how to merge them.

> Android: the Proton Drive Android app doesn't offer a synced folder, so Proton sync on Android will need another route. That will be decided when the Android version is built. Google Drive and WebDAV will work there directly.

### Google Drive

Google requires every app that isn't in a store to have its own sign-in client. It's free and takes about 5 minutes:

1. Open <https://console.cloud.google.com/>, create a project (any name).
2. **APIs & Services → Library**: enable **Google Drive API**.
3. **APIs & Services → OAuth consent screen**: choose *External*, fill in the app name and your email, add yourself as a **test user**.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** → application type **Desktop app**.
5. Copy the **Client ID** and **Client secret** into CaretNotes → Settings → Sync → Google Drive, then press **Sign in with Google**.

CaretNotes only gets access to the files it creates (`drive.file` scope), stored in a `CaretNotes` folder in your Drive. While the Google app is in "Testing" mode, Google signs you out about once a week. Press *Sign in* again when the sidebar asks. Publishing the consent screen removes that limit.

### WebDAV (Nextcloud, ownCloud, NAS)

Enter the folder's WebDAV address (Nextcloud: `https://<server>/remote.php/dav/files/<user>/CaretNotes`), your user name and an app password. The password is stored encrypted with Windows DPAPI.

## Keyboard shortcuts in a note

| Keys | Action |
| --- | --- |
| Ctrl+Z / Ctrl+Y (or Ctrl+Shift+Z) | Undo / redo |
| Ctrl+C / Ctrl+X / Ctrl+V | Copy / cut / paste (also pastes images and text from other apps) |
| Ctrl+D | Duplicate selection |
| Delete | Delete selection |
| Ctrl+= / Ctrl+- / Ctrl+0 | Zoom in / out / fit width |
| Ctrl+mouse wheel | Zoom; wheel scrolls; Shift+wheel scrolls sideways |
| Ctrl+S | Save now (it also saves automatically) |

Fingers scroll and pinch-zoom. Turn on **Draw with finger** if you have no pen. Hold the toolbar to drag it to the left or right side, or let it float.

## Project layout

```
lib/core/     platform-independent logic: model, file format, ink geometry, merge, sync, PDF export
lib/ui/       Flutter UI: home screen, editor, sync, settings, export
test/         unit and widget tests
docs/         design and implementation plan
```

## License

MIT, see [LICENSE](LICENSE).
