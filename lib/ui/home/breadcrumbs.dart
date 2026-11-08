import 'package:flutter/material.dart';

/// "All notes › Semester 3 › Lineare Algebra" path bar.
class Breadcrumbs extends StatelessWidget {
  final String relDir;
  final ValueChanged<String> onOpen;
  const Breadcrumbs({super.key, required this.relDir, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final parts = relDir.isEmpty ? <String>[] : relDir.split('/');
    final t = Theme.of(context);
    final items = <Widget>[
      _crumb(context, 'All notes', '', parts.isEmpty, const ValueKey('crumb-root')),
    ];
    for (var i = 0; i < parts.length; i++) {
      items.add(Icon(Icons.chevron_right, size: 18, color: t.colorScheme.onSurfaceVariant));
      items.add(_crumb(context, parts[i], parts.sublist(0, i + 1).join('/'), i == parts.length - 1, ValueKey('crumb-${parts[i]}')));
    }
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: items));
  }

  Widget _crumb(BuildContext context, String label, String target, bool last, Key key) {
    final t = Theme.of(context);
    return TextButton(
      key: key,
      onPressed: last ? null : () => onOpen(target),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 36),
        foregroundColor: t.colorScheme.onSurfaceVariant,
        disabledForegroundColor: t.colorScheme.onSurface,
      ),
      child: Text(label, style: last ? t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600) : t.textTheme.bodyLarge),
    );
  }
}
