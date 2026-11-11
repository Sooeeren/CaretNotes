import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/export/export_fonts.dart';
import '../core/export/pdf_export.dart';
import '../core/export/pdf_stamp.dart';
import '../core/geometry.dart';
import '../core/library/library_store.dart';
import '../core/model/note.dart';
import '../core/model/page.dart';
import 'editor/painters.dart';
import 'editor/pdf_cache.dart';

enum ExportFormat { pdf, png, jpg }

Future<void> showExportDialog(BuildContext context, Note note, {int currentPage = 0}) =>
    showDialog(context: context, builder: (_) => _ExportDialog(note: note, currentPage: currentPage));

Future<void> exportEntry(BuildContext context, NoteEntry e) async {
  final store = context.read<LibraryStore>();
  try {
    final n = await store.loadNote(e.relPath);
    if (context.mounted) await showExportDialog(context, n);
  } catch (err) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open note: $err')));
  }
}

String _safe(String s) => s.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

/// Renders a page area to PNG/JPG bytes at [dpi].
Future<Uint8List?> renderAreaImage(Note n, NotePage pg, Rect area, double dpi, ExportFormat f, PdfPageCache pdf) async {
  final images = await decodeImages(n);
  final scale = dpi / 72;
  ui.Image? bg;
  if (pg.pdf != null) bg = await pdf.renderNow(pg.pdf!, (pg.width * scale).round().clamp(200, 6000));
  final im = await renderPageImage(n, pg, RenderAssets(images: images, pdfImage: (_) => bg), scale, area: area);
  try {
    if (f == ExportFormat.png) return await encodePng(im);
    final raw = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) return null;
    final decoded = img.Image.fromBytes(width: im.width, height: im.height, bytes: raw.buffer, numChannels: 4);
    final flat = img.Image(width: im.width, height: im.height)..clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, decoded);
    return Uint8List.fromList(img.encodeJpg(flat, quality: 92));
  } finally {
    im.dispose();
  }
}

/// "Save selection as image" from the editor.
Future<void> exportSelectionImage(BuildContext context, Note n, String pageId, RectD r) async {
  final pg = n.pages.firstWhere((x) => x.id == pageId);
  final loc = await getSaveLocation(suggestedName: '${_safe(n.title)} - selection.png', acceptedTypeGroups: const [XTypeGroup(label: 'PNG', extensions: ['png'])]);
  if (loc == null) return;
  final cache = PdfPageCache(() => n.assets);
  try {
    final bytes = await renderAreaImage(n, pg, Rect.fromLTRB(r.left - 8, r.top - 8, r.right + 8, r.bottom + 8), 300, ExportFormat.png, cache);
    if (bytes != null) await File(loc.path).writeAsBytes(bytes);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${p.basename(loc.path)}')));
  } finally {
    cache.dispose();
  }
}

class _ExportDialog extends StatefulWidget {
  final Note note;
  final int currentPage;
  const _ExportDialog({required this.note, required this.currentPage});
  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  ExportFormat _format = ExportFormat.pdf;
  String _which = 'all'; // all | current | range
  final _range = TextEditingController();
  CanvasExport _canvas = CanvasExport.onePage;
  double _dpi = 200;
  bool _busy = false;

  // Preview: one small picture per sheet, rendered one after another.
  static const _previewHeight = 150.0;
  static const _previewMax = 24;
  final _previewPdf = <String, ui.Image>{};
  late final PdfPageCache _previewCache = PdfPageCache(() => n.assets);
  List<ExportSheet> _previewSheets = const [];
  final _previewImages = <ui.Image?>[];
  String? _previewFor;
  int _previewGen = 0;

  /// The running preview job; exporting waits for it (PDFium must not render and stamp at once).
  Future<void> _previewJob = Future.value();

  Note get n => widget.note;

  @override
  void dispose() {
    _previewGen++;
    _range.dispose();
    final job = _previewJob;
    // Free the pictures once the last one is done rendering.
    job.whenComplete(() {
      _disposePreview();
      for (final im in _previewPdf.values) {
        im.dispose();
      }
      _previewCache.dispose();
    });
    super.dispose();
  }

  void _disposePreview() {
    for (final im in _previewImages) {
      im?.dispose();
    }
    _previewImages.clear();
  }

