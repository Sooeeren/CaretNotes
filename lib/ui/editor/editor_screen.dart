import 'dart:async';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:provider/provider.dart';

import '../../core/geometry.dart';
import '../../core/library/library_store.dart';
import '../../core/model/note.dart';
import '../../core/settings.dart';
import '../controllers.dart';
import '../home/dialogs.dart';
import 'canvas_view.dart';
import 'editor_controller.dart';
import 'image_box.dart';
import 'page_strip.dart';
import 'painters.dart';
import 'pdf_cache.dart';
import 'ruler.dart';
import 'template_dialog.dart';
import 'toolbar.dart';

/// Export UI lives in the export module; called with the current note.
Future<void> Function(BuildContext context, Note note, String relPath)? editorExportAction;

/// Called after a note was closed and saved (sync uses this).
void Function(String relPath)? onNoteClosed;

class EditorScreen extends StatefulWidget {
  final String relPath;
  const EditorScreen({super.key, required this.relPath});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EditorController? _c;
  Object? _error;
  late PdfPageCache _pdf;
  final Map<String, ui.Image> _images = {};
  int _imagesVersion = 0;
  final _ruler = ValueNotifier<RulerGeom?>(null);
  final _handle = CanvasHandle();
  final _focus = FocusNode();
  bool _showPages = false;
  Offset? _dragPos;
  final _areaKey = GlobalKey();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<LibraryStore>();
    final settings = context.read<SettingsController>().value;
    try {
      final note = await store.loadNote(widget.relPath);
      final c = EditorController(note: note, relPath: widget.relPath, store: store, deviceName: settings.deviceName);
      _pdf = PdfPageCache(() => c.note.assets);
      c.thumbnailer = _thumbnail;
      c.addListener(_onNoteChanged);
      await decodeImages(note, into: _images);
      if (!mounted) return;
      setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<Uint8List?> _thumbnail(Note n) async {
    ui.Image? first;
    final p0 = n.pages.isEmpty ? null : n.pages.first;
    if (p0?.pdf != null) first = await _pdf.renderNow(p0!.pdf!, 400);
    return renderThumbnail(n, RenderAssets(images: _images, pdfImage: (p) => identical(p, p0) ? first : null));
  }

  void _onNoteChanged() {
    final c = _c;
    if (c == null) return;
    final missing = c.note.assets.keys.where((k) => !_images.containsKey(k) && !k.startsWith('pdf-'));
    if (missing.isNotEmpty) {
      decodeImages(c.note, into: _images).then((_) {
        if (mounted) setState(() => _imagesVersion++);
      });
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_onNoteChanged);
    _c?.dispose();
    if (_c != null) _pdf.dispose();
    _ruler.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    final c = _c;
    if (c != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (c.editingTextId != null) c.finishTextEdit();
      try {
        await c.close();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
          _closing = false;
          return;
        }
      }
      onNoteClosed?.call(c.relPath);
    }
    if (mounted) Navigator.of(context).pop();
  }

  String get _pageForInsert => _handle.visiblePageId ?? _c!.note.pages.first.id;

  Future<void> _paste() async {
    final c = _c!;
    final img = await Pasteboard.image;
    if (!mounted) return;
    if (img != null && img.isNotEmpty) {
      await insertImageBytes(context, c, img, _pageForInsert, _handle.visibleCenterLocal);
      return;
    }
    if (c.clipboard.isNotEmpty) {
      c.paste(_pageForInsert, at: _handle.visibleCenterLocal);
      return;
    }
    final text = await Pasteboard.text;
    if (text != null && text.trim().isNotEmpty) {
      final at = _handle.visibleCenterLocal ?? const Vec2(60, 80);
      final t = c.addText(_pageForInsert, at);
      c.typeText(_pageForInsert, t.id, text, 40 + 18.0 * '\n'.allMatches(text).length);
      c.finishTextEdit();
    }
  }

  Future<void> _onDrop(DropDoneDetails d) async {
    final c = _c!;
    for (final f in d.files) {
      if (isImagePath(f.path)) {
        final bytes = await f.readAsBytes();
        if (!mounted) return;
        await insertImageBytes(context, c, bytes, _pageForInsert, _handle.visibleCenterLocal);
      } else if (isPdfPath(f.path)) {
        await _insertPdf(await f.readAsBytes());
      }
    }
  }

