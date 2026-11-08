import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'remote_store.dart';
import 'secret_store.dart';

const driveScopes = [drive.DriveApi.driveFileScope];
const _folderMime = 'application/vnd.google-apps.folder';

/// Google Drive, limited to files this app created (drive.file scope).
/// The library lives in a "CaretNotes" folder in the user's Drive.
class GDriveRemote implements RemoteStore {
  final drive.DriveApi api;
  final String rootName;
  GDriveRemote(this.api, {this.rootName = 'CaretNotes'});

  @override
  String get displayName => 'Google Drive';

  String? _rootId;
  final Map<String, String> _dirIds = {}; // rel dir -> id
  final Map<String, String> _fileIds = {}; // rel path -> id

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on SocketException catch (e) {
      throw RemoteException('Google Drive not reachable: ${e.message}', offline: true);
    } on drive.DetailedApiRequestError catch (e) {
      throw RemoteException('Google Drive error ${e.status}: ${e.message}');
    } on AccessDeniedException {
      throw RemoteException('Google sign-in expired. Sign in again in Settings → Sync.');
    }
  }

  Future<String> _root() async {
    if (_rootId != null) return _rootId!;
    final q = "name = '$rootName' and mimeType = '$_folderMime' and 'root' in parents and trashed = false";
    final r = await api.files.list(q: q, $fields: 'files(id)', spaces: 'drive');
    if (r.files != null && r.files!.isNotEmpty) return _rootId = r.files!.first.id!;
    final f = await api.files.create(drive.File(name: rootName, mimeType: _folderMime, parents: ['root']));
    return _rootId = f.id!;
  }

  @override
  Future<List<RemoteEntry>> listAll() => _guard(() async {
        final root = await _root();
        final all = <drive.File>[];
        String? token;
        do {
          final r = await api.files.list(
            q: 'trashed = false',
            spaces: 'drive',
            pageSize: 1000,
            pageToken: token,
            $fields: 'nextPageToken, files(id, name, mimeType, parents, md5Checksum, modifiedTime, size)',
          );
          all.addAll(r.files ?? const []);
          token = r.nextPageToken;
        } while (token != null);

        final byId = {for (final f in all) f.id!: f};
        final pathCache = <String, String?>{root: ''};
        String? pathOf(String id) {
          if (pathCache.containsKey(id)) return pathCache[id];
          final f = byId[id];
          if (f == null || f.parents == null || f.parents!.isEmpty) return pathCache[id] = null;
          final parent = pathOf(f.parents!.first);
          if (parent == null) return pathCache[id] = null;
          return pathCache[id] = parent.isEmpty ? f.name! : '$parent/${f.name}';
        }

        _dirIds
          ..clear()
          ..[''] = root;
        _fileIds.clear();
        final out = <RemoteEntry>[];
        for (final f in all) {
          final path = pathOf(f.id!);
          if (path == null || path.isEmpty) continue;
          if (f.mimeType == _folderMime) {
            _dirIds[path] = f.id!;
          } else {
            _fileIds[path] = f.id!;
            out.add(RemoteEntry(path, f.md5Checksum ?? f.modifiedTime?.toIso8601String() ?? f.id!, int.tryParse(f.size ?? '') ?? 0));
          }
        }
        return out;
      });

  Future<String?> _idFor(String path) async {
    if (_fileIds.isEmpty) await listAll();
    return _fileIds[path];
  }

  Future<String> _dir(String rel) async {
    if (_dirIds.containsKey(rel)) return _dirIds[rel]!;
    final parentRel = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
    final parent = rel.isEmpty ? await _root() : await _dir(parentRel);
    final name = rel.split('/').last;
    final q = "name = '${name.replaceAll("'", r"\'")}' and mimeType = '$_folderMime' and '$parent' in parents and trashed = false";
    final r = await api.files.list(q: q, $fields: 'files(id)', spaces: 'drive');
    final id = (r.files != null && r.files!.isNotEmpty)
        ? r.files!.first.id!
        : (await api.files.create(drive.File(name: name, mimeType: _folderMime, parents: [parent]))).id!;
    return _dirIds[rel] = id;
  }

  @override
  Future<Uint8List> read(String path) => _guard(() async {
        final id = await _idFor(path);
        if (id == null) throw RemoteException('Not found on Google Drive: $path');
        final media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
        final b = BytesBuilder(copy: false);
        await for (final chunk in media.stream) {
          b.add(chunk);
        }
        return b.takeBytes();
      });

  @override
  Future<String> write(String path, Uint8List data) => _guard(() async {
        final media = drive.Media(Stream.value(data), data.length, contentType: 'application/octet-stream');
        final existing = await _idFor(path);
        drive.File f;
        if (existing != null) {
          f = await api.files.update(drive.File(), existing, uploadMedia: media, $fields: 'id, md5Checksum, modifiedTime');
        } else {
          final dirRel = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
          final parent = await _dir(dirRel);
          f = await api.files.create(drive.File(name: path.split('/').last, parents: [parent]),
              uploadMedia: media, $fields: 'id, md5Checksum, modifiedTime');
          _fileIds[path] = f.id!;
        }
        return f.md5Checksum ?? f.modifiedTime?.toIso8601String() ?? f.id!;
      });

  /// Moves to the Drive trash (recoverable there for 30 days).
  @override
  Future<void> delete(String path) => _guard(() async {
        final id = await _idFor(path);
        if (id == null) return;
        await api.files.update(drive.File(trashed: true), id);
        _fileIds.remove(path);
      });
}

/// Google sign-in for desktop: opens the browser, listens on a loopback port.
class GoogleAuth {
  final SecretStore secrets;
  GoogleAuth(this.secrets);
  static const _key = 'gdrive-credentials';

  Future<bool> get signedIn async => await secrets.read(_key) != null;

  Future<void> signIn(String clientId, String clientSecret, void Function(String url) openBrowser) async {
    final client = http.Client();
    try {
      final creds = await obtainAccessCredentialsViaUserConsent(
        ClientId(clientId, clientSecret.isEmpty ? null : clientSecret),
        driveScopes,
        client,
        openBrowser,
      );
      await secrets.write(_key, jsonEncode(creds.toJson()));
    } finally {
      client.close();
    }
  }

  Future<void> signOut() => secrets.delete(_key);

  /// Authorized client that refreshes tokens and stores refreshed credentials.
  Future<AutoRefreshingAuthClient?> client(String clientId, String clientSecret) async {
    final raw = await secrets.read(_key);
    if (raw == null) return null;
    final creds = AccessCredentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final c = autoRefreshingClient(ClientId(clientId, clientSecret.isEmpty ? null : clientSecret), creds, http.Client());
    c.credentialUpdates.listen((u) => secrets.write(_key, jsonEncode(u.toJson())));
    return c;
  }
}