  /// Starts rendering the preview when the sheets changed.
  void _updatePreview(List<ExportSheet> sheets) {
    final key = [for (final s in sheets) '${s.page.id}:${s.area.left},${s.area.top},${s.area.right},${s.area.bottom},${s.height}'].join('|');
    if (key == _previewFor) return;
    _previewFor = key;
    final gen = ++_previewGen;
    _previewJob = _previewJob.then((_) async {
      if (gen != _previewGen) return;
      final shown = sheets.take(_previewMax).toList();
      _disposePreview();
      if (mounted) setState(() => _previewSheets = shown);
      final images = await decodeImages(n);
      for (final s in shown) {
        if (gen != _previewGen) break;
        ui.Image? im;
        try {
          final ref = s.page.pdf;
          ui.Image? bg;
          if (ref != null) {
            final k = '${ref.assetId}#${ref.pageIndex}';
            bg = _previewPdf[k] ??= (await _previewCache.renderNow(ref, 400))!;
          }
          final scale = 2 * _previewHeight / s.height;
          im = await renderPageImage(n, s.page, RenderAssets(images: images, pdfImage: (_) => bg), scale,
              area: Rect.fromLTRB(s.area.left, s.area.top, s.area.right, s.area.bottom));
        } catch (_) {}
        if (gen != _previewGen || !mounted) {
          im?.dispose();
          break;
        }
        setState(() => _previewImages.add(im));
      }
      for (final im in images.values) {
        im.dispose();
      }
    }).catchError((_) {});
  }