  Future<void> _insertPdf(Uint8List bytes) async {
    final c = _c!;
    if (c.note.layout != NoteLayout.paged) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF pages can be added to notes with pages.')));
      return;
    }
    try {
      final (pages, id, data) = await pdfToPages(bytes);
      final idx = c.pageIndex(_pageForInsert);
      c.addAsset(id, data);
      c.commit([...c.note.pages]..insertAll(idx + 1, pages));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not read the PDF: $e')));
    }
  }

  Future<void> _template({String? pageId}) async {
    final c = _c!;
    final pg = pageId == null ? null : c.page(pageId);
    final r = await showTemplateDialog(context, pg?.templateOverride ?? c.note.template,
        allowPageOnly: pageId != null, hasOverride: pg?.templateOverride != null);
    if (r == null) return;
    final (t, whole) = r;
    if (pageId != null && !whole) {
      c.setPageTemplate(pageId, t);
    } else if (t != null) {
      c.setNoteTemplate(t);
    }
  }

  void _toggleRuler() {
    final c = _c!;
    if (_ruler.value == null) {
      final pid = _pageForInsert;
      final l = _handle.visibleCenterLocal ?? const Vec2(300, 300);
      final o = c.note.layout == NoteLayout.canvas ? Vec2.zero : _pageOriginOf(pid);
      _ruler.value = RulerGeom(center: Vec2(l.x + o.x, l.y + o.y), angle: 0);
    }
  }

  Vec2 _pageOriginOf(String pageId) {
    final n = _c!.note;
    final maxW = n.pages.fold<double>(0, (m, p) => p.width > m ? p.width : m);
    var y = 0.0;
    for (final p in n.pages) {
      if (p.id == pageId) return Vec2((maxW - p.width) / 2, y);
      y += p.height + 24;
    }
    return Vec2.zero;
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(EditorController c) => {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): c.copySelection,
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): c.cutSelection,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _paste,
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): c.duplicateSelection,
        const SingleActivator(LogicalKeyboardKey.delete): c.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.backspace): c.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.escape): () => c.clearSelection(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => c.save(),
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () => _handle.zoomBy(1.2),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () => _handle.zoomBy(1 / 1.2),
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): _handle.fit,
      };

  @override
  Widget build(BuildContext context) {
    final settingsCtl = context.watch<SettingsController>();
    final settings = settingsCtl.value;
    final c = _c;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('This note could not be opened.\n$_error', textAlign: TextAlign.center)),
      );
    }
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        body: SafeArea(
          child: CallbackShortcuts(
            bindings: c.editingTextId == null ? _shortcuts(c) : const {},
            child: Focus(
              focusNode: _focus,
              autofocus: true,
              child: ListenableBuilder(
                listenable: c,
                builder: (context, _) => _layout(context, c, settings, settingsCtl),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, EditorController c, AppSettings settings, SettingsController settingsCtl) {
    final dock = settings.toolbarDock;
    Widget toolbar(Axis axis, {bool compact = false}) => EditorToolbar(
          c: c,
          settings: settings,
          axis: axis,
          compact: compact,
          onBack: _close,
          onInsertImage: () => pickAndInsertImage(context, c, _pageForInsert, _handle.visibleCenterLocal),
          onRename: () async {
            final n = await askText(context, title: 'Rename note', initial: c.note.title);
            if (n != null) c.rename(n);
          },
          moreMenu: _moreMenu(context, c, settings, settingsCtl),
          onDragStart: (g) => setState(() => _dragPos = _toArea(g)),
          onDragUpdate: (g) => setState(() => _dragPos = _toArea(g)),
          onDragEnd: (g) {
            final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;
            final local = _toArea(g);
            setState(() => _dragPos = null);
            if (box == null) return;
            final d = dockFor(local, box.size);
            settingsCtl.update((s) => s.copyWith(
                  toolbarDock: d,
                  floatX: d == ToolbarDock.floating ? (local.dx - 150).clamp(0, box.size.width - 200) : s.floatX,
                  floatY: d == ToolbarDock.floating ? (local.dy - 24).clamp(0, box.size.height - 60) : s.floatY,
                ));
          },
          onPenColorsChanged: (col) {
            if (!settings.penColors.contains(col)) {
              settingsCtl.update((s) => s.copyWith(penColors: [col, ...s.penColors].take(7).toList()));
            }
          },
        );

    if (c.rulerVisible && _ruler.value == null) WidgetsBinding.instance.addPostFrameCallback((_) => _toggleRuler());

    final canvas = DropTarget(
      onDragDone: _onDrop,
      child: CanvasView(
        controller: c,
        settings: settings,
        pdf: _pdf,
        images: _images,
        imagesVersion: _imagesVersion,
        handle: _handle,
        ruler: _ruler,
      ),
    );
    final withPages = Row(children: [
      Expanded(child: canvas),
      if (_showPages && c.note.layout == NoteLayout.paged)
        PageStrip(
          c: c,
          pdf: _pdf,
          images: _images,
          onOpen: _handle.showPage,
          onTemplate: (pid) => _template(pageId: pid),
          onClose: () => setState(() => _showPages = false),
        ),
    ]);

    Widget body;
    switch (dock) {
      case ToolbarDock.top:
        body = Column(children: [toolbar(Axis.horizontal), const Divider(height: 1), Expanded(child: withPages)]);
      case ToolbarDock.left:
        body = Row(children: [toolbar(Axis.vertical), const VerticalDivider(width: 1), Expanded(child: withPages)]);
      case ToolbarDock.right:
        body = Row(children: [Expanded(child: withPages), const VerticalDivider(width: 1), toolbar(Axis.vertical)]);
      case ToolbarDock.floating:
        body = Stack(children: [
          Positioned.fill(child: withPages),
          Positioned(left: settings.floatX, top: settings.floatY, child: toolbar(Axis.horizontal, compact: true)),
        ]);
    }

    return Stack(key: _areaKey, children: [
      Positioned.fill(child: body),
      if (_dragPos != null) ..._dropHints(context),
    ]);
  }

  Offset _toArea(Offset global) {
    final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  List<Widget> _dropHints(BuildContext context) {
    final t = Theme.of(context);
    final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? Size.zero;
    final target = dockFor(_dragPos!, size);
    Widget zone(Rect r, ToolbarDock d) => Positioned.fromRect(
          rect: r,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: t.colorScheme.primary.withValues(alpha: target == d ? 0.25 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.colorScheme.primary.withValues(alpha: 0.6)),
              ),
            ),
          ),
        );
    return [
      zone(Rect.fromLTWH(8, 8, size.width - 16, 60), ToolbarDock.top),
      zone(Rect.fromLTWH(8, 76, 60, size.height - 84), ToolbarDock.left),
      zone(Rect.fromLTWH(size.width - 68, 76, 60, size.height - 84), ToolbarDock.right),
      Positioned(
        left: _dragPos!.dx - 60,
        top: _dragPos!.dy - 20,
        child: IgnorePointer(
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: t.colorScheme.primary,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text('Toolbar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _moreMenu(BuildContext context, EditorController c, AppSettings settings, SettingsController settingsCtl) {
    final n = c.note;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) async {
        switch (v) {
          case 'pages':
            setState(() => _showPages = !_showPages);
          case 'addpage':
            c.addPage(after: c.pageIndex(_pageForInsert));
          case 'pdf':
            final f = await openFile(acceptedTypeGroups: const [pdfTypes]);
            if (f != null) await _insertPdf(await f.readAsBytes());
          case 'template':
            await _template();
          case 'pagetemplate':
            await _template(pageId: _pageForInsert);
          case 'layout':
            c.switchLayout();
          case 'export':
            await c.save();
            if (context.mounted) await editorExportAction?.call(context, c.note, c.relPath);
          case 'fav':
            c.toggleFavorite();
          case 'rename':
            final t = await askText(context, title: 'Rename note', initial: n.title);
            if (t != null) c.rename(t);
          case 'fit':
            _handle.fit();
          case 'finger':
            await settingsCtl.update((s) => s.copyWith(fingerDrawing: !s.fingerDrawing));
          case 'dock':
            await settingsCtl.update((s) => s.copyWith(toolbarDock: ToolbarDock.top));
        }
      },
      itemBuilder: (_) => [
        if (n.layout == NoteLayout.paged) CheckedPopupMenuItem(value: 'pages', checked: _showPages, child: const Text('Page overview')),
        if (n.layout == NoteLayout.paged) const PopupMenuItem(value: 'addpage', child: Text('Add page')),
        if (n.layout == NoteLayout.paged) const PopupMenuItem(value: 'pdf', child: Text('Insert PDF pages…')),
        const PopupMenuItem(value: 'template', child: Text('Paper template…')),
        if (n.layout == NoteLayout.paged) const PopupMenuItem(value: 'pagetemplate', child: Text('Template for this page…')),
        if (c.canSwitchLayout)
          PopupMenuItem(value: 'layout', child: Text(n.layout == NoteLayout.paged ? 'Switch to endless page' : 'Switch to pages')),
        const PopupMenuDivider(),
        if (editorExportAction != null) const PopupMenuItem(value: 'export', child: Text('Export as PDF / image…')),
        CheckedPopupMenuItem(value: 'fav', checked: n.favorite, child: const Text('Favorite')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'fit', child: Text('Fit to width (Ctrl+0)')),
        CheckedPopupMenuItem(value: 'finger', checked: settings.fingerDrawing, child: const Text('Draw with finger')),
        if (settings.toolbarDock != ToolbarDock.top) const PopupMenuItem(value: 'dock', child: Text('Put toolbar back on top')),
      ],
    );
  }
}

/// Imports a PDF picked by the user as a new note in the current folder and opens it.
Future<void> importPdfIntoLibrary(BuildContext context) async {
  final lib = context.read<LibraryController>();
  final device = context.read<SettingsController>().value.deviceName;
  try {
    final note = await pickPdfAsNote(device);
    if (note == null) return;
    final e = await lib.store.createNote(lib.view == HomeView.folder ? lib.currentDir : '', note);
    await lib.refresh();
    if (context.mounted) await Navigator.of(context).pushNamed('/editor', arguments: e.relPath);
    await lib.refresh();
  } catch (err) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not import the PDF: $err')));
  }
}
