// Renders the app icon files from AppLogoPainter (lib/ui/app_logo.dart):
//   flutter test tool/icons/render_icons_test.dart
// Writes the Windows .ico, the Android launcher PNGs and the Linux/brand PNGs.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:caret_notes/ui/app_logo.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Room around the tile, as in CaretFlow's icons (a 440 tile in a 512 box).
const margin = 36 / 512;

Future<Uint8List> png(int size) async {
  final rec = ui.PictureRecorder();
  const AppLogoPainter(margin: margin).paint(Canvas(rec), Size.square(size.toDouble()));
  final img = await rec.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// An .ico holding PNG images (fine for every Windows since Vista).
Uint8List ico(Map<int, Uint8List> images) {
  final b = BytesBuilder();
  final head = ByteData(6)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, images.length, Endian.little);
  b.add(head.buffer.asUint8List());
  var offset = 6 + 16 * images.length;
  for (final e in images.entries) {
    final d = ByteData(16)
      ..setUint8(0, e.key >= 256 ? 0 : e.key)
      ..setUint8(1, e.key >= 256 ? 0 : e.key)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, e.value.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    b.add(d.buffer.asUint8List());
    offset += e.value.length;
  }
  for (final v in images.values) {
    b.add(v);
  }
  return b.toBytes();
}

void main() {
  testWidgets('render app icons', (tester) async {
    await tester.runAsync(() async {
      Future<void> write(String path, List<int> bytes) async {
        final f = File(path);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes);
      }

      await write('windows/runner/resources/app_icon.ico', ico({for (final s in [16, 20, 24, 32, 40, 48, 64, 256]) s: await png(s)}));
      const android = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      for (final e in android.entries) {
        await write('android/app/src/main/res/mipmap-${e.key}/ic_launcher.png', await png(e.value));
      }
      for (final s in [64, 128, 256, 512]) {
        await write('packaging/linux/icons/${s}x$s/caretnotes.png', await png(s));
      }
      await write('docs/brand/icon.png', await png(512));
    });
  });
}
