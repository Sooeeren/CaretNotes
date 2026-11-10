#!/usr/bin/env bash
# Packages build/linux/x64/release/bundle (run `flutter build linux --release` first) as
#   caretnotes_<v>_amd64.deb, caretnotes-<v>-1.x86_64.rpm, caretnotes-<v>-1-x86_64.pkg.tar.zst
#   and CaretNotes-<v>-x86_64.AppImage in <out dir>.
# Needs nfpm (https://nfpm.goreleaser.com) and appimagetool on PATH.
# Usage: packaging/linux/build.sh <version> <out dir>
set -euo pipefail
VERSION="$1"; OUT="$2"
cd "$(dirname "$0")/../.."
BUNDLE=build/linux/x64/release/bundle
[ -x "$BUNDLE/caret_notes" ] || { echo "Run 'flutter build linux --release' first." >&2; exit 1; }
mkdir -p "$OUT"
export VERSION

# File names the in-app updater looks for (lib/core/update/update_check.dart).
pkg() { # <nfpm packager> <install_kind> <file name>
  echo "$2" > build/linux/install_kind
  nfpm package --config packaging/linux/nfpm.yaml --packager "$1" --target "$OUT/$3"
}
pkg deb deb "caretnotes_${VERSION}_amd64.deb"
pkg rpm rpm "caretnotes-${VERSION}-1.x86_64.rpm"
pkg archlinux arch "caretnotes-${VERSION}-1-x86_64.pkg.tar.zst"

# AppImage: the bundle plus desktop entry and icon; runs on any distro with GTK 3.
APPDIR=build/linux/AppDir
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/lib" "$APPDIR/usr/share/metainfo" "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp -r "$BUNDLE" "$APPDIR/usr/lib/caretnotes"
cp packaging/linux/dev.caretnotes.caret_notes.desktop "$APPDIR/"
cp packaging/linux/icons/256x256/caretnotes.png "$APPDIR/dev.caretnotes.caret_notes.png"
cp packaging/linux/icons/256x256/caretnotes.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/dev.caretnotes.caret_notes.png"
cp packaging/linux/dev.caretnotes.caret_notes.metainfo.xml "$APPDIR/usr/share/metainfo/dev.caretnotes.caret_notes.appdata.xml"
cat > "$APPDIR/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/caretnotes/caret_notes" "$@"
RUN
chmod +x "$APPDIR/AppRun"
ARCH=x86_64 appimagetool --no-appstream "$APPDIR" "$OUT/CaretNotes-$VERSION-x86_64.AppImage"
ls -lh "$OUT"
