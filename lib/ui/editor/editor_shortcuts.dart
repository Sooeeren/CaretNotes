import 'package:flutter/widgets.dart';

import 'editor_controller.dart';

/// Editor-wide keyboard shortcuts (undo, delete selection, zoom, ...).
///
/// They are switched off while a text box is being edited, so keys like Backspace
/// and Ctrl+Z reach the text field. Rebuilds with [c], because editing starts and
/// stops without the editor screen itself rebuilding.
class EditorShortcuts extends StatelessWidget {
  final EditorController c;
  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;
  final FocusNode? focusNode;
  const EditorShortcuts({super.key, required this.c, required this.bindings, required this.child, this.focusNode});

  /// True when the keyboard focus is inside a text field (text box, rename field, ...).
  static bool get typingInTextField {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, child) => CallbackShortcuts(
          bindings: c.editingTextId != null
              ? const {}
              : {
                  for (final e in bindings.entries)
                    e.key: () {
                      if (!typingInTextField) e.value();
                    },
                },
          child: child!,
        ),
        child: Focus(focusNode: focusNode, autofocus: true, child: child),
      );
}
