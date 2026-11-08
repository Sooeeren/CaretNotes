import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/geometry.dart';
import '../../core/ink/eraser.dart';
import '../../core/ink/stroke_geometry.dart';
import '../../core/model/elements.dart' hide Element;
import '../../core/model/elements.dart' as m show Element;
import '../../core/model/note.dart';
import '../../core/model/page.dart';
import '../../core/settings.dart';
import 'editor_controller.dart';
import 'input_router.dart';
import 'painters.dart';
import 'pdf_cache.dart';
import 'ruler.dart';
import 'text_box.dart';

const _pageGap = 24.0;

enum _Action { stroke, erase, select, transform, text, pan }

enum _Handle { move, scale, rotate }

class _Ptr {
  final _Action action;
  final String pageId;
  final ToolKind kind;
  InkPoint? last;
  int? rulerSide;
  Offset downScreen;
  Vec2 downLocal;
  bool moved = false;
  _Handle handle = _Handle.move;
  Vec2 anchor = Vec2.zero;
  _Ptr(this.action, this.pageId, this.kind, this.downScreen, this.downLocal);
}

/// Exposes viewport operations to the editor screen (zoom buttons, go to page).
class CanvasHandle {
  _CanvasViewState? _s;
  void zoomBy(double f) => _s?._zoomAt(_s!._viewSize.center(Offset.zero), f);
  void fit() => _s?._fit();
  void showPage(int i) => _s?._showPage(i);
  double get scale => _s?._scale ?? 1;
  Vec2? get visibleCenterLocal => _s?._centerLocal();
  String? get visiblePageId => _s?._visiblePageId();
}

class CanvasView extends StatefulWidget {
  final EditorController controller;
  final AppSettings settings;
  final PdfPageCache pdf;
  final Map<String, ui.Image> images;
  final int imagesVersion;
  final CanvasHandle handle;
  final ValueNotifier<RulerGeom?> ruler;
  const CanvasView({
    super.key,
    required this.controller,
    required this.settings,
    required this.pdf,
    required this.images,
    required this.imagesVersion,
    required this.handle,
    required this.ruler,
  });

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  EditorController get c => widget.controller;
  Note get note => c.note;

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _viewSize = Size.zero;
  bool _init = false;

  late final InputRouter _router = InputRouter(fingerDrawing: widget.settings.fingerDrawing);
  final Map<int, _Ptr> _ptrs = {};
  final Map<int, Offset> _touches = {};
  final Map<int, Offset> _touchStart = {};
  double _pinchScale = 1;
  Offset _pinchOffset = Offset.zero;
  bool _rulerGesture = false;
  RulerGeom? _rulerStart;
  Offset? _hover;

