import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// The app's own title bar, as in CaretFlow: no system caption, the window buttons sit
/// at the right end of each screen's header and the header's empty space moves the window.
class WindowChrome {
  WindowChrome._();

  /// Windows desktop only, and never inside `flutter test`.
  static final bool supported = Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST');

  /// True while the app draws its own title bar.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  /// What the close button does. Asks the app to exit as if the window were closed, so
  /// AppLifecycleListener.onExitRequested runs first (open notes are saved). Tests swap it.
  static Future<void> Function() requestClose = () => ServicesBinding.instance.exitApplication(ui.AppExitType.cancelable);

  static const minimumSize = Size(480, 400);

  static Window? get _window => supported ? WindowManager.instance.getCurrent() : null;

  /// Hides or restores the system title bar.
  static void apply({required bool custom}) {
    final w = _window;
    if (w == null) return;
    w.titleBarStyle = custom ? TitleBarStyle.hidden : TitleBarStyle.normal;
    // Small enough for half a laptop screen, big enough that headers keep room to grab.
    w.minimumSize = minimumSize.toNative();
    active.value = custom;
  }

  /// Full screen: the window covers the whole display (Windows), or the system bars
  /// hide (Android). Nothing happens in tests.
  static Future<void> setFullScreen(bool on) async {
    final w = _window;
    if (w != null) {
      w.isFullScreen = on;
    } else if ((Platform.isAndroid || Platform.isIOS) && !Platform.environment.containsKey('FLUTTER_TEST')) {
      await SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }
}

/// A label inside a header that should move the window too: a drag on it moves the
/// window, a tap still reaches [child]. Small windows leave little empty header to grab.
class CaptionDrag extends StatelessWidget {
  final Widget child;
  const CaptionDrag({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WindowChrome.active,
      builder: (context, on, _) => on ? DragToMoveArea(child: child) : child,
    );
  }
}

/// Wraps a header: the empty space behind [child] drags the window, a double click
/// maximizes, a right click opens the system menu. Buttons inside [child] work as usual.
class CaptionArea extends StatelessWidget {
  final Widget child;
  const CaptionArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WindowChrome.active,
      builder: (context, on, _) {
        if (!on) return child;
        return Stack(fit: StackFit.passthrough, children: [
          // Not const: the test compiler rejects DragToMoveArea in a const expression.
          // ignore: prefer_const_constructors
          Positioned.fill(child: DragToMoveArea(child: const SizedBox.expand())),
          child,
        ]);
      },
    );
  }
}

/// Minimize, maximize/restore and close, Fluent style (Segoe Fluent Icons glyphs,
/// 46 px wide, full height, red close hover). Nothing when the system title bar is used.
class WindowButtons extends StatefulWidget {
  final double height;

  /// Space before the buttons, and the width taken instead when they are hidden.
  final double gap, inactiveWidth;
  const WindowButtons({super.key, required this.height, this.gap = 0, this.inactiveWidth = 0});

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> {
  static const _min = '', _max = '', _restore = '', _close = '';
  bool _maximized = false;
  ListenerId? _listener;

  @override
  void initState() {
    super.initState();
    final w = WindowChrome._window;
    if (w == null) return;
    _maximized = w.isMaximized;
    _listener = WindowManager.instance.addListener((e) {
      if (e is WindowMaximizedEvent || e is WindowRestoredEvent || e is WindowResizedEvent) {
        final m = w.isMaximized;
        if (m != _maximized && mounted) setState(() => _maximized = m);
      }
    });
  }

  @override
  void dispose() {
    final id = _listener;
    if (id != null) WindowManager.instance.removeListener(id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WindowChrome.active,
      builder: (context, on, _) {
        if (!on) return SizedBox(width: widget.inactiveWidth);
        final w = WindowChrome._window;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: widget.gap),
          _CaptionButton(glyph: _min, tooltip: 'Minimize', height: widget.height, onTap: () => w?.minimize()),
          MaximizeButtonArea(
            child: _CaptionButton(
              glyph: _maximized ? _restore : _max,
              tooltip: _maximized ? 'Restore' : 'Maximize',
              height: widget.height,
              onTap: () => _maximized ? w?.unmaximize() : w?.maximize(),
            ),
          ),
          _CaptionButton(
            glyph: _close,
            tooltip: 'Close',
            height: widget.height,
            close: true,
            onTap: () => WindowChrome.requestClose(),
          ),
        ]);
      },
    );
  }
}

class _CaptionButton extends StatefulWidget {
  final String glyph;
  final String tooltip;
  final double height;
  final bool close;
  final VoidCallback onTap;
  const _CaptionButton({required this.glyph, required this.tooltip, required this.height, required this.onTap, this.close = false});

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onSurface;
    final Color bg;
    Color color = fg;
    if (widget.close && (_hover || _down)) {
      bg = _down ? const Color(0xFFC42B1C).withValues(alpha: 0.85) : const Color(0xFFC42B1C);
      color = Colors.white;
    } else {
      bg = _down ? fg.withValues(alpha: 0.15) : (_hover ? fg.withValues(alpha: 0.09) : Colors.transparent);
    }
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = _down = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTap: () {
            setState(() => _down = false);
            widget.onTap();
          },
          child: Container(
            width: 46,
            height: widget.height,
            color: bg,
            alignment: Alignment.center,
            child: Text(
              widget.glyph,
              style: TextStyle(
                fontFamily: 'Segoe Fluent Icons',
                fontFamilyFallback: const ['Segoe MDL2 Assets'],
                fontSize: 10,
                height: 1,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A slim title strip for screens without a header of their own (editor toolbar docked
/// at the side or floating): the note title centered, window buttons on the right.
class CaptionStrip extends StatelessWidget {
  final String title;
  const CaptionStrip({super.key, required this.title});

  static const height = 34.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: WindowChrome.active,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: t.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: t.dividerColor)),
          ),
          child: CaptionArea(
            child: Row(children: [
              const SizedBox(width: 46 * 3),
              Expanded(
                child: IgnorePointer(
                  child: Text(
                    '$title — CaretNotes',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(fontSize: 12.5),
                  ),
                ),
              ),
              const WindowButtons(height: height),
            ]),
          ),
        );
      },
    );
  }
}
