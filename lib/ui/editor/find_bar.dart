import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/find.dart';
import '../theme.dart';
import 'editor_controller.dart';

/// "Find in note" strip under the note bar: type, then step through the text
/// boxes that contain the words. [onReveal] scrolls the page to a hit.
class FindBar extends StatefulWidget {
  final EditorController c;
  final void Function(FindHit hit) onReveal;
  final VoidCallback onClose;
  const FindBar({super.key, required this.c, required this.onReveal, required this.onClose});

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final _text = TextEditingController();
  List<FindHit> _hits = const [];
  int _i = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _search(String q) {
    setState(() {
      _hits = findInNote(widget.c.note, q);
      _i = 0;
    });
    _show();
  }

  void _step(int d) {
    // The note may have changed since the search, so search again before stepping.
    final fresh = findInNote(widget.c.note, _text.text);
    setState(() {
      _hits = fresh;
      if (_hits.isNotEmpty) _i = (_i + d) % _hits.length;
    });
    _show();
  }

  void _show() {
    if (_hits.isEmpty) {
      widget.c.showFindHit(null);
      return;
    }
    final h = _hits[_i.clamp(0, _hits.length - 1)];
    widget.c.showFindHit(h);
    widget.onReveal(h);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tk = AppTokens.of(context);
    final q = _text.text.trim();
    final label = q.isEmpty
        ? 'Searches typed text'
        : _hits.isEmpty
        ? 'No matches'
        : '${_i + 1} of ${_hits.length}';
    return Material(
      color: t.colorScheme.surfaceContainerLow,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tk.hairline)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: tk.muted),
            const SizedBox(width: 8),
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
                  const SingleActivator(LogicalKeyboardKey.enter, shift: true): () => _step(-1),
                },
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Find in note', border: InputBorder.none, isDense: true),
                  onChanged: _search,
                  onSubmitted: (_) => _step(1),
                  onEditingComplete: () {}, // keep focus after Enter, so Enter steps again
                ),
              ),
            ),
            Text(label, style: t.textTheme.bodySmall?.copyWith(color: tk.muted)),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Previous (Shift+Enter)',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: _hits.isEmpty ? null : () => _step(-1),
            ),
            IconButton(
              tooltip: 'Next (Enter)',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: _hits.isEmpty ? null : () => _step(1),
            ),
            IconButton(tooltip: 'Close (Esc)', icon: const Icon(Icons.close), onPressed: widget.onClose),
          ],
        ),
      ),
    );
  }
}
