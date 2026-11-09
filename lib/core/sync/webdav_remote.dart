import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'remote_store.dart';

/// WebDAV (Nextcloud, ownCloud, many NAS boxes). Library lives under [baseUrl].
class WebDavRemote implements RemoteStore {
  final Uri baseUrl;
  final String user;
  final String password;
  final http.Client _http;

  WebDavRemote(String url, this.user, this.password, {http.Client? client})
      : baseUrl = Uri.parse(url.endsWith('/') ? url : '$url/'),
        _http = client ?? http.Client();

  @override
  String get displayName => 'WebDAV';

  Map<String, String> get _auth => {
        if (user.isNotEmpty) 'Authorization': 'Basic ${base64.encode(utf8.encode('$user:$password'))}',
      };

  Uri _url(String rel) => baseUrl.resolve(rel.split('/').map(Uri.encodeComponent).join('/'));

  Future<http.StreamedResponse> _send(String method, Uri url, {Map<String, String> headers = const {}, List<int>? body}) async {
    final req = http.Request(method, url)..headers.addAll({..._auth, ...headers});
    if (body != null) req.bodyBytes = body;
    try {
      return await _http.send(req).timeout(const Duration(seconds: 60));
    } on SocketException catch (e) {
      throw RemoteException('Server not reachable: ${e.message}', offline: true);
    } on HttpException catch (e) {
      throw RemoteException('Connection failed: ${e.message}', offline: true);
    }
  }

  void _check(http.StreamedResponse r, String what) {
    if (r.statusCode == 401 || r.statusCode == 403) throw RemoteException('WebDAV login was rejected ($what).');
    if (r.statusCode >= 400) throw RemoteException('WebDAV error ${r.statusCode} ($what).');
  }

  static const _propfind = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getetag/><d:getlastmodified/><d:getcontentlength/></d:prop></d:propfind>';

  @override
  Future<List<RemoteEntry>> listAll() async {
    final out = <RemoteEntry>[];
    await _ensureDir('');
    Future<void> walk(String rel) async {
      final r = await _send('PROPFIND', _url(rel), headers: {'Depth': '1', 'Content-Type': 'application/xml'}, body: utf8.encode(_propfind));
      if (r.statusCode == 404) return;
      _check(r, 'list');
      final doc = XmlDocument.parse(await r.stream.bytesToString());
      final basePath = Uri.decodeComponent(baseUrl.path);
      for (final resp in doc.findAllElements('response', namespaceUri: 'DAV:')) {
        final href = Uri.decodeComponent(Uri.parse(resp.findElements('href', namespaceUri: 'DAV:').first.innerText).path);
        if (!href.startsWith(basePath)) continue;
        var child = href.substring(basePath.length);
        if (child.endsWith('/')) child = child.substring(0, child.length - 1);
        if (child == rel || child.isEmpty) continue;
        final name = child.split('/').last;
        if (name.startsWith('.') && name != '.folder.json') continue;
        final prop = resp.findAllElements('prop', namespaceUri: 'DAV:').first;
        final isDir = prop.findAllElements('collection', namespaceUri: 'DAV:').isNotEmpty;
        if (isDir) {
          await walk(child);
        } else {
          final etag = prop.findAllElements('getetag', namespaceUri: 'DAV:').firstOrNull?.innerText ?? '';
          final lm = prop.findAllElements('getlastmodified', namespaceUri: 'DAV:').firstOrNull?.innerText ?? '';
          final len = int.tryParse(prop.findAllElements('getcontentlength', namespaceUri: 'DAV:').firstOrNull?.innerText ?? '') ?? 0;
          out.add(RemoteEntry(child, etag.isNotEmpty ? etag : '$lm:$len', len));
        }
      }
    }

    await walk('');
    return out;
  }

  @override
  Future<Uint8List> read(String path) async {
    final r = await _send('GET', _url(path));
    _check(r, 'read $path');
    return Uint8List.fromList(await r.stream.toBytes());
  }

  final Set<String> _knownDirs = {};

  Future<void> _ensureDir(String rel) async {
    if (_knownDirs.contains(rel)) return;
    final parts = rel.isEmpty ? <String>[] : rel.split('/');
    for (var i = 0; i <= parts.length; i++) {
      final d = parts.take(i).join('/');
      if (_knownDirs.contains(d)) continue;
      final r = await _send('MKCOL', _url(d.isEmpty ? '' : '$d/'));
      await r.stream.drain<void>();
      if (r.statusCode >= 400 && r.statusCode != 405 && r.statusCode != 301) _check(r, 'create folder $d');
      _knownDirs.add(d);
    }
  }

  @override
  Future<String> write(String path, Uint8List data) async {
    final dir = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
    await _ensureDir(dir);
    final r = await _send('PUT', _url(path), headers: {'Content-Type': 'application/octet-stream'}, body: data);
    _check(r, 'write $path');
    await r.stream.drain<void>();
    final etag = r.headers['etag'];
    if (etag != null && etag.isNotEmpty) return etag;
    final all = await listAll();
    return all.firstWhere((e) => e.path == path, orElse: () => RemoteEntry(path, DateTime.now().toIso8601String(), data.length)).token;
  }

  @override
  Future<void> delete(String path) async {
    final r = await _send('DELETE', _url(path));
    await r.stream.drain<void>();
    if (r.statusCode != 404) _check(r, 'delete $path');
  }
}
