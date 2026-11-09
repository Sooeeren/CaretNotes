# Building CaretNotes

CaretNotes is a Flutter app. Windows is the first target; Android will be built from the same code later.

## What you need

- [Flutter](https://docs.flutter.dev/get-started/install/windows) (stable; developed with 3.47)
- Visual Studio 2022 or newer (or just its Build Tools) with the **Desktop development with C++** workload

## Build and run

```
flutter pub get
flutter run -d windows            # debug
flutter build windows --release   # build\windows\x64\runner\Release\caret_notes.exe
```

The `.exe` there needs the DLLs and the `data` folder next to it. To share a build as **one file**:

```
powershell -ExecutionPolicy Bypass -File tool\single_exe\build.ps1   # build\single_exe\CaretNotes.exe
```

That packs the Release folder (plus the Visual C++ runtime DLLs) into a small launcher (`tool/single_exe/launcher.cpp`). On first start it unpacks once to `%LOCALAPPDATA%\CaretNotes\app\<build id>` and starts the app from there; later starts reuse it. Your notes stay where they always are.

## Android

```
flutter build apk --release       # build\app\outputs\flutter-apk\app-release.apk
```

Needs the Android SDK (Android Studio or the command-line tools). Release builds are signed with the debug key for now.

A release build fails with `LNK1104` while `caret_notes.exe` is still running. Close the app first.

> Don't keep the project folder itself inside a synced cloud folder while building. Sync clients like Proton Drive can rename build files mid-build ("Name clash" copies).

## Tests

```
flutter analyze
flutter test
```

## Running a separate profile

Your notes live in `%APPDATA%\dev.caretnotes\caret_notes\library` (Settings → Device & storage shows the exact path). For testing, use a separate folder so your real notes are never touched:

```
$env:CARETNOTES_HOME = "C:\temp\cn-demo"
dart run tool/seed_demo.dart C:\temp\cn-demo\library   # optional: demo notes
build\windows\x64\runner\Release\caret_notes.exe "--open=Brainstorming.cnote"
```

`--open=<path inside the library>` opens a note straight in the editor.

## README screenshots

The pictures in `docs/screenshots` are rendered from the real app widgets with the Windows fonts:

```
flutter test tool/screenshots/readme_screenshots_test.dart
```

Edit `tool/screenshots/demo_library.dart` to change what the demo notes contain.

## Project layout

```
lib/core/     platform-independent logic: model, file format, paper, ink geometry, merge, sync, PDF export
lib/ui/       Flutter UI: home screen, editor, sync, settings, export
test/         unit and widget tests
tool/         demo data and the screenshot script
docs/         guides, design spec and implementation plan
```

`lib/core` never imports Flutter widgets, so it can be shared with the Android version. More for contributors in [AGENTS.md](../AGENTS.md).