  Timer? _holdTimer;
  Offset _holdAnchor = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.handle._s = this;
    c.addListener(_onChange);
    widget.pdf.addListener(_onChange);
    widget.ruler.addListener(_onChange);
  }

  @override
  void didUpdateWidget(CanvasView old) {
    super.didUpdateWidget(old);
    widget.handle._s = this;
    _router.fingerDrawing = widget.settings.fingerDrawing;
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    c.removeListener(_onChange);
    widget.pdf.removeListener(_onChange);
    widget.ruler.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // ---------- layout ----------

  bool get _isCanvas => note.layout == NoteLayout.canvas;

  List<Offset> get _origins {
    if (_isCanvas) return [Offset.zero];
    final maxW = note.pages.fold<double>(0, (m, p) => math.max(m, p.width));
    final out = <Offset>[];
    var y = 0.0;
    for (final p in note.pages) {
      out.add(Offset((maxW - p.width) / 2, y));
      y += p.height + _pageGap;
    }
    return out;
  }

  double get _docWidth => note.pages.fold<double>(0, (m, p) => math.max(m, p.width));
  double get _docHeight {
    final o = _origins;
    return o.isEmpty ? 0 : o.last.dy + note.pages.last.height;
  }

  Offset _toScreen(Offset doc) => doc * _scale + _offset;
  Offset _toDoc(Offset screen) => (screen - _offset) / _scale;
  Offset _vecScreen(Vec2 global) => _toScreen(Offset(global.x, global.y));

  /// Page index and page-local point under a screen position.
  (int, Vec2) _hitPage(Offset screen) {
    final d = _toDoc(screen);
    if (_isCanvas) return (0, Vec2(d.dx, d.dy));
    final o = _origins;
    var best = 0;
    for (var i = 0; i < o.length; i++) {
      if (d.dy >= o[i].dy - _pageGap / 2) best = i;
    }
    return (best, Vec2(d.dx - o[best].dx, d.dy - o[best].dy));
  }

  Offset _pageOrigin(String pageId) {
    final i = c.pageIndex(pageId);
    if (i < 0) return Offset.zero;
    return _origins[i];
  }

  Vec2 _localToGlobal(String pageId, Vec2 l) {
    final o = _pageOrigin(pageId);
    return Vec2(l.x + o.dx, l.y + o.dy);
  }

  Vec2 _globalToLocal(String pageId, Vec2 g) {
    final o = _pageOrigin(pageId);
    return Vec2(g.x - o.dx, g.y - o.dy);
  }

  double get _minScale => _isCanvas ? 0.08 : 0.25;
  double get _maxScale => 8;

  void _fit() {
    if (_viewSize.isEmpty) return;
    if (_isCanvas) {
      _scale = 1;
      _offset = const Offset(40, 40);
    } else {
      _scale = ((_viewSize.width - 48) / _docWidth).clamp(_minScale, 1.6);
      _offset = Offset((_viewSize.width - _docWidth * _scale) / 2, 24);
    }
    setState(() {});
  }

  void _showPage(int i) {
    if (_isCanvas || i < 0 || i >= note.pages.length) return;
    final o = _origins[i];
    _offset = Offset(_offset.dx, 24 - o.dy * _scale);
    _clamp();
    setState(() {});
  }

  Vec2 _centerLocal() {
    final (_, l) = _hitPage(_viewSize.center(Offset.zero));
    return l;
  }

  String _visiblePageId() => note.pages[_hitPage(_viewSize.center(Offset.zero)).$1].id;

  void _clamp() {
    if (_isCanvas || _viewSize.isEmpty) return;
    final w = _docWidth * _scale, h = _docHeight * _scale;
    double dx = _offset.dx, dy = _offset.dy;
    if (w + 48 <= _viewSize.width) {
      dx = (_viewSize.width - w) / 2;
    } else {
      dx = dx.clamp(_viewSize.width - w - 24, 24);
    }
    final minY = math.min(24.0, _viewSize.height - h - 120);
    dy = dy.clamp(minY, 24.0);
    _offset = Offset(dx, dy);
  }

  void _zoomAt(Offset focal, double factor) {
    final ns = (_scale * factor).clamp(_minScale, _maxScale);
    final doc = _toDoc(focal);
    _scale = ns;
    _offset = focal - doc * ns;
    _clamp();
    setState(() {});
  }

  void _panBy(Offset d) {
    _offset += d;
    _clamp();
    setState(() {});
  }

  // ---------- input ----------

  double _pressure(PointerEvent e) {
    if (!InputRouter.isStylus(e.kind)) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.05, 1.0);
  }

  _Action _actionForTool() => switch (c.tool) {
        EditorTool.pen || EditorTool.highlighter => _Action.stroke,
        EditorTool.eraser => _Action.erase,
        EditorTool.select => _Action.select,
        EditorTool.text => _Action.text,
      };

  void _onDown(PointerDownEvent e) {
    final ms = e.timeStamp.inMilliseconds;
    final role = _router.down(e.pointer, e.kind, e.buttons, ms);
    if (role == InputRole.ignore) return;
    if (role == InputRole.navigate) {
      _touches[e.pointer] = e.localPosition;
      _startNav();
      return;
    }
    if (_touches.isNotEmpty && e.kind == PointerDeviceKind.touch) return;
    if (c.editingTextId != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      c.finishTextEdit();
    }
    var action = switch (role) {
      InputRole.erase => _Action.erase,
      InputRole.sideButton => widget.settings.sideButton == SideButtonAction.eraser ? _Action.erase : _Action.select,
      _ => _actionForTool(),
    };
    final (pi, local) = _hitPage(e.localPosition);
    final pg = note.pages[pi];
    if (action == _Action.select && c.hasSelection) {
      final h = _handleAt(e.localPosition);
      if (h != null) action = _Action.transform;
    }
    final kind = c.tool == EditorTool.highlighter && action == _Action.stroke ? ToolKind.highlighter : c.penKind;
    final ptr = _Ptr(action, pg.id, kind, e.localPosition, local);
    _ptrs[e.pointer] = ptr;
    switch (action) {
      case _Action.stroke:
        var p = InkPoint(local.x, local.y, _pressure(e));
        final r = widget.ruler.value;
        if (c.rulerVisible && r != null) {
          final g = _localToGlobal(pg.id, local);
          final side = r.edgeNear(g, 14 / _scale + 4);
          if (side != null) {
            ptr.rulerSide = side;
            final q = _globalToLocal(pg.id, r.project(g, side));
            p = InkPoint(q.x, q.y, p.p);
          }
        }
        ptr.last = p;
        c.beginStroke(pg.id, p, kind);
        _restartHold(e.localPosition, ptr);
      case _Action.erase:
        c.beginErase();
        c.eraseAt(pg.id, local);
      case _Action.select:
        c.clearSelection(notify: false);
        c.live
          ..pageId = pg.id
          ..selectPath = c.selectMode == SelectMode.lasso ? [local] : null
          ..selectBox = c.selectMode == SelectMode.box ? RectD(local.x, local.y, local.x, local.y) : null;
        c.live.changed();
      case _Action.transform:
        final h = _handleAt(e.localPosition)!;
        final selPage = c.selPageId!;
        final sel = c.selectionRect!;
        ptr.handle = h;
        // operate in the selection's page coords
        final docPt = _toDoc(e.localPosition);
        final o = _pageOrigin(selPage);
        final lp = Vec2(docPt.dx - o.dx, docPt.dy - o.dy);
        ptr.downLocal = lp;
        if (h == _Handle.scale) {
          final corners = sel.corners;
          var far = corners.first;
          for (final k in corners) {
            if (k.dist(lp) > far.dist(lp)) far = k;
          }
          ptr.anchor = far;
        } else {
          ptr.anchor = sel.center;
        }
        _ptrs[e.pointer] = _Ptr(_Action.transform, selPage, kind, e.localPosition, lp)
          ..handle = h
          ..anchor = ptr.anchor;
        c.beginTransform();
      case _Action.text:
      case _Action.pan:
        break;
    }
  }

  void _onMove(PointerMoveEvent e) {
    final ms = e.timeStamp.inMilliseconds;
    _router.move(e.pointer, e.kind, ms);
    if (_touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      _updateNav();
      return;
    }
    final ptr = _ptrs[e.pointer];
    if (ptr == null) return;
    if ((e.localPosition - ptr.downScreen).distance > 3) ptr.moved = true;
    final o = _pageOrigin(ptr.pageId);
    final d = _toDoc(e.localPosition);
    final local = Vec2(d.dx - o.dx, d.dy - o.dy);
    switch (ptr.action) {
      case _Action.stroke:
        var raw = InkPoint(local.x, local.y, _pressure(e));
        final r = widget.ruler.value;
        if (ptr.rulerSide != null && r != null) {
          final q = _globalToLocal(ptr.pageId, r.project(_localToGlobal(ptr.pageId, local), ptr.rulerSide!));
          raw = InkPoint(q.x, q.y, raw.p);
        }
        final sm = ptr.last == null || ptr.rulerSide != null ? raw : smoothPoint(ptr.last!, raw, 0.6);
        ptr.last = sm;
        c.extendStroke(sm);
        if ((e.localPosition - _holdAnchor).distance > 4) _restartHold(e.localPosition, ptr);
      case _Action.erase:
        c.eraseAt(ptr.pageId, local);
        _hover = e.localPosition;
      case _Action.select:
        if (c.live.selectPath != null) {
          c.live.selectPath!.add(local);
        } else if (c.live.selectBox != null) {
          c.live.selectBox = RectD(ptr.downLocal.x, ptr.downLocal.y, local.x, local.y);
        }
        c.live.changed();
      case _Action.transform:
        final a = ptr.anchor, s0 = ptr.downLocal;
        Affine t;
        switch (ptr.handle) {
          case _Handle.move:
            t = Affine.translate(local.x - s0.x, local.y - s0.y);
          case _Handle.scale:
            final d0 = s0.dist(a);
            final f = d0 < 1 ? 1.0 : (local.dist(a) / d0).clamp(0.05, 20.0);
            t = Affine.about(a, Affine.scale(f));
          case _Handle.rotate:
            final ang = math.atan2(local.y - a.y, local.x - a.x) - math.atan2(s0.y - a.y, s0.x - a.x);
            t = Affine.about(a, Affine.rotate(ang));
        }
        c.previewTransform(t);
      case _Action.text:
      case _Action.pan:
        break;
    }
  }

  void _onUp(PointerEvent e, {bool cancel = false}) {
    _router.up(e.pointer, e.timeStamp.inMilliseconds);
    if (_touches.remove(e.pointer) != null) {
      _touchStart.remove(e.pointer);
      _startNav();
      return;
    }
    final ptr = _ptrs.remove(e.pointer);
    if (ptr == null) return;
    _holdTimer?.cancel();
    switch (ptr.action) {
      case _Action.stroke:
        if (cancel) {
          c.cancelStroke();
        } else {
          c.endStroke();
        }
      case _Action.erase:
        c.endErase();
      case _Action.select:
        final path = c.live.selectPath, box = c.live.selectBox;
        c.live.clear();
        if (!ptr.moved) {
          _tapSelect(ptr.pageId, ptr.downLocal);
        } else if (path != null && path.length > 2) {
          c.selectLasso(ptr.pageId, path);
        } else if (box != null) {
          final r = RectD(math.min(box.left, box.right), math.min(box.top, box.bottom), math.max(box.left, box.right), math.max(box.top, box.bottom));
          c.selectBox(ptr.pageId, r);
        }
      case _Action.transform:
        c.endTransform();
      case _Action.text:
        if (!cancel) _tapText(ptr.pageId, ptr.downLocal);
      case _Action.pan:
        break;
    }
  }

  void _restartHold(Offset pos, _Ptr ptr) {
    _holdAnchor = pos;
    _holdTimer?.cancel();
    if (ptr.rulerSide != null) return;
    _holdTimer = Timer(const Duration(milliseconds: 450), () {
      if (_ptrs.values.contains(ptr) && c.snapLiveToShape()) HapticFeedback.selectionClick();
    });
  }

  m.Element? _elementAt(String pageId, Vec2 p) {
    final pg = c.page(pageId);
    for (final e in pg.elements.reversed) {
      switch (e) {
        case StrokeEl s:
          if (strokeHit(s, p, 6 / _scale)) return e;
        default:
          if (e.bounds().contains(p)) return e;
      }
    }
    return null;
  }

  void _tapSelect(String pageId, Vec2 p) {
    final e = _elementAt(pageId, p);
    if (e == null) {
      c.clearSelection();
    } else {
      c.selectOnly(pageId, e.id);
    }
  }

  void _tapText(String pageId, Vec2 p) {
    final pg = c.page(pageId);
    for (final e in pg.elements.reversed) {
      if (e is TextEl && e.rect.inflate(4).contains(p)) {
        c.startTextEdit(pageId, e.id);
        return;
      }
    }
    c.addText(pageId, p);
  }

  _Handle? _handleAt(Offset screen) {
    final r = c.selectionRect;
    if (r == null) return null;
    final o = _pageOrigin(c.selPageId!);
    final tl = _toScreen(Offset(r.left + o.dx, r.top + o.dy));
    final br = _toScreen(Offset(r.right + o.dx, r.bottom + o.dy));
    final rect = Rect.fromPoints(tl, br).inflate(6);
    final rot = Offset(rect.center.dx, rect.top - 28);
    if ((screen - rot).distance < 16) return _Handle.rotate;
    for (final k in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      if ((screen - k).distance < 16) return _Handle.scale;
    }
    if (rect.contains(screen)) return _Handle.move;
    return null;
  }

  void _startNav() {
    _touchStart
      ..clear()
      ..addAll(_touches);
    _pinchScale = _scale;
    _pinchOffset = _offset;
    _rulerGesture = false;
    final r = widget.ruler.value;
    if (_touches.length == 2 && c.rulerVisible && r != null) {
      final pts = _touches.values.map((p) => _toDoc(p)).toList();
      if (pts.every((p) => r.contains(Vec2(p.dx, p.dy), margin: 30 / _scale))) {
        _rulerGesture = true;
        _rulerStart = r;
      }
    }
  }

  void _updateNav() {
    final ids = _touchStart.keys.where(_touches.containsKey).toList();
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      final id = ids.first;
      _offset = _pinchOffset + (_touches[id]! - _touchStart[id]!);
      _clamp();
      setState(() {});
      return;
    }
    final a0 = _touchStart[ids[0]]!, b0 = _touchStart[ids[1]]!, a1 = _touches[ids[0]]!, b1 = _touches[ids[1]]!;
    if (_rulerGesture && _rulerStart != null) {
      Vec2 dv(Offset s) {
        final d = (s - _offset) / _scale;
        return Vec2(d.dx, d.dy);
      }

      widget.ruler.value = _rulerStart!.twoFinger(dv(a0), dv(b0), dv(a1), dv(b1));
      return;
    }
    final d0 = (b0 - a0).distance, d1 = (b1 - a1).distance;
    if (d0 < 1) return;
    final ns = (_pinchScale * d1 / d0).clamp(_minScale, _maxScale);
    final f0 = (a0 + b0) / 2, f1 = (a1 + b1) / 2;
    final docFocal = (f0 - _pinchOffset) / _pinchScale;
    _scale = ns;
    _offset = f1 - docFocal * ns;
    _clamp();
    setState(() {});
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final keys = HardwareKeyboard.instance;
      if (keys.isControlPressed) {
        _zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 400));
      } else if (keys.isShiftPressed) {
        _panBy(Offset(-e.scrollDelta.dy, 0));
      } else {
        _panBy(-e.scrollDelta);
      }
    } else if (e is PointerScaleEvent) {
      _zoomAt(e.localPosition, e.scale);
    }
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final size = Size(cons.maxWidth, cons.maxHeight);
      if (size != _viewSize) {
        _viewSize = size;
        if (!_init) {
          _init = true;
          _fit();
        } else {
          _clamp();
        }
      }
      final dark = Theme.of(context).brightness == Brightness.dark;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final assets = RenderAssets(
        images: widget.images,
        pdfImage: (p) => widget.pdf.imageFor(p, pxFor(p.width, _scale, dpr)),
      );
      final editingId = c.editingTextId;
      final children = <Widget>[
        Positioned.fill(child: ColoredBox(color: dark ? const Color(0xFF101215) : const Color(0xFFE9EAEE))),
      ];
      final textWidgets = <Widget>[];
      Widget? editor;

      if (_isCanvas) {
        final pg = note.pages.first;
        final tl = _toDoc(Offset.zero), br = _toDoc(Offset(size.width, size.height));
        children.add(Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: PagePainter(
                note: note,
                page: pg,
                assets: assets,
                scale: _scale,
                assetsVersion: widget.imagesVersion,
                area: Rect.fromPoints(tl, br),
              ),
            ),
          ),
        ));
        _texts(pg, Offset.zero, editingId, textWidgets, (w) => editor = w);
      } else {
        final o = _origins;
        final view = Offset.zero & size;
        for (var i = 0; i < note.pages.length; i++) {
          final pg = note.pages[i];
          final r = Rect.fromLTWH(_toScreen(o[i]).dx, _toScreen(o[i]).dy, pg.width * _scale, pg.height * _scale);
          if (!r.overlaps(view.inflate(200))) continue;
          children.add(Positioned.fromRect(
            rect: r,
            child: DecoratedBox(
              decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 2))]),
              child: RepaintBoundary(
                child: CustomPaint(
                  size: r.size,
                  painter: PagePainter(note: note, page: pg, assets: assets, scale: _scale, assetsVersion: widget.imagesVersion),
                ),
              ),
            ),
          ));
          _texts(pg, o[i], editingId, textWidgets, (w) => editor = w);
        }
      }

      children.addAll(textWidgets);
      children.add(Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(painter: _LivePainter(c.live, _scale, _offset, _pageOrigin, c, _hover, dark)),
          ),
        ),
      ));
      final ruler = widget.ruler.value;
      if (c.rulerVisible && ruler != null) {
        children.add(Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: RulerPainter(ruler, _scale, _vecScreen, dark))),
        ));
      }

      children.add(Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: (e) => _onUp(e),
          onPointerCancel: (e) => _onUp(e, cancel: true),
          onPointerHover: (e) {
            _router.hover(e.kind, e.timeStamp.inMilliseconds);
            if (c.tool == EditorTool.eraser || e.kind == PointerDeviceKind.invertedStylus) {
              setState(() => _hover = e.localPosition);
            } else if (_hover != null) {
              setState(() => _hover = null);
            }
          },
          onPointerSignal: _onSignal,
          onPointerPanZoomUpdate: (e) {
            if (e.scale != 1) {
              _zoomAt(e.localPosition, 1 + (e.scale - 1) * 0.1);
            }
            _panBy(e.panDelta);
          },
          child: MouseRegion(
            cursor: switch (c.tool) {
              EditorTool.text => SystemMouseCursors.text,
              EditorTool.select => SystemMouseCursors.precise,
              _ => SystemMouseCursors.precise,
            },
            onExit: (_) => setState(() => _hover = null),
          ),
        ),
      ));

      if (editor != null) children.add(editor!);
      if (c.hasSelection && c.editingTextId == null) children.add(_selectionBar(context));
      return ClipRect(child: Stack(children: children));
    });
  }

  void _texts(NotePage pg, Offset origin, String? editingId, List<Widget> out, void Function(Widget) setEditor) {
    for (final e in pg.elements) {
      if (e is! TextEl) continue;
      final tl = _toScreen(Offset(e.rect.left + origin.dx, e.rect.top + origin.dy));
      if (tl.dy > _viewSize.height + 50 || tl.dy + e.rect.height * _scale < -50) continue;
      if (e.id == editingId) {
        setEditor(Positioned(
          left: tl.dx,
          top: tl.dy,
          child: ScaledBox(
            width: e.rect.width,
            height: e.rect.height,
            scale: _scale,
            child: TextBoxEditor(
              key: ValueKey('edit-${e.id}'),
              el: e,
              onChanged: (md, h) => c.typeText(pg.id, e.id, md, h),
              onDone: () {
                if (c.editingTextId == e.id) c.finishTextEdit();
              },
            ),
          ),
        ));
      } else {
        out.add(Positioned(
          left: tl.dx,
          top: tl.dy,
          child: IgnorePointer(
            child: ScaledBox(width: e.rect.width, height: e.rect.height, scale: _scale, child: RenderedMarkdown(el: e)),
          ),
        ));
      }
    }
  }

  Widget _selectionBar(BuildContext context) {
    final r = c.selectionRect!;
    final o = _pageOrigin(c.selPageId!);
    final tl = _toScreen(Offset(r.left + o.dx, r.top + o.dy));
    final br = _toScreen(Offset(r.right + o.dx, r.bottom + o.dy));
    final top = tl.dy - 92 < 8 ? br.dy + 16 : tl.dy - 92;
    final double left = ((tl.dx + br.dx) / 2 - 170).clamp(8.0, math.max(8.0, _viewSize.width - 348)).toDouble();
    final sel = c.selectedElements;
    final single = sel.length == 1 ? sel.first : null;
    return Positioned(
      left: left,
      top: top,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final col in widget.settings.penColors.take(5))
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => c.recolorSelection(col),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: CircleAvatar(radius: 9, backgroundColor: Color(col)),
                ),
              ),
            const SizedBox(width: 4),
            if (single is TextEl)
              IconButton(
                tooltip: 'Edit text',
                icon: const Icon(Icons.edit_rounded, size: 20),
                onPressed: () => c.startTextEdit(c.selPageId!, single.id),
              ),
            if (single is ImageEl)
              IconButton(
                tooltip: single.behindInk ? 'Bring in front of ink' : 'Send behind ink',
                icon: Icon(single.behindInk ? Icons.flip_to_front_rounded : Icons.flip_to_back_rounded, size: 20),
                onPressed: () => c.replaceElement(c.selPageId!, single.copyWith(behindInk: !single.behindInk)),
              ),
            if (single is ImageEl)
              IconButton(
                tooltip: 'Crop',
                icon: const Icon(Icons.crop_rounded, size: 20),
                onPressed: () => cropImageAction?.call(context, c, single),
              ),
            IconButton(tooltip: 'Duplicate', icon: const Icon(Icons.control_point_duplicate_rounded, size: 20), onPressed: c.duplicateSelection),
            IconButton(tooltip: 'Copy', icon: const Icon(Icons.copy_rounded, size: 20), onPressed: c.copySelection),
            IconButton(tooltip: 'Cut', icon: const Icon(Icons.content_cut_rounded, size: 20), onPressed: c.cutSelection),
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded, size: 20), onPressed: c.deleteSelection),
          ]),
        ),
      ),
    );
  }
}