  Widget _preview(ThemeData t, List<ExportSheet> sheets) {
    final more = sheets.length - _previewSheets.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Preview · ${sheets.length} ${_format == ExportFormat.pdf ? 'page' : 'image'}${sheets.length == 1 ? '' : 's'}',
          style: t.textTheme.labelLarge),
      const SizedBox(height: 8),
      SizedBox(
        height: _previewHeight + 22,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _previewSheets.length + (more > 0 ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            if (i == _previewSheets.length) {
              return Center(child: Text('+$more more', style: t.textTheme.bodySmall));
            }
            final s = _previewSheets[i];
            final w = _previewHeight * s.width / s.height;
            final im = i < _previewImages.length ? _previewImages[i] : null;
            return Column(children: [
              Container(
                key: ValueKey('export-preview-$i'),
                width: w,
                height: _previewHeight,
                alignment: Alignment.topCenter,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: t.dividerColor)),
                child: im == null
                    ? (i < _previewImages.length ? null : const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
                    : RawImage(image: im, width: w - 2, height: (_previewHeight - 2) * s.area.height / s.height, fit: BoxFit.fill),
              ),
              const SizedBox(height: 4),
              Text('${i + 1}', style: t.textTheme.labelSmall),
            ]);
          },
        ),
      ),
    ]);
  }

  List<int>? _pages() {
    if (n.layout != NoteLayout.paged) return null;
    switch (_which) {
      case 'current':
        return [widget.currentPage];
      case 'range':
        final out = <int>{};
        for (final part in _range.text.split(',')) {
          final m = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+))?\s*$').firstMatch(part);
          if (m == null) continue;
          final a = int.parse(m.group(1)!), b = int.parse(m.group(2) ?? m.group(1)!);
          for (var i = a; i <= b; i++) {
            if (i >= 1 && i <= n.pages.length) out.add(i - 1);
          }
        }
        return out.isEmpty ? null : (out.toList()..sort());
      default:
        return null;
    }
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    _previewGen++; // stop the preview, then wait for its last picture
    await _previewJob;
    _previewFor = null; // redo it afterwards if the dialog stays open
    final cache = PdfPageCache(() => n.assets);
    try {
      final pages = _pages();
      if (_format == ExportFormat.pdf) {
        final loc = await getSaveLocation(suggestedName: '${_safe(n.title)}.pdf', acceptedTypeGroups: const [XTypeGroup(label: 'PDF', extensions: ['pdf'])]);
        if (loc == null) return;
        final bytes = await exportNotePdf(
          n,
          pages: pages,
          canvas: _canvas,
          fonts: await ExportFonts.system(),
          stamper: PdfiumStamper.tryLoad()?.stamp,
          rasterPdfPage: (ref, px) async {
            final im = await cache.renderNow(ref, px);
            if (im == null) return null;
            final png = await encodePng(im);
            im.dispose();
            return png;
          },
        );
        final path = loc.path.toLowerCase().endsWith('.pdf') ? loc.path : '${loc.path}.pdf';
        await File(path).writeAsBytes(bytes);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported ${p.basename(path)}')));
        }
      } else {
        final sheets = planSheets(n, pages: pages, canvas: _canvas);
        final ext = _format == ExportFormat.png ? 'png' : 'jpg';
        String? dir;
        String? single;
        if (sheets.length == 1) {
          final loc = await getSaveLocation(suggestedName: '${_safe(n.title)}.$ext', acceptedTypeGroups: [XTypeGroup(label: ext.toUpperCase(), extensions: [ext])]);
          if (loc == null) return;
          single = loc.path;
        } else {
          dir = await getDirectoryPath(confirmButtonText: 'Save ${sheets.length} images here');
          if (dir == null) return;
        }
        for (var i = 0; i < sheets.length; i++) {
          final s = sheets[i];
          final bytes = await renderAreaImage(n, s.page, Rect.fromLTRB(s.area.left, s.area.top, s.area.right, s.area.bottom), _dpi, _format, cache);
          if (bytes == null) continue;
          final path = single ?? p.join(dir!, '${_safe(n.title)} - ${(i + 1).toString().padLeft(2, '0')}.$ext');
          await File(path).writeAsBytes(bytes);
        }
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported ${sheets.length} image${sheets.length == 1 ? '' : 's'}')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      cache.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sheets = planSheets(n, pages: _pages(), canvas: _canvas);
    if (!_busy) _updatePreview(sheets);
    return AlertDialog(
      title: Text('Export "${n.title}"'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<ExportFormat>(
            segments: const [
              ButtonSegment(value: ExportFormat.pdf, label: Text('PDF'), icon: Icon(Icons.picture_as_pdf)),
              ButtonSegment(value: ExportFormat.png, label: Text('PNG')),
              ButtonSegment(value: ExportFormat.jpg, label: Text('JPG')),
            ],
            selected: {_format},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _format = v.first),
          ),
          const SizedBox(height: 16),
          if (n.layout == NoteLayout.paged) ...[
            Text('Pages', style: t.textTheme.labelLarge),
            RadioGroup<String>(
              groupValue: _which,
              onChanged: (v) => setState(() => _which = v!),
              child: Column(children: [
                RadioListTile(value: 'all', title: Text('All ${n.pages.length} pages'), dense: true),
                RadioListTile(value: 'current', title: Text('Current page (${widget.currentPage + 1})'), dense: true),
                RadioListTile(
                  value: 'range',
                  dense: true,
                  title: TextField(
                    controller: _range,
                    decoration: const InputDecoration(hintText: 'e.g. 1-3, 5', isDense: true),
                    onTap: () => setState(() => _which = 'range'),
                  ),
                ),
              ]),
            ),
          ],
          if (n.layout == NoteLayout.endless)
            Text('The long page is split into A4 sheets, between lines of writing so nothing is cut in half.', style: t.textTheme.bodySmall),
          if (n.layout == NoteLayout.canvas) ...[
            Text('Canvas', style: t.textTheme.labelLarge),
            RadioGroup<CanvasExport>(
              groupValue: _canvas,
              onChanged: (v) => setState(() => _canvas = v!),
              child: const Column(children: [
                RadioListTile(value: CanvasExport.onePage, title: Text('Everything on one large page'), dense: true),
                RadioListTile(value: CanvasExport.tiles, title: Text('Split into A4 sheets'), dense: true),
              ]),
            ),
          ],
          if (_format != ExportFormat.pdf) ...[
            const SizedBox(height: 8),
            Text('Resolution: ${_dpi.round()} dpi', style: t.textTheme.labelLarge),
            Slider(value: _dpi, min: 72, max: 400, divisions: 16, label: '${_dpi.round()} dpi', onChanged: (v) => setState(() => _dpi = v)),
          ],
          if (_format == ExportFormat.pdf)
            Text('Ink stays sharp at any zoom, typed text stays selectable, imported PDFs keep their original quality.', style: t.textTheme.bodySmall),
          const SizedBox(height: 16),
          _preview(t, sheets),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _busy ? null : _run,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.ios_share),
          label: const Text('Export'),
        ),
      ],
    );
  }
}
