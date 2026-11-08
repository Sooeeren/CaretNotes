import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/model/note.dart';
import '../../core/model/page.dart';
import 'editor_controller.dart';
import 'painters.dart';
import 'pdf_cache.dart';

/// Page overview: thumbnails, tap to jump, drag to reorder, per-page actions.
class PageStrip extends StatefulWidget {
  final EditorController c;
  final PdfPageCache pdf;
  final Map<String, ui.Image> images;
  final ValueChanged<int> onOpen;
  final void Function(String pageId) onTemplate;
  final VoidCallback onClose;
  const PageStrip({super.key, required this.c, required this.pdf, required this.images, required this.onOpen, required this.onTemplate, required this.onClose});

  @override
  State<PageStrip> createState() => _PageStripState();
}

class _PageStripState extends State<PageStrip> {
  final Map<NotePage, Future<Uint8List?>> _thumbs = {};

  Future<Uint8List?> _thumb(Note n, NotePage p) => _thumbs[p] ??= () async {
        ui.Image? pdfImg;
        if (p.pdf != null) pdfImg = await widget.pdf.renderNow(p.pdf!, 220);
        final img = await renderPageImage(n, p, RenderAssets(images: widget.images, pdfImage: (_) => pdfImg), 110 / p.width);
        final png = await encodePng(img);
        img.dispose();
        return png;
      }();

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final n = c.note;
        _thumbs.removeWhere((k, _) => !n.pages.contains(k));
        return Material(
          color: t.colorScheme.surfaceContainerLow,
          child: SizedBox(
            width: 176,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                child: Row(children: [
                  Expanded(child: Text('Pages (${n.pages.length})', style: t.textTheme.titleSmall)),
                  IconButton(tooltip: 'Add page', icon: const Icon(Icons.add_rounded), onPressed: () => c.addPage()),
                  IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: widget.onClose),
                ]),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.all(8),
                  itemCount: n.pages.length,
                  onReorder: (a, b) => c.movePage(a, b > a ? b - 1 : b),
                  itemBuilder: (ctx, i) {
                    final pg = n.pages[i];
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(pg.id),
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: () => widget.onOpen(i),
                          onSecondaryTapDown: (d) => _menu(context, i, d.globalPosition),
                          onLongPress: () {},
                          child: Column(children: [
                            AspectRatio(
                              aspectRatio: pg.width / pg.height,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: t.colorScheme.outlineVariant),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: FutureBuilder<Uint8List?>(
                                  future: _thumb(n, pg),
                                  builder: (_, s) => s.data == null ? const SizedBox() : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
                                ),
                              ),
                            ),
                            Row(children: [
                              Expanded(child: Text('${i + 1}', textAlign: TextAlign.center, style: t.textTheme.labelMedium)),
                              Builder(
                                builder: (bctx) => IconButton(
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 18,
                                  icon: const Icon(Icons.more_horiz_rounded),
                                  onPressed: () {
                                    final box = bctx.findRenderObject() as RenderBox;
                                    _menu(context, i, box.localToGlobal(Offset.zero));
                                  },
                                ),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _menu(BuildContext context, int i, Offset pos) async {
    final c = widget.c;
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'add', child: Text('Insert blank page after')),
        const PopupMenuItem(value: 'dup', child: Text('Duplicate page')),
        const PopupMenuItem(value: 'tpl', child: Text('Page template…')),
        if (i > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
        if (i < c.note.pages.length - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
        if (c.note.pages.length > 1) const PopupMenuItem(value: 'del', child: Text('Delete page')),
      ],
    );
    switch (v) {
      case 'add':
        c.addPage(after: i);
      case 'dup':
        c.duplicatePage(i);
      case 'tpl':
        widget.onTemplate(c.note.pages[i].id);
      case 'up':
        c.movePage(i, i - 1);
      case 'down':
        c.movePage(i, i + 1);
      case 'del':
        c.deletePage(i);
    }
  }
}
