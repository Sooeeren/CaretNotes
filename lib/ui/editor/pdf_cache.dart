import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/model/page.dart';

/// Renders imported PDF pages on demand at the current zoom, keeping the best image so far.
class PdfPageCache extends ChangeNotifier {
  final Map<String, Uint8List> Function() assets;

  /// How many rendered pages to keep (visible pages plus a few around them).
  final int maxImages;
  PdfPageCache(this.assets, {this.maxImages = 24});

  /// Bumped whenever a page image changes, so painters know to repaint.
  int version = 0;

  final Map<String, Future<PdfDocument?>> _docs = {};
  final Map<String, (ui.Image, int)> _images = {}; // key -> (image, pixel width)
  final Set<String> _pending = {};
  bool _disposed = false;

  String _key(PdfRef r) => '${r.assetId}#${r.pageIndex}';

  Future<PdfDocument?> _doc(String assetId) => _docs[assetId] ??= () async {
        final bytes = assets()[assetId];
        if (bytes == null) return null;
        try {
          return await PdfDocument.openData(bytes, sourceName: 'asset:$assetId');
        } catch (_) {
          return null;
        }
      }();

  /// Best image available for [page]; schedules a sharper render if [wantPx] is larger.
  ui.Image? imageFor(NotePage page, double wantPx) {
    final ref = page.pdf;
    if (ref == null) return null;
    final k = _key(ref);
    final have = _images.remove(k);
    if (have != null) _images[k] = have; // mark as recently used
    final want = wantPx.clamp(200, 3000).round();
    if ((have == null || have.$2 < want * 0.7) && !_pending.contains(k)) {
      _render(ref, want);
    }
    return have?.$1;
  }

  /// Renders synchronously-awaitable image (for export/thumbnail).
  Future<ui.Image?> renderNow(PdfRef ref, int px) async {
    final doc = await _doc(ref.assetId);
    if (doc == null || ref.pageIndex >= doc.pages.length) return null;
    final p = doc.pages[ref.pageIndex];
    final h = (px * p.height / p.width).round();
    final img = await p.render(fullWidth: px.toDouble(), fullHeight: h.toDouble(), width: px, height: h, backgroundColor: 0xFFFFFFFF);
    if (img == null) return null;
    final out = await img.createImage();
    img.dispose();
    return out;
  }

  Future<void> _render(PdfRef ref, int px) async {
    final k = _key(ref);
    _pending.add(k);
    try {
      final img = await renderNow(ref, px);
      if (img != null && !_disposed) {
        storeImage(k, img, px);
        notifyListeners();
      } else {
        img?.dispose();
      }
    } catch (_) {
      // ignore broken pages; they render blank
    } finally {
      _pending.remove(k);
    }
  }

  /// Stores a rendered page, disposing the image it replaces and evicting the least
  /// recently used pages beyond [maxImages].
  @visibleForTesting
  void storeImage(String key, ui.Image img, int px) {
    final old = _images.remove(key);
    if (old != null && !identical(old.$1, img)) old.$1.dispose();
    _images[key] = (img, px);
    while (_images.length > maxImages) {
      final first = _images.keys.first;
      _images.remove(first)!.$1.dispose();
    }
    version++;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final v in _images.values) {
      v.$1.dispose();
    }
    _images.clear();
    for (final f in _docs.values) {
      f.then((d) => d?.dispose());
    }
    super.dispose();
  }
}

/// PDF page sizes in points, for import.
Future<List<(double, double)>> pdfPageSizes(Uint8List bytes) async {
  final doc = await PdfDocument.openData(bytes, sourceName: 'import:${bytes.length}:${DateTime.now().microsecondsSinceEpoch}');
  try {
    return [for (final p in doc.pages) (p.width, p.height)];
  } finally {
    await doc.dispose();
  }
}

double pxFor(double pagePt, double scale, double dpr) => math.max(200, pagePt * scale * dpr);
