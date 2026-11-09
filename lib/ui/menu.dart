import 'package:flutter/material.dart';

/// Popup menu entry with a leading outlined icon, and a check mark on the right when [checked] is set.
PopupMenuItem<T> iconMenuItem<T>(T value, IconData icon, String label, {bool? checked, String? shortcut}) => PopupMenuItem<T>(
      value: value,
      height: 40,
      child: Builder(builder: (context) {
        final t = Theme.of(context);
        final muted = t.colorScheme.onSurfaceVariant;
        return Row(children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 14),
          Expanded(child: Text(label)),
          if (shortcut != null) ...[
            const SizedBox(width: 16),
            Text(shortcut, style: t.textTheme.bodySmall?.copyWith(color: muted)),
          ],
          if (checked != null) ...[
            const SizedBox(width: 12),
            Icon(Icons.check, size: 18, color: checked ? t.colorScheme.primary : Colors.transparent),
          ],
        ]);
      }),
    );
