import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Where releases come from. Only this one request is made for a check; nothing is sent.
const releasesRepo = 'Sooeeren/CaretNotes';
const releasesPage = 'https://github.com/$releasesRepo/releases';

/// Every release also carries this file (the API's release JSON, written by the release
/// workflow). Downloads aren't rate-limited like the API (60 requests an hour per network),
/// so it's the fallback when the API answers 403/429.
const releaseManifest = '$releasesPage/latest/download/release.json';

class AppVersion implements Comparable<AppVersion> {
  final List<int> parts;
  const AppVersion(this.parts);

  /// `v1.2.0`, `1.2`, `1.2.0+3` (the build number is ignored).
  static AppVersion? tryParse(String s) {
    final m = RegExp(r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(s.trim());
    if (m == null) return null;
    return AppVersion([for (var i = 1; i <= 3; i++) int.parse(m.group(i) ?? '0')]);
  }

  static AppVersion parse(String s) => tryParse(s) ?? (throw FormatException('Not a version: $s'));

  @override
  int compareTo(AppVersion o) {
    for (var i = 0; i < 3; i++) {
      final d = parts[i].compareTo(o.parts[i]);
      if (d != 0) return d;
    }
    return 0;
  }

  bool operator >(AppVersion o) => compareTo(o) > 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hashAll(parts);

  @override
  String toString() => parts.join('.');
}

/// How this copy was installed; decides which download fits and whether the app can
/// replace itself.
enum InstallKind {
  windowsInstaller,
  windowsPortable,
  appImage,
  deb,
  rpm,
  arch,
  android,
  other;

  /// The installer (run silently) and the AppImage (a single file we may overwrite) update
  /// themselves; the others get the right download to open or install.
  bool get selfUpdates => this == windowsInstaller || this == appImage;
}

class ReleaseAsset {
  final String name, url;
  final int size;

  /// Hex SHA-256 from GitHub's asset `digest`, when listed.
  final String? sha256;
  const ReleaseAsset({required this.name, required this.url, required this.size, this.sha256});

  /// Whether downloaded [bytes] are this file (size, and the SHA-256 when known).
  bool matches(List<int> bytes) {
    if (bytes.length != size) return false;
    final want = sha256;
    return want == null || want == sha256Of(bytes);
  }
}

String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

class ReleaseInfo {
  final AppVersion version;
  final String tag, notes, pageUrl;
  final List<ReleaseAsset> assets;
  const ReleaseInfo({required this.version, required this.tag, required this.notes, required this.pageUrl, required this.assets});

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) {
    final tag = j['tag_name'] as String;
    return ReleaseInfo(
      version: AppVersion.parse(tag),
      tag: tag,
      notes: (j['body'] as String?)?.trim() ?? '',
      pageUrl: j['html_url'] as String? ?? '$releasesPage/tag/$tag',
      assets: [
        for (final a in (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>())
          ReleaseAsset(
            name: a['name'] as String,
            url: a['browser_download_url'] as String,
            size: (a['size'] as num?)?.toInt() ?? 0,
            sha256: switch (a['digest']) {
              final String d when d.startsWith('sha256:') => d.substring(7).toLowerCase(),
              _ => null,
            },
          ),
      ],
    );
  }

  /// The download for [kind], by the file names the release workflow uses.
  ReleaseAsset? assetFor(InstallKind kind) {
    final pattern = switch (kind) {
      InstallKind.windowsInstaller => RegExp(r'^CaretNotes-Setup-[\d.]+\.exe$'),
      InstallKind.windowsPortable => RegExp(r'^CaretNotes-[\d.]+-portable\.exe$'),
      InstallKind.appImage => RegExp(r'^CaretNotes-[\d.]+-x86_64\.AppImage$'),
      InstallKind.deb => RegExp(r'^caretnotes_[\d.]+_amd64\.deb$'),
      InstallKind.rpm => RegExp(r'^caretnotes-[\d.]+-\d+\.x86_64\.rpm$'),
      InstallKind.arch => RegExp(r'^caretnotes-[\d.]+-\d+-x86_64\.pkg\.tar\.zst$'),
      InstallKind.android => RegExp(r'^CaretNotes-[\d.]+\.apk$'),
      InstallKind.other => null,
    };
    if (pattern == null) return null;
    for (final a in assets) {
      if (pattern.hasMatch(a.name)) return a;
    }
    return null;
  }
}

class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => message;
}

/// Asks GitHub for the latest release and reports it when it is newer than [current].
class UpdateChecker {
  final http.Client client;
  final AppVersion current;
  UpdateChecker({required this.client, required this.current});

  Future<http.Response> _get(String url) async {
    try {
      return await client
          .get(Uri.parse(url), headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'CaretNotes/$current'})
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw UpdateException('Could not reach GitHub ($e)');
    }
  }

  Future<ReleaseInfo?> check() async {
    var r = await _get('https://api.github.com/repos/$releasesRepo/releases/latest');
    if (r.statusCode == 404) return null; // no release published yet
    if (r.statusCode == 403 || r.statusCode == 429) {
      // Rate limited (many people on one network, e.g. a university): ask the download instead.
      r = await _get(releaseManifest);
      if (r.statusCode != 200) {
        throw UpdateException('GitHub is limiting update checks from this network right now. Try again in an hour.');
      }
    }
    if (r.statusCode != 200) throw UpdateException('GitHub answered ${r.statusCode}');
    final ReleaseInfo info;
    try {
      info = ReleaseInfo.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    } catch (e) {
      throw UpdateException('Unexpected answer from GitHub ($e)');
    }
    return info.version > current ? info : null;
  }
}
