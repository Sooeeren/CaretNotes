import 'dart:convert';
import 'dart:io';

import 'package:caret_notes/core/sync/conflict_copies.dart';
import 'package:caret_notes/core/sync/secret_store.dart';
import 'package:caret_notes/core/sync/webdav_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('secret store round-trips and does not store plain text on Windows', () async {
    final dir = await Directory.systemTemp.createTemp('cn_sec_');
    final s = SecretStore(dir.path);
    await s.write('token', 'refresh-abc-123');
    expect(await s.read('token'), 'refresh-abc-123');
    final raw = await File('${dir.path}/token.secret').readAsBytes();
    if (Platform.isWindows) expect(utf8.decode(raw, allowMalformed: true).contains('refresh-abc-123'), isFalse);
    await s.delete('token');
    expect(await s.read('token'), isNull);
    await dir.delete(recursive: true);
  });

  test('conflict copy names map back to the original', () {
    expect(conflictOriginal('A/VL 1 (# Name clash 2026-11-08 x1y2z3 #).cnote'), 'A/VL 1.cnote');
    expect(conflictOriginal("VL 1 (Laptop's conflicted copy 2026-11-08).cnote"), 'VL 1.cnote');
    expect(conflictOriginal('VL 1 (conflict 2).cnote'), 'VL 1.cnote');
    expect(conflictOriginal('VL 1 (2).cnote'), isNull);
    expect(conflictOriginal('Plain.cnote'), isNull);
    expect(maybeHostSuffixCopy('Notes-DESKTOP-AB12.cnote'), 'Notes.cnote');
  });

  test('WebDAV lists files recursively from PROPFIND responses', () async {
    final client = MockClient((req) async {
      if (req.method == 'MKCOL') return http.Response('', 405);
      if (req.method != 'PROPFIND') return http.Response('', 404);
      final path = Uri.decodeComponent(req.url.path);
      if (path == '/dav/notes/') {
        return http.Response('''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
 <d:response><d:href>/dav/notes/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
 <d:response><d:href>/dav/notes/Physik/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
 <d:response><d:href>/dav/notes/VL%201.cnote</d:href><d:propstat><d:prop><d:resourcetype/><d:getetag>"e1"</d:getetag><d:getcontentlength>10</d:getcontentlength></d:prop></d:propstat></d:response>
</d:multistatus>''', 207);
      }
      if (path == '/dav/notes/Physik') {
        return http.Response('''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
 <d:response><d:href>/dav/notes/Physik/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
 <d:response><d:href>/dav/notes/Physik/.folder.json</d:href><d:propstat><d:prop><d:resourcetype/><d:getetag>"e2"</d:getetag></d:prop></d:propstat></d:response>
</d:multistatus>''', 207);
      }
      return http.Response('', 404);
    });
    final r = WebDavRemote('https://example.org/dav/notes', 'u', 'p', client: client);
    final entries = await r.listAll();
    expect(entries.map((e) => e.path), unorderedEquals(['VL 1.cnote', 'Physik/.folder.json']));
    expect(entries.firstWhere((e) => e.path == 'VL 1.cnote').token, '"e1"');
  });
}
