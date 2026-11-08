import 'package:flutter/material.dart';

/// Built-in folder icons, stored by key in `.folder.json`. One outlined family, one stroke.
const folderIcons = <String, IconData>{
  'folder': Icons.folder_outlined,
  'school': Icons.school_outlined,
  'book': Icons.menu_book_outlined,
  'functions': Icons.functions_outlined,
  'calculate': Icons.calculate_outlined,
  'science': Icons.science_outlined,
  'biotech': Icons.biotech_outlined,
  'atom': Icons.hub_outlined,
  'code': Icons.code_outlined,
  'computer': Icons.computer_outlined,
  'language': Icons.translate_outlined,
  'history': Icons.history_edu_outlined,
  'public': Icons.public_outlined,
  'psychology': Icons.psychology_outlined,
  'palette': Icons.palette_outlined,
  'music': Icons.music_note_outlined,
  'sports': Icons.sports_soccer_outlined,
  'work': Icons.work_outline,
  'star': Icons.star_outline,
  'heart': Icons.favorite_outline,
  'home': Icons.home_outlined,
  'lightbulb': Icons.lightbulb_outline,
  'pen': Icons.edit_outlined,
  'gavel': Icons.gavel_outlined,
};

/// Muted, ink-like folder colors (readable on light and dark).
const folderColors = <int>[
  0xFF8A8F98, 0xFF4A6FA5, 0xFF3F8FA6, 0xFF4E8B5F, 0xFF8A9A4B, 0xFFC49A2C,
  0xFFD9772B, 0xFFC0504D, 0xFFB65A7B, 0xFF7E5BA6, 0xFF8B6B52, 0xFF4F5560,
];

IconData folderIcon(String key) => folderIcons[key] ?? Icons.folder_outlined;
