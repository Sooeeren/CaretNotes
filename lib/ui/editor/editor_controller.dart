import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../core/format/note_codec.dart';
import '../../core/geometry.dart';
import '../../core/ids.dart';
import '../../core/ink/eraser.dart';
import '../../core/ink/selection.dart';
import '../../core/ink/shape_recognizer.dart';
import '../../core/library/library_store.dart';
import '../../core/model/elements.dart';
import '../../core/model/note.dart';
import '../../core/model/page.dart';
import '../../core/paper.dart';

enum EditorTool { pen, highlighter, eraser, select, text }

enum SelectMode { lasso, box }

/// What the text tool does on tap: type on the paper's lines, or place a free text box.
enum TextMode { lines, box }

/// The stroke (or lasso path) currently being drawn. Repaints only the live layer.
class LiveInk extends ChangeNotifier {
  String? pageId;
  List<InkPoint> points = [];
  ToolKind tool = ToolKind.pen;
  int color = 0;
  double width = 2;
  bool snapped = false;
  RecognizedShape? shape;

  /// Lasso/box selection outline in page coords.
  List<Vec2>? selectPath;
  RectD? selectBox;

  void clear() {
    pageId = null;
    points = [];
    snapped = false;
    shape = null;
    selectPath = null;
    selectBox = null;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

class _Op {
  final List<NotePage> before, after;
  final NoteLayout layoutBefore, layoutAfter;
  const _Op(this.before, this.after, this.layoutBefore, this.layoutAfter);
}

class EditorController extends ChangeNotifier {
  EditorController({
    required this._note,
    required this.relPath,
    required this.store,
    required this.deviceName,
    this.autosave = true,
  });

  Note _note;
  Note get note => _note;
  String relPath;
  final LibraryStore? store;
  final String deviceName;
  final bool autosave;

  /// Renders a PNG thumbnail of the first page; set by the UI.
  Future<Uint8List?> Function(Note note)? thumbnailer;

  // ---- tool state ----
  EditorTool tool = EditorTool.pen;
  ToolKind penKind = ToolKind.pen;
  int penColor = 0xFF1B2A6B;
  double penWidth = 2.4;
  int hlColor = 0xFFFFE14D;
  double hlWidth = 14;
  bool eraserPartial = false;
  double eraserSize = 8;
  SelectMode selectMode = SelectMode.lasso;
  TextMode textMode = TextMode.lines;
  bool rulerVisible = false;

  final LiveInk live = LiveInk();

  // ---- undo ----
  final List<_Op> _undo = [], _redo = [];
  List<NotePage>? _gestureBefore;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  bool dirty = false;
  Timer? _saveTimer;
  String? _diskStamp;

  Future<String?> _stamp() async {
    final s = store;
    if (s == null) return null;
    final f = File(s.abs(relPath));
    if (!await f.exists()) return null;
    final st = await f.stat();
    return '${st.modified.microsecondsSinceEpoch}:${st.size}';
  }

  /// Remembers the file's state on disk right after loading, so saving can tell
  /// whether something else (sync) replaced the file meanwhile.
  Future<void> markLoaded() async => _diskStamp = await _stamp();
  Future<void>? _saving;

  void setTool(EditorTool t) {
    tool = t;
    if (t != EditorTool.select) clearSelection(notify: false);
    notifyListeners();
  }

  void update(void Function() f) {
    f();
    notifyListeners();
  }

  // ---------- pages helpers ----------

  int pageIndex(String pageId) => _note.pages.indexWhere((p) => p.id == pageId);
  NotePage page(String pageId) => _note.pages[pageIndex(pageId)];

  void _setPages(List<NotePage> pages) {
    _note = _note.copyWith(pages: pages);
  }

  void _replacePage(NotePage p) {
    final i = pageIndex(p.id);
    if (i < 0) return;
    final pages = [..._note.pages];
    pages[i] = p;
    _setPages(pages);
  }

  /// Applies a change as one undo step.
  void commit(List<NotePage> newPages, {NoteLayout? layoutBefore}) {
    final before = _note.pages;
    _setPages(newPages);
    _undo.add(_Op(before, newPages, layoutBefore ?? _note.layout, _note.layout));
    _redo.clear();
    _markDirty();
    notifyListeners();
  }

  void _commitPage(NotePage p) {
    final i = pageIndex(p.id);
    final pages = [..._note.pages];
    pages[i] = p;
    commit(pages);
  }

  void beginGesture() => _gestureBefore ??= _note.pages;

  void endGesture() {
    final before = _gestureBefore;
    _gestureBefore = null;
    if (before == null || identical(before, _note.pages)) return;
    _undo.add(_Op(before, _note.pages, _note.layout, _note.layout));
    _redo.clear();
    _markDirty();
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final op = _undo.removeLast();
    _redo.add(op);
    _note = _note.copyWith(layout: op.layoutBefore);
    _setPages(op.before);
    clearSelection(notify: false);
    _markDirty();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final op = _redo.removeLast();
    _undo.add(op);
    _note = _note.copyWith(layout: op.layoutAfter);
    _setPages(op.after);
    clearSelection(notify: false);
    _markDirty();
    notifyListeners();
  }

  // ---------- strokes ----------

  void beginStroke(String pageId, InkPoint p, ToolKind kind) {
    live
      ..pageId = pageId
      ..points = [p]
      ..tool = kind
      ..color = kind == ToolKind.highlighter ? hlColor : penColor
      ..width = kind == ToolKind.highlighter ? hlWidth : penWidth
      ..snapped = false
      ..shape = null;
    live.changed();
  }

  void extendStroke(InkPoint p) {
    if (live.pageId == null) return;
    if (live.snapped) {
      _adjustShape(p.v);
    } else {
      final last = live.points.last;
      if ((last.x - p.x).abs() < 0.15 && (last.y - p.y).abs() < 0.15) return;
      live.points.add(p);
    }
    live.changed();
  }

  /// Hold-to-shape: replaces the live stroke by a clean shape. Returns true on success.
  bool snapLiveToShape() {
    if (live.pageId == null || live.snapped || live.points.length < 3) return false;
    final s = recognizeShape([for (final p in live.points) p.v]);
    if (s == null) return false;
    live.shape = s;
    live.snapped = true;
    _shapeAnchorBase = s.points;
    _shapeGrab = live.points.last.v;
    live.points = _densify(s.points);
    live.changed();
    return true;
  }

  List<Vec2> _shapeAnchorBase = const [];
  Vec2 _shapeGrab = Vec2.zero;

  void _adjustShape(Vec2 p) {
    final s = live.shape;
    if (s == null) return;
    List<Vec2> pts;
    if (s.kind == ShapeKind.line) {
      pts = [_shapeAnchorBase.first, p];
    } else if (s.kind == ShapeKind.arrow) {
      final tail = _shapeAnchorBase.first;
      final dir = (p - tail).normalized();
      final len = tail.dist(p);
      final head = math.max(0.18 * len, 8.0);
      Vec2 rot(Vec2 d, double a) => Vec2(d.x * math.cos(a) - d.y * math.sin(a), d.x * math.sin(a) + d.y * math.cos(a));
      pts = [tail, p, p + rot(dir * -1, 0.45) * head, p, p + rot(dir * -1, -0.45) * head];
    } else {
      // Scale from the bounding-box corner farthest from where the pen grabbed the shape.
      final b = RectD.fromPoints(_shapeAnchorBase);
      final anchor = Vec2(
        (_shapeGrab.x - b.left).abs() > (_shapeGrab.x - b.right).abs() ? b.left : b.right,
        (_shapeGrab.y - b.top).abs() > (_shapeGrab.y - b.bottom).abs() ? b.top : b.bottom,
      );
      final gx = _shapeGrab.x - anchor.x, gy = _shapeGrab.y - anchor.y;
      final sx = gx.abs() < 1 ? 1.0 : (p.x - anchor.x) / gx;
      final sy = gy.abs() < 1 ? 1.0 : (p.y - anchor.y) / gy;
      pts = [for (final q in _shapeAnchorBase) Vec2(anchor.x + (q.x - anchor.x) * sx, anchor.y + (q.y - anchor.y) * sy)];
    }
    live.shape = RecognizedShape(s.kind, pts);
    live.points = _densify(pts);
  }

  /// Evenly spaced points so partial erasing works on shapes too.
  List<InkPoint> _densify(List<Vec2> pts) {
    final out = <InkPoint>[];
    for (var i = 0; i < pts.length; i++) {
      if (i == 0) {
        out.add(InkPoint(pts[0].x, pts[0].y, 0.6));
        continue;
      }
      final a = pts[i - 1], b = pts[i];
      final n = math.max(1, (a.dist(b) / 4).ceil());
      for (var k = 1; k <= n; k++) {
        final t = k / n;
        out.add(InkPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, 0.6));
      }
    }
    return out;
  }

  void endStroke() {
    final pid = live.pageId;
    if (pid == null || pageIndex(pid) < 0) {
      live.clear();
      return;
    }
    final pts = live.points;
    final stroke = StrokeEl(id: newId(), points: List.of(pts), tool: live.tool, color: live.color, width: live.width);
    var pg = page(pid);
    pg = pg.copyWith(elements: [...pg.elements, stroke]);
    pg = _grow(pg, stroke.bounds());
    live.clear();
    _commitPage(pg);
  }

  void cancelStroke() => live.clear();

  /// Endless notes grow downward as you write near the bottom.
  NotePage _grow(NotePage pg, RectD b) {
    if (_note.layout != NoteLayout.endless) return pg;
    const margin = 600.0;
    if (b.bottom + margin / 2 > pg.height) return pg.copyWith(height: b.bottom + margin);
    return pg;
  }

  // ---------- eraser ----------

  void beginErase() => beginGesture();

  void eraseAt(String pageId, Vec2 p) {
    final i = pageIndex(pageId);
    if (i < 0) return;
    final pg = _note.pages[i];
    final r = eraserSize;
    var changed = false;
    final out = <Element>[];
    for (final e in pg.elements) {
      if (e is StrokeEl) {
        if (eraserPartial) {
          final pieces = eraseStroke(e, p, r);
          if (pieces.length != 1 || !identical(pieces.first, e)) changed = true;
          out.addAll(pieces);
        } else if (strokeHit(e, p, r)) {
          changed = true;
        } else {
          out.add(e);
        }
      } else {
        out.add(e);
      }
    }
    if (!changed) return;
    _replacePage(pg.copyWith(elements: out));
    notifyListeners();
  }

  void endErase() => endGesture();

  // ---------- selection ----------

  String? selPageId;
  Set<String> selIds = {};
  List<Element> _transformBase = const [];
  List<Element> clipboard = const [];

  bool get hasSelection => selPageId != null && selIds.isNotEmpty;

  List<Element> get selectedElements {
    if (!hasSelection || pageIndex(selPageId!) < 0) return const [];
    return [for (final e in page(selPageId!).elements) if (selIds.contains(e.id)) e];
  }

  RectD? get selectionRect => hasSelection ? selectionBounds(selectedElements) : null;

  void clearSelection({bool notify = true}) {
    selPageId = null;
    selIds = {};
    if (notify) notifyListeners();
  }

  void selectLasso(String pageId, List<Vec2> polygon) {
    selPageId = pageId;
    selIds = lassoHits(page(pageId).elements, polygon);
    if (selIds.isEmpty) selPageId = null;
    notifyListeners();
  }

  void selectBox(String pageId, RectD r) {
    selPageId = pageId;
    selIds = boxHits(page(pageId).elements, r);
    if (selIds.isEmpty) selPageId = null;
    notifyListeners();
  }

  void selectOnly(String pageId, String id) {
    selPageId = pageId;
    selIds = {id};
    notifyListeners();
  }

  void beginTransform() {
    beginGesture();
    _transformBase = selectedElements;
  }

  /// Live preview of move/scale/rotate; [t] is relative to the state at [beginTransform].
  void previewTransform(Affine t) {
    if (!hasSelection) return;
    final base = {for (final e in _transformBase) e.id: e};
    final pg = page(selPageId!);
    _replacePage(pg.copyWith(elements: [for (final e in pg.elements) base.containsKey(e.id) ? base[e.id]!.transformed(t) : e]));
    notifyListeners();
  }

  void endTransform() {
    _transformBase = const [];
    if (hasSelection) {
      final pg = page(selPageId!);
      _replacePage(_grow(pg, selectionRect!));
    }
    endGesture();
  }

  void moveSelection(double dx, double dy) {
    beginTransform();
    previewTransform(Affine.translate(dx, dy));
    endTransform();
  }

  void deleteSelection() {
    if (!hasSelection) return;
    final pg = page(selPageId!);
    final ids = selIds;
    clearSelection(notify: false);
    _commitPage(pg.copyWith(elements: [for (final e in pg.elements) if (!ids.contains(e.id)) e]));
  }

  void recolorSelection(int color) {
    if (!hasSelection) return;
    final pg = page(selPageId!);
    _commitPage(pg.copyWith(elements: [
      for (final e in pg.elements)
        if (!selIds.contains(e.id))
          e
        else
          switch (e) {
            StrokeEl s => s.copyWith(color: color),
            TextEl t => t.copyWith(color: color),
            _ => e,
          },
    ]));
  }

  void copySelection() => clipboard = selectedElements;

  void cutSelection() {
    copySelection();
    deleteSelection();
  }

  /// Pastes the clipboard onto [pageId], offset a bit (or centered at [at]).
  void paste(String pageId, {Vec2? at}) {
    if (clipboard.isEmpty) return;
    final b = selectionBounds(clipboard);
    final t = at == null ? Affine.translate(16, 16) : Affine.translate(at.x - b.center.x, at.y - b.center.y);
    final copies = [for (final e in clipboard) e.transformed(t).withId(newId())];
    final pg = page(pageId);
    _commitPage(pg.copyWith(elements: [...pg.elements, ...copies]));
    selPageId = pageId;
    selIds = {for (final e in copies) e.id};
    notifyListeners();
  }

  void duplicateSelection() {
    if (!hasSelection) return;
    copySelection();
    paste(selPageId!);
  }

  // ---------- generic element edits ----------

  void addElement(String pageId, Element e) {
    final pg = page(pageId);
    _commitPage(_grow(pg.copyWith(elements: [...pg.elements, e]), e.bounds()));
  }

  void replaceElement(String pageId, Element e, {bool undoable = true}) {
    final pg = page(pageId);
    final np = pg.copyWith(elements: [for (final x in pg.elements) x.id == e.id ? e : x]);
    if (undoable) {
      _commitPage(np);
    } else {
      _replacePage(np);
      _markDirty();
      notifyListeners();
    }
  }

  void removeElement(String pageId, String id) {
    final pg = page(pageId);
    _commitPage(pg.copyWith(elements: [for (final x in pg.elements) if (x.id != id) x]));
  }

  // ---------- text boxes ----------

  String? editingTextId;
  String? editingTextPageId;

  TextEl addText(String pageId, Vec2 at, {TextMode? mode}) {
    final color = penColor == 0xFF1B2A6B ? 0xFF222222 : penColor;
    final pg = page(pageId);
    final TextEl t;
    if ((mode ?? textMode) == TextMode.lines) {
      final canvas = _note.layout == NoteLayout.canvas;
      final f = ruledFrameAt(
        pg.templateOverride ?? _note.template,
        at,
        pageWidth: canvas ? null : pg.width,
        pageHeight: canvas || _note.layout == NoteLayout.endless ? null : pg.height,
      );
      t = TextEl(
        id: newId(),
        rect: RectD(f.left, f.top, f.right, f.top + f.lineHeight),
        markdown: '',
        color: color,
        fontSize: ruledFontSize(f.lineHeight),
        lineHeight: f.lineHeight,
      );
    } else {
      final w = math.min(320.0, math.max(160.0, pg.width - at.x - 24));
      t = TextEl(id: newId(), rect: RectD(at.x, at.y, at.x + w, at.y + 36), markdown: '', color: color);
    }
    addElement(pageId, t);
    editingTextId = t.id;
    editingTextPageId = pageId;
    notifyListeners();
    return t;
  }

  void startTextEdit(String pageId, String id) {
    beginGesture();
    editingTextId = id;
    editingTextPageId = pageId;
    clearSelection(notify: false);
    notifyListeners();
  }

  /// Live typing: no undo step per keystroke; [finishTextEdit] makes one.
  void typeText(String pageId, String id, String markdown, double height) {
    beginGesture();
    final pg = page(pageId);
    final el = pg.find(id);
    if (el is! TextEl) return;
    final r = el.rect;
    _replacePage(pg.copyWith(elements: [
      for (final x in pg.elements) x.id == id ? el.copyWith(markdown: markdown, rect: RectD(r.left, r.top, r.right, r.top + height)) : x,
    ]));
    _markDirty();
  }

  void finishTextEdit() {
    final pid = editingTextPageId, id = editingTextId;
    editingTextId = null;
    editingTextPageId = null;
    if (pid != null && id != null && pageIndex(pid) >= 0) {
      final el = page(pid).find(id);
      if (el is TextEl && el.markdown.trim().isEmpty) {
        final pg = page(pid);
        _replacePage(pg.copyWith(elements: [for (final x in pg.elements) if (x.id != id) x]));
      }
    }
    endGesture();
    notifyListeners();
  }

  // ---------- images ----------

  String _assetId(Uint8List bytes) => sha1.convert(bytes).toString();

  void addAsset(String id, Uint8List bytes) {
    _note = _note.copyWith(assets: {..._note.assets, id: bytes});
    _markDirty();
  }

  /// Adds an image asset and places it on [pageId], fitted to at most half the page width.
  void addImage(String pageId, Uint8List bytes, int pxW, int pxH, {Vec2? center}) {
    final id = _assetId(bytes);
    _note = _note.copyWith(assets: {..._note.assets, id: bytes});
    final pg = page(pageId);
    final maxW = (_note.layout == NoteLayout.canvas ? 600.0 : pg.width * 0.6);
    final scale = math.min(1.0, maxW / math.max(1, pxW));
    final w = pxW * scale, h = pxH * scale;
    final c = center ?? Vec2(_note.layout == NoteLayout.canvas ? 300 : pg.width / 2, 120 + h / 2);
    final img = ImageEl(id: newId(), rect: RectD(c.x - w / 2, c.y - h / 2, c.x + w / 2, c.y + h / 2), assetId: id);
    addElement(pageId, img);
    selPageId = pageId;
    selIds = {img.id};
    tool = EditorTool.select;
    notifyListeners();
  }

  // ---------- pages ----------

  void addPage({int? after}) {
    final i = after ?? _note.pages.length - 1;
    final ref = _note.pages.isEmpty ? null : _note.pages[i.clamp(0, _note.pages.length - 1)];
    final w = ref?.pdf == null ? (ref?.width ?? _note.pageWidth) : _note.pageWidth;
    final h = ref?.pdf == null ? (ref?.height ?? _note.pageHeight) : _note.pageHeight;
    final pages = [..._note.pages]..insert(i + 1, NotePage.blank(w, h));
    commit(pages);
  }

  void deletePage(int i) {
    if (_note.pages.length <= 1) return;
    commit([..._note.pages]..removeAt(i));
  }

  void duplicatePage(int i) {
    final p = _note.pages[i];
    final copy = NotePage(
      id: newId(),
      width: p.width,
      height: p.height,
      templateOverride: p.templateOverride,
      pdf: p.pdf,
      elements: [for (final e in p.elements) e.withId(newId())],
    );
    commit([..._note.pages]..insert(i + 1, copy));
  }

  void movePage(int from, int to) {
    if (from == to) return;
    final pages = [..._note.pages];
    final p = pages.removeAt(from);
    pages.insert(to.clamp(0, pages.length), p);
    commit(pages);
  }

  /// Text typed on lines follows the new line spacing.
  NotePage _fitLines(NotePage pg, Template t) {
    if (!pg.elements.any((e) => e is TextEl && e.ruled && e.lineHeight != t.spacing)) return pg;
    return pg.copyWith(elements: [for (final e in pg.elements) e is TextEl ? fitTextToLines(e, t.spacing) : e]);
  }

  void setNoteTemplate(Template t) {
    _note = _note.copyWith(
      template: t,
      pages: [for (final p in _note.pages) p.templateOverride == null ? _fitLines(p, t) : p],
    );
    _markDirty();
    notifyListeners();
  }

  void setPageTemplate(String pageId, Template? t) {
    final pg = page(pageId);
    _commitPage(t == null
        ? _fitLines(pg.copyWith(clearTemplateOverride: true), _note.template)
        : _fitLines(pg.copyWith(templateOverride: t), t));
  }

  void rename(String title) {
    _note = _note.copyWith(title: title);
    _markDirty();
    notifyListeners();
  }

  void toggleFavorite() {
    _note = _note.copyWith(favorite: !_note.favorite);
    _markDirty();
    notifyListeners();
  }

  bool get canSwitchLayout => _note.layout != NoteLayout.canvas && _note.pages.every((p) => p.pdf == null);

  /// Paged ⇄ endless. Endless notes are split into pages by element position.
  void switchLayout() {
    if (!canSwitchLayout) return;
    if (_note.layout == NoteLayout.paged) {
      var y = 0.0;
      final els = <Element>[];
      for (final p in _note.pages) {
        final t = Affine.translate(0, y);
        els.addAll(p.elements.map((e) => e.transformed(t)));
        y += p.height;
      }
      final first = _note.pages.first;
      _note = _note.copyWith(layout: NoteLayout.endless);
      commit(layoutBefore: NoteLayout.paged, [NotePage(id: first.id, width: first.width, height: math.max(y, _note.pageHeight), templateOverride: first.templateOverride, elements: els)]);
    } else {
      final pg = _note.pages.first;
      final h = _note.pageHeight;
      final n = math.max(1, (pg.height / h).ceil());
      final buckets = List.generate(n, (_) => <Element>[]);
      for (final e in pg.elements) {
        final i = (e.bounds().top / h).floor().clamp(0, n - 1);
        buckets[i].add(e.transformed(Affine.translate(0, -i * h)));
      }
      _note = _note.copyWith(layout: NoteLayout.paged);
      commit(layoutBefore: NoteLayout.endless, [
        for (var i = 0; i < n; i++)
          NotePage(id: i == 0 ? pg.id : newId(), width: pg.width, height: h, templateOverride: pg.templateOverride, elements: buckets[i]),
      ]);
    }
  }

  // ---------- saving ----------

  void _markDirty() {
    dirty = true;
    if (!autosave || store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), save);
  }

  Future<void> save() async {
    final s = store;
    if (!dirty || s == null) return;
    await _saving;
    dirty = false;
    final n = _note.copyWith(modified: DateTime.now().toUtc(), modifiedBy: deviceName);
    _note = n;
    final done = Completer<void>();
    _saving = done.future;
    try {
      Uint8List? thumb;
      try {
        thumb = await thumbnailer?.call(n);
      } catch (_) {}
      final now = await _stamp();
      if (_diskStamp != null && now != null && now != _diskStamp) {
        // The file was replaced while the note was open: keep that version, don't overwrite it.
        await s.trashItem(relPath, reason: 'Changed elsewhere while this note was open');
      }
      // Zipping (JSON + deflate + CRC of all assets) runs off the UI thread so writing never stutters.
      final bytes = await Isolate.run(() => encodeNote(n, thumb: thumb));
      await s.writeBytesAtomic(relPath, bytes);
      _diskStamp = await _stamp();
    } catch (e) {
      dirty = true;
      rethrow;
    } finally {
      done.complete();
    }
  }

  Future<void> close() async {
    _saveTimer?.cancel();
    if (_gestureBefore != null) endGesture();
    await save();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    live.dispose();
    super.dispose();
  }
}
