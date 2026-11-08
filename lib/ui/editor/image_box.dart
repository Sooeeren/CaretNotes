import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../core/geometry.dart';
import '../../core/ids.dart';
import '../../core/model/elements.dart';
import '../../core/model/note.dart';
import '../../core/model/page.dart';
import 'editor_controller.dart';
import 'pdf_cache.dart';

const imageTypes = XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']);
const pdfTypes = XTypeGroup(label: 'PDF', extensions: ['pdf']);

bool isImagePath(String path) => const ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'].contains(p.extension(path).toLowerCase());
bool isPdfPath(String path) => p.extension(path).toLowerCase() == '.pdf';

/// Downscales very large images so notes stay small and fast. Returns (bytes, width, height).
Future<(Uint8List, int, int)?> prepareImage(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width, h = frame.image.height;
    frame.image.dispose();
    const maxDim = 2400;
    if (math.max(w, h) <= maxDim) return (bytes, w, h);
    final out = await compute(_downscale, bytes);
    if (out == null) return (bytes, w, h);
    return out;
  } catch (_) {
    return null;
  }
}

(Uint8List, int, int)? _downscale(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  const maxDim = 2400;
  final resized = decoded.width >= decoded.height ? img.copyResize(decoded, width: maxDim) : img.copyResize(decoded, height: maxDim);
  final enc = decoded.hasAlpha ? img.encodePng(resized) : img.encodeJpg(resized, quality: 88);
  return (Uint8List.fromList(enc), resized.width, resized.height);
}

Future<void> insertImageBytes(BuildContext context, EditorController c, Uint8List bytes, String pageId, Vec2? center) async {
  final prepared = await prepareImage(bytes);
  if (prepared == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That image format isn\'t supported.')));
    }
    return;
  }
  c.addImage(pageId, prepared.$1, prepared.$2, prepared.$3, center: center);
}

Future<void> pickAndInsertImage(BuildContext context, EditorController c, String pageId, Vec2? center) async {
  final f = await openFile(acceptedTypeGroups: const [imageTypes]);
  if (f == null) return;
  final bytes = await f.readAsBytes();
  if (!context.mounted) return;
  await insertImageBytes(context, c, bytes, pageId, center);
}

/// Note pages for each page of a PDF, plus the asset map entry.
Future<(List<NotePage>, String, Uint8List)> pdfToPages(Uint8List bytes) async {
  final sizes = await pdfPageSizes(bytes);
  final assetId = 'pdf-${newId()}';
  final pages = [
    for (var i = 0; i < sizes.length; i++) NotePage(id: newId(), width: sizes[i].$1, height: sizes[i].$2, pdf: PdfRef(assetId, i)),
  ];
  return (pages, assetId, bytes);
}

/// Creates a new note from a PDF file the user picks. Returns the note or null.
Future<Note?> pickPdfAsNote(String deviceName) async {
  final f = await openFile(acceptedTypeGroups: const [pdfTypes]);
  if (f == null) return null;
  return pdfFileToNote(await f.readAsBytes(), p.basenameWithoutExtension(f.name), deviceName);
}

Future<Note> pdfFileToNote(Uint8List bytes, String title, String deviceName) async {
  final (pages, assetId, data) = await pdfToPages(bytes);
  final n = Note.create(title: title, layout: NoteLayout.paged, deviceName: deviceName);
  return n.copyWith(pages: pages, assets: {assetId: data});
}

/// Simple crop dialog; returns the new normalized crop rect.
Future<RectD?> showCropDialog(BuildContext context, Uint8List bytes, RectD initial) => showDialog<RectD>(
      context: context,
      builder: (ctx) => _CropDialog(bytes: bytes, initial: initial),
    );

class _CropDialog extends StatefulWidget {
  final Uint8List bytes;
  final RectD initial;
  const _CropDialog({required this.bytes, required this.initial});
  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  late RectD _r = widget.initial;
  int? _corner; // 0 tl, 1 tr, 2 br, 3 bl, 4 move
  Offset _last = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crop image'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: LayoutBuilder(builder: (ctx, cons) {
          final size = Size(cons.maxWidth, cons.maxHeight);
          Rect toPx(RectD r) => Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height);
          final px = toPx(_r);
          return GestureDetector(
            onPanStart: (d) {
              _last = d.localPosition;
              final cs = [px.topLeft, px.topRight, px.bottomRight, px.bottomLeft];
              _corner = 4;
              for (var i = 0; i < 4; i++) {
                if ((cs[i] - d.localPosition).distance < 24) _corner = i;
              }
            },
            onPanUpdate: (d) {
              final dx = (d.localPosition.dx - _last.dx) / size.width, dy = (d.localPosition.dy - _last.dy) / size.height;
              _last = d.localPosition;
              var l = _r.left, t = _r.top, r = _r.right, b = _r.bottom;
              switch (_corner) {
                case 0:
                  l += dx;
                  t += dy;
                case 1:
                  r += dx;
                  t += dy;
                case 2:
                  r += dx;
                  b += dy;
                case 3:
                  l += dx;
                  b += dy;
                default:
                  final w = r - l, h = b - t;
                  l = (l + dx).clamp(0.0, 1 - w);
                  t = (t + dy).clamp(0.0, 1 - h);
                  r = l + w;
                  b = t + h;
              }
              l = l.clamp(0.0, r - 0.05);
              t = t.clamp(0.0, b - 0.05);
              r = r.clamp(l + 0.05, 1.0);
              b = b.clamp(t + 0.05, 1.0);
              setState(() => _r = RectD(l, t, r, b));
            },
            child: Stack(children: [
              Positioned.fill(child: Image.memory(widget.bytes, fit: BoxFit.fill)),
              Positioned.fill(child: CustomPaint(painter: _CropPainter(px))),
            ]),
          );
        }),
      ),
      actions: [
        TextButton(onPressed: () => setState(() => _r = const RectD(0, 0, 1, 1)), child: const Text('Reset')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _r), child: const Text('Crop')),
      ],
    );
  }
}

class _CropPainter extends CustomPainter {
  final Rect r;
  _CropPainter(this.r);
  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = Colors.black54;
    final full = Offset.zero & size;
    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(full), Path()..addRect(r)), shade);
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(r, line);
    for (final k in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) {
      canvas.drawCircle(k, 8, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.r != r;
}

/// Crops so the visible part keeps its on-page scale.
Future<void> cropImage(BuildContext context, EditorController c, ImageEl e) async {
  final bytes = c.note.assets[e.assetId];
  if (bytes == null || c.selPageId == null) return;
  final pid = c.selPageId!;
  final r = await showCropDialog(context, bytes, e.crop);
  if (r == null) return;
  // full image size on the page implied by the current crop
  final fullW = e.rect.width / e.crop.width, fullH = e.rect.height / e.crop.height;
  final originX = e.rect.left - e.crop.left * fullW, originY = e.rect.top - e.crop.top * fullH;
  final nr = RectD(originX + r.left * fullW, originY + r.top * fullH, originX + r.right * fullW, originY + r.bottom * fullH);
  c.replaceElement(pid, e.copyWith(crop: r, rect: nr));
}
