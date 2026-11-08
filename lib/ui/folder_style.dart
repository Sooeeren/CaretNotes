import 'package:flutter/material.dart';

/// Built-in folder icons, stored by key in `.folder.json`.
const folderIcons = <String, IconData>{
  'folder': Icons.folder_rounded,
  'school': Icons.school_rounded,
  'book': Icons.menu_book_rounded,
  'functions': Icons.functions_rounded,
  'calculate': Icons.calculate_rounded,
  'science': Icons.science_rounded,
  'biotech': Icons.biotech_rounded,
  'atom': Icons.blur_on_rounded,
  'code': Icons.code_rounded,
  'computer': Icons.computer_rounded,
  'language': Icons.translate_rounded,
  'history': Icons.history_edu_rounded,
  'public': Icons.public_rounded,
  'psychology': Icons.psychology_rounded,
  'palette': Icons.palette_rounded,
  'music': Icons.music_note_rounded,
  'sports': Icons.sports_soccer_rounded,
  'work': Icons.work_rounded,
  'star': Icons.star_rounded,
  'heart': Icons.favorite_rounded,
  'home': Icons.home_rounded,
  'lightbulb': Icons.lightbulb_rounded,
  'pen': Icons.edit_rounded,
  'gavel': Icons.gavel_rounded,
};

const folderColors = <int>[
  0xFF8A94A6, 0xFF3B6FE0, 0xFF2BA6C8, 0xFF1A8F3C, 0xFF7CB342, 0xFFF2B705,
  0xFFFF8A1F, 0xFFD23B3B, 0xFFE0457B, 0xFF9B3FD1, 0xFF6D4C41, 0xFF37474F,
];

IconData folderIcon(String key) => folderIcons[key] ?? Icons.folder_rounded;
