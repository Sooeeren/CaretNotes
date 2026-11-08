import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model/note.dart';

/// A `.cnote` file is a zip with:
///   note.json        structured note data
///   assets/<id>      embedded images / PDFs
///   thumb.png        first-page thumbnail (optional)
const noteExtension = '.cnote';

class NoteFormatException implements Exception {
  final String message;
  NoteFormatException(this.message);
  @override
  String toString() => 'NoteFormatException: $message';
}

Uint8List encodeNote(Note note, {Uint8List? thumb}) {
  final a = Archive();
  final json = utf8.encode(jsonEncode(note.toJson()));
  a.addFile(ArchiveFile('note.json', json.length, json));
  note.assets.forEach((id, bytes) {
    // already-compressed media: store
    a.addFile(ArchiveFile.noCompress('assets/$id', bytes.length, bytes));
  });
  if (thumb != null) a.addFile(ArchiveFile.noCompress('thumb.png', thumb.length, thumb));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

Archive _open(Uint8List bytes) {
  try {
    return ZipDecoder().decodeBytes(bytes, verify: true);
  } catch (e) {
    throw NoteFormatException('not a valid note archive: $e');
  }
}

Note decodeNote(Uint8List bytes) {
  final a = _open(bytes);
  final nj = a.findFile('note.json');
  if (nj == null) throw NoteFormatException('note.json missing');
  try {
    final map = jsonDecode(utf8.decode(nj.content)) as Map<String, dynamic>;
    if ((map['format'] as int? ?? 0) > Note.formatVersion) {
      throw NoteFormatException('note was written by a newer CaretNotes version');
    }
    final assets = <String, Uint8List>{};
    for (final f in a.files) {
      if (f.isFile && f.name.startsWith('assets/')) {
        assets[f.name.substring(7)] = Uint8List.fromList(f.content);
      }
    }
    return Note.fromJson(map, assets: assets);
  } on NoteFormatException {
    rethrow;
  } catch (e) {
    throw NoteFormatException('corrupt note.json: $e');
  }
}

/// Cheap validity check used by sync to skip half-written files.
bool isValidNoteFile(Uint8List bytes) {
  try {
    final a = _open(bytes);
    return a.findFile('note.json') != null;
  } catch (_) {
    return false;
  }
}

Uint8List? readThumb(Uint8List bytes) {
  try {
    final f = _open(bytes).findFile('thumb.png');
    return f == null ? null : Uint8List.fromList(f.content);
  } catch (_) {
    return null;
  }
}

/// Reads only note.json metadata (title, modified, favorite, id) without assets.
Map<String, dynamic>? readNoteMeta(Uint8List bytes) {
  try {
    final f = _open(bytes).findFile('note.json');
    if (f == null) return null;
    return jsonDecode(utf8.decode(f.content)) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
