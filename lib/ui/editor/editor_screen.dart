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
import '../menu.dart';
import 'canvas_view.dart';
import 'editor_controller.dart';
import 'editor_shortcuts.dart';
import 'find_bar.dart';
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

/// Called when a note is opened (sync leaves it alone while it's open).
void Function(String relPath)? onNoteOpened;

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
  bool _finding = false;
  Offset? _dragPos;
  final _areaKey = GlobalKey();
  bool _closing = false;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Never lose the last strokes: save when the window closes or the app goes to the background.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        try {
          await _c?.close();
        } catch (_) {}
        return ui.AppExitResponse.exit;
      },
      onHide: () => _c?.save(),
      onPause: () => _c?.save(),
    );
    _load();
  }

  Future<void> _load() async {
    final store = context.read<LibraryStore>();
    final settings = context.read<SettingsController>().value;
    // Tell sync first, so it leaves this note alone from the moment it starts loading.
    onNoteOpened?.call(widget.relPath);
    try {
      final note = await store.loadNote(widget.relPath);
      final c = EditorController(note: note, relPath: widget.relPath, store: store, deviceName: settings.deviceName);
      _pdf = PdfPageCache(() => c.note.assets);
      c.thumbnailer = _thumbnail;
      c.addListener(_onNoteChanged);
      await c.markLoaded();
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
    _lifecycle.dispose();
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
      final t = c.addText(_pageForInsert, at, mode: TextMode.box);
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
        allowPageOnly: pageId != null,
        hasOverride: pg?.templateOverride != null,
        pageSize: Size((pg ?? c.note.pages.first).width, c.note.layout == NoteLayout.paged ? (pg ?? c.note.pages.first).height : (pg ?? c.note.pages.first).width * 1.414));
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

  Map<ShortcutActivator, VoidCallback> _shortcuts(EditorController c) {
    // In read mode only looking around works; nothing on the page changes.
    VoidCallback edit(VoidCallback f) => () {
          if (!c.readOnly) f();
        };
    return {
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): edit(c.undo),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): edit(c.redo),
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): edit(c.redo),
      const SingleActivator(LogicalKeyboardKey.keyC, control: true): c.copySelection,
      const SingleActivator(LogicalKeyboardKey.keyX, control: true): edit(c.cutSelection),
      const SingleActivator(LogicalKeyboardKey.keyV, control: true): edit(_paste),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): edit(c.duplicateSelection),
      const SingleActivator(LogicalKeyboardKey.delete): edit(c.deleteSelection),
      const SingleActivator(LogicalKeyboardKey.backspace): edit(c.deleteSelection),
      const SingleActivator(LogicalKeyboardKey.escape): () => c.clearSelection(),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => c.save(),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => setState(() => _finding = true),
      const SingleActivator(LogicalKeyboardKey.equal, control: true): () => _handle.zoomBy(1.2),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () => _handle.zoomBy(1 / 1.2),
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): _handle.fit,
    };
  }

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
          child: EditorShortcuts(
            c: c,
            bindings: _shortcuts(c),
            focusNode: _focus,
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) => _layout(context, c, settings, settingsCtl),
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, EditorController c, AppSettings settings, SettingsController settingsCtl) {
    final dock = settings.toolbarDock;
    final pill = ToolPill(
      c: c,
      settings: settings,
      axis: dock == ToolbarDock.left || dock == ToolbarDock.right ? Axis.vertical : Axis.horizontal,
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
        topInset: dock == ToolbarDock.top ? 52 : 0,
      ),
    );
    final paged = c.note.layout == NoteLayout.paged;

    final area = LayoutBuilder(builder: (context, box) {
      final placed = switch (dock) {
        ToolbarDock.top => Positioned(top: 10, left: 0, right: 0, child: Center(child: pill)),
        ToolbarDock.left => Positioned(left: 10, top: 0, bottom: 0, child: Center(child: pill)),
        ToolbarDock.right => Positioned(right: 10, top: 0, bottom: 0, child: Center(child: pill)),
        ToolbarDock.floating => Positioned(
            left: settings.floatX.clamp(0, (box.maxWidth - 120).clamp(0, double.infinity)).toDouble(),
            top: settings.floatY.clamp(0, (box.maxHeight - 56).clamp(0, double.infinity)).toDouble(),
            child: pill,
          ),
      };
      return Stack(key: _areaKey, children: [
        Positioned.fill(child: canvas),
        placed,
        if (_dragPos != null) ..._dropHints(context),
      ]);
    });

    return Column(children: [
      NoteBar(
        c: c,
        onBack: _close,
        onRename: () async {
          final n = await askText(context, title: 'Rename note', initial: c.note.title);
          if (n != null) c.rename(n);
        },
        finding: _finding,
        onFind: () => _setFinding(!_finding),
        insertMenu: _insertMenu(context, c),
        pagesButton: paged
            ? BarToggle(
                icon: Icons.view_agenda_outlined,
                tooltip: 'Pages',
                on: _showPages,
                onTap: () => setState(() => _showPages = !_showPages),
              )
            : null,
        moreMenu: _moreMenu(context, c, settings, settingsCtl),
      ),
      if (_finding)
        FindBar(
          c: c,
          onReveal: (h) => _handle.reveal(h.pageIndex, h.rect),
          onClose: () => _setFinding(false),
        ),
      const Divider(height: 1),
      Expanded(
        child: Row(children: [
          Expanded(child: area),
          if (_showPages && paged)
            PageStrip(
              c: c,
              pdf: _pdf,
              images: _images,
              onOpen: _handle.showPage,
              onTemplate: (pid) => _template(pageId: pid),
              onClose: () => setState(() => _showPages = false),
            ),
        ]),
      ),
    ]);
  }

  void _setFinding(bool on) {
    setState(() => _finding = on);
    if (!on) {
      _c?.showFindHit(null);
      _focus.requestFocus();
    }
  }

  Widget _insertMenu(BuildContext context, EditorController c) {
    final paged = c.note.layout == NoteLayout.paged;
    return PopupMenuButton<String>(
      tooltip: 'Insert',
      icon: const Icon(Icons.add),
      enabled: !c.readOnly,
      onSelected: (v) async {
        switch (v) {
          case 'image':
            await pickAndInsertImage(context, c, _pageForInsert, _handle.visibleCenterLocal);
          case 'pdf':
            final f = await openFile(acceptedTypeGroups: const [pdfTypes]);
            if (f != null) await _insertPdf(await f.readAsBytes());
          case 'textbox':
            c.textMode = TextMode.box;
            c.setTool(EditorTool.text);
          case 'addpage':
            c.addPage(after: c.pageIndex(_pageForInsert));
        }
      },
      itemBuilder: (_) => [
        iconMenuItem('image', Icons.image_outlined, 'Image…'),
        if (paged) iconMenuItem('pdf', Icons.picture_as_pdf_outlined, 'PDF pages…'),
        iconMenuItem('textbox', Icons.text_fields, 'Text box'),
        if (paged) ...[
          const PopupMenuDivider(),
          iconMenuItem('addpage', Icons.note_add_outlined, 'New page after this one'),
        ],
      ],
    );
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
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        switch (v) {
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
        iconMenuItem('template', Icons.texture_outlined, 'Paper template…'),
        if (n.layout == NoteLayout.paged) iconMenuItem('pagetemplate', Icons.description_outlined, 'Template for this page…'),
        if (c.canSwitchLayout)
          n.layout == NoteLayout.paged
              ? iconMenuItem('layout', Icons.vertical_split_outlined, 'Switch to endless page')
              : iconMenuItem('layout', Icons.auto_stories_outlined, 'Switch to pages'),
        const PopupMenuDivider(),
        if (editorExportAction != null) iconMenuItem('export', Icons.ios_share_outlined, 'Export as PDF / image…'),
        iconMenuItem('fav', n.favorite ? Icons.star : Icons.star_outline, n.favorite ? 'Remove from favorites' : 'Add to favorites'),
        iconMenuItem('rename', Icons.drive_file_rename_outline, 'Rename'),
        const PopupMenuDivider(),
        iconMenuItem('fit', Icons.fit_screen_outlined, 'Fit to width', shortcut: 'Ctrl+0'),
        iconMenuItem('finger', Icons.touch_app_outlined, 'Draw with finger', checked: settings.fingerDrawing),
        if (settings.toolbarDock != ToolbarDock.top) iconMenuItem('dock', Icons.vertical_align_top, 'Put tools back on top'),
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
