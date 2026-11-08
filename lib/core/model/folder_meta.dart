enum SortMode { modified, created, name, manual }

/// Stored as `<folder>/.folder.json`. Synced like a note.
class FolderMeta {
  static const fileName = '.folder.json';

  final int color;
  final String icon;
  final SortMode sort;
  final bool ascending;

  /// Manual order: item file names (folders and notes).
  final List<String> order;
  final DateTime? modified;

  const FolderMeta({
    this.color = 0xFF8A94A6,
    this.icon = 'folder',
    this.sort = SortMode.modified,
    this.ascending = false,
    this.order = const [],
    this.modified,
  });

  FolderMeta copyWith({int? color, String? icon, SortMode? sort, bool? ascending, List<String>? order, DateTime? modified}) =>
      FolderMeta(
        color: color ?? this.color,
        icon: icon ?? this.icon,
        sort: sort ?? this.sort,
        ascending: ascending ?? this.ascending,
        order: order ?? this.order,
        modified: modified ?? this.modified,
      );

  Map<String, dynamic> toJson() => {
        'color': color,
        'icon': icon,
        'sort': sort.name,
        'asc': ascending,
        'order': order,
        if (modified != null) 'modified': modified!.toIso8601String(),
      };

  factory FolderMeta.fromJson(Map<String, dynamic> j) => FolderMeta(
        color: j['color'] as int? ?? 0xFF8A94A6,
        icon: j['icon'] as String? ?? 'folder',
        sort: SortMode.values.asNameMap()[j['sort']] ?? SortMode.modified,
        ascending: j['asc'] as bool? ?? false,
        order: (j['order'] as List?)?.cast<String>() ?? const [],
        modified: j['modified'] == null ? null : DateTime.tryParse(j['modified'] as String),
      );
}
