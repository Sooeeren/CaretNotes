import 'package:flutter/gestures.dart';

enum InputRole { draw, erase, sideButton, navigate, ignore }

/// Decides what each pointer does: pen draws, eraser end erases, fingers navigate,
/// and touches are ignored while the pen is down or hovering (palm rejection).
class InputRouter {
  bool fingerDrawing;
  InputRouter({required this.fingerDrawing});

  /// Touches within this time after pen activity are treated as a resting palm.
  static const palmWindowMs = 500;

  final Set<int> _stylusDown = {};
  final Set<int> _touchDown = {};
  final Set<int> _cancelled = {};
  final Set<int> _newlyCancelled = {};

  /// A palm that touched down before the pen: cancel it as soon as the pen shows up.
  void _cancelTouches() {
    for (final t in _touchDown) {
      if (_cancelled.add(t)) _newlyCancelled.add(t);
    }
  }

  /// Touch pointers cancelled since the last call; the canvas drops their strokes/gestures.
  Set<int> takeCancelledTouches() {
    final out = Set<int>.of(_newlyCancelled);
    _newlyCancelled.clear();
    return out;
  }

  bool isCancelled(int pointer) => _cancelled.contains(pointer);
  int _lastStylusMs = -1 << 40;

  static bool isStylus(PointerDeviceKind k) => k == PointerDeviceKind.stylus || k == PointerDeviceKind.invertedStylus;

  bool get stylusActive => _stylusDown.isNotEmpty;

  void hover(PointerDeviceKind kind, int timeMs) {
    if (isStylus(kind)) {
      _lastStylusMs = timeMs;
      _cancelTouches();
    }
  }

  InputRole down(int pointer, PointerDeviceKind kind, int buttons, int timeMs) {
    if (isStylus(kind)) {
      _stylusDown.add(pointer);
      _lastStylusMs = timeMs;
      _cancelTouches();
      if (kind == PointerDeviceKind.invertedStylus) return InputRole.erase;
      if (buttons & kSecondaryStylusButton != 0) return InputRole.sideButton;
      return InputRole.draw;
    }
    if (kind == PointerDeviceKind.touch) {
      _touchDown.add(pointer);
      if (_stylusDown.isNotEmpty || timeMs - _lastStylusMs < palmWindowMs) {
        _cancelled.add(pointer);
        return InputRole.ignore;
      }
      return fingerDrawing ? InputRole.draw : InputRole.navigate;
    }
    if (kind == PointerDeviceKind.mouse) {
      if (buttons & kPrimaryMouseButton != 0) return InputRole.draw;
      if (buttons & kMiddleMouseButton != 0) return InputRole.navigate;
      return InputRole.ignore;
    }
    if (kind == PointerDeviceKind.trackpad) return InputRole.navigate;
    return InputRole.ignore;
  }

  void move(int pointer, PointerDeviceKind kind, int timeMs) {
    if (isStylus(kind)) _lastStylusMs = timeMs;
  }

  void up(int pointer, int timeMs) {
    if (_stylusDown.remove(pointer)) _lastStylusMs = timeMs;
    _touchDown.remove(pointer);
    _cancelled.remove(pointer);
    _newlyCancelled.remove(pointer);
  }
}