/// Image crop UI is provided by image_box.dart.
Future<void> Function(BuildContext, EditorController, ImageEl)? cropImageAction;

class _LivePainter extends CustomPainter {
  final LiveInk live;
  final double scale;
  final Offset offset;
  final Offset Function(String) origin;
  final EditorController c;
  final Offset? hover;
  final bool dark;
  _LivePainter(this.live, this.scale, this.offset, this.origin, this.c, this.hover, this.dark) : super(repaint: live);

  @override
  void paint(Canvas canvas, Size size) {
    final pid = live.pageId;
    if (pid != null) {
      final o = origin(pid);
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.scale(scale);
      canvas.translate(o.dx, o.dy);
      if (live.points.isNotEmpty) {
        final path = pathFromOutline(strokeOutline(live.points, live.width, live.tool));
        canvas.drawPath(path, strokePaint(live.tool, live.color));
      }
      final dash = Paint()
        ..color = const Color(0xFF3B6FE0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / scale;
      if (live.selectPath != null && live.selectPath!.length > 1) {
        final p = ui.Path()..moveTo(live.selectPath!.first.x, live.selectPath!.first.y);
        for (final v in live.selectPath!.skip(1)) {
          p.lineTo(v.x, v.y);
        }
        canvas.drawPath(p, dash);
      }
      if (live.selectBox != null) {
        final b = live.selectBox!;
        canvas.drawRect(Rect.fromLTRB(b.left, b.top, b.right, b.bottom), dash);
        canvas.drawRect(Rect.fromLTRB(b.left, b.top, b.right, b.bottom), Paint()..color = const Color(0x143B6FE0));
      }
      canvas.restore();
    }
    // selection frame
    final r = c.selectionRect;
    if (r != null && c.selPageId != null) {
      final o = origin(c.selPageId!);
      final tl = Offset(r.left + o.dx, r.top + o.dy) * scale + offset;
      final br = Offset(r.right + o.dx, r.bottom + o.dy) * scale + offset;
      final rect = Rect.fromPoints(tl, br).inflate(6);
      final line = Paint()
        ..color = const Color(0xFF3B6FE0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawRect(rect, line);
      final fill = Paint()..color = Colors.white;
      for (final k in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
        canvas.drawCircle(k, 7, fill);
        canvas.drawCircle(k, 7, line);
      }
      final rot = Offset(rect.center.dx, rect.top - 28);
      canvas.drawLine(Offset(rect.center.dx, rect.top), rot, line);
      canvas.drawCircle(rot, 8, fill);
      canvas.drawCircle(rot, 8, line);
    }
    if (hover != null && (c.tool == EditorTool.eraser)) {
      canvas.drawCircle(
          hover!,
          c.eraserSize * scale,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = dark ? Colors.white70 : Colors.black54);
    }
  }

  @override
  bool shouldRepaint(_LivePainter old) => true;
}
