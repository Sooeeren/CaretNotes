import 'dart:typed_data';

import '../ids.dart';
import 'page.dart';

enum NoteLayout { paged, endless, canvas }

enum PaperSize {
  a4(595.28, 841.89),
  letter(612, 792);

  final double w, h;
  const PaperSize(this.w, this.h);
}

class Note {
  /// 2: Cornell and staff paper, text typed on the lines (`lh` on text).
  static const formatVersion = 2;

  final String id;
  final String title;
  final NoteLayout layout;
  final PaperSize paper;
  final bool landscape;
  final Template template;
  final List<NotePage> pages;
  final DateTime created;
  final DateTime modified;
  final String modifiedBy;
  final bool favorite;

  /// Binary assets (images, imported PDFs) by asset id. Not part of [toJson].
  final Map<String, Uint8List> assets;

  const Note({
    required this.id,
    required this.title,
    required this.layout,
    this.paper = PaperSize.a4,
    this.landscape = false,
    this.template = const Template(),
    required this.pages,
    required this.created,
    required this.modified,
    required this.modifiedBy,
    this.favorite = false,
    this.assets = const {},
  });

  double get pageWidth => landscape ? paper.h : paper.w;
  double get pageHeight => landscape ? paper.w : paper.h;

  factory Note.create({
    required String title,
    required NoteLayout layout,
    required String deviceName,
    PaperSize paper = PaperSize.a4,
    bool landscape = false,
    Template template = const Template(),
  }) {
    final now = DateTime.now().toUtc();
    final w = landscape ? paper.h : paper.w;
    final h = landscape ? paper.w : paper.h;
    return Note(
      id: newId(),
      title: title,
      layout: layout,
      paper: paper,
      landscape: landscape,
      template: template,
      pages: [NotePage.blank(w, h)],
      created: now,
      modified: now,
      modifiedBy: deviceName,
    );
  }

  Note copyWith({
    String? id,
    String? title,
    NoteLayout? layout,
    PaperSize? paper,
    bool? landscape,
    Template? template,
    List<NotePage>? pages,
    DateTime? modified,
    String? modifiedBy,
    bool? favorite,
    Map<String, Uint8List>? assets,
  }) =>
      Note(
        id: id ?? this.id,
        title: title ?? this.title,
        layout: layout ?? this.layout,
        paper: paper ?? this.paper,
        landscape: landscape ?? this.landscape,
        template: template ?? this.template,
        pages: pages ?? this.pages,
        created: created,
        modified: modified ?? this.modified,
        modifiedBy: modifiedBy ?? this.modifiedBy,
        favorite: favorite ?? this.favorite,
        assets: assets ?? this.assets,
      );

  /// All typed text, for search.
  String get plainText {
    final b = StringBuffer(title);
    for (final p in pages) {
      for (final e in p.elements) {
        if (e.toJson()['md'] case final String md) b.write('\n$md');
      }
    }
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'format': formatVersion,
        'id': id,
        'title': title,
        'layout': layout.name,
        'paper': paper.name,
        'landscape': landscape,
        'template': template.toJson(),
        'created': created.toIso8601String(),
        'modified': modified.toIso8601String(),
        'modifiedBy': modifiedBy,
        'favorite': favorite,
        'pages': [for (final p in pages) p.toJson()],
      };

  factory Note.fromJson(Map<String, dynamic> j, {Map<String, Uint8List> assets = const {}}) => Note(
        id: j['id'] as String,
        title: j['title'] as String,
        layout: NoteLayout.values.byName(j['layout'] as String),
        paper: PaperSize.values.byName(j['paper'] as String),
        landscape: j['landscape'] as bool,
        template: Template.fromJson(j['template'] as Map<String, dynamic>),
        created: DateTime.parse(j['created'] as String),
        modified: DateTime.parse(j['modified'] as String),
        modifiedBy: j['modifiedBy'] as String,
        favorite: j['favorite'] as bool? ?? false,
        pages: [for (final p in j['pages'] as List) NotePage.fromJson(p as Map<String, dynamic>)],
        assets: assets,
      );
}
