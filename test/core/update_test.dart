import 'dart:convert';
import 'dart:io';

import 'package:caret_notes/core/update/install_kind.dart';
import 'package:caret_notes/core/update/update_check.dart';
import 'package:caret_notes/core/version.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> release(String tag, List<String> assets, {String body = 'Notes'}) => {
      'tag_name': tag,
      'html_url': 'https://github.com/Sooeeren/CaretNotes/releases/tag/$tag',
      'body': body,
      'draft': false,
      'prerelease': false,
      'assets': [
        for (final a in assets)
          {
            'name': a,
            'browser_download_url': 'https://github.com/Sooeeren/CaretNotes/releases/download/$tag/$a',
            'size': 1000,
            'digest': 'sha256:${sha256.convert(utf8.encode(a))}',
          },
      ],
    };

const allAssets = [
  'CaretNotes-Setup-1.4.0.exe',
  'CaretNotes-1.4.0-portable.exe',
  'CaretNotes-1.4.0-x86_64.AppImage',
  'caretnotes_1.4.0_amd64.deb',
  'caretnotes-1.4.0-1.x86_64.rpm',
  'caretnotes-1.4.0-1-x86_64.pkg.tar.zst',
  'CaretNotes-1.4.0.apk',
];

void main() {
  test('the version in the code matches pubspec.yaml', () {
    final m = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(appVersion, m!.group(1));
  });

  test('versions compare numerically and ignore a leading v', () {
    expect(AppVersion.parse('v1.10.0') > AppVersion.parse('1.9.3'), isTrue);
    expect(AppVersion.parse('1.2.0') == AppVersion.parse('v1.2'), isTrue);
    expect(AppVersion.parse('1.2.0+3').toString(), '1.2.0');
    expect(AppVersion.tryParse('nightly'), isNull);
  });

  test('a release lists its version, notes and downloads', () {
    final r = ReleaseInfo.fromJson(release('v1.4.0', allAssets, body: 'What is new'));
    expect(r.version.toString(), '1.4.0');
    expect(r.notes, 'What is new');
    expect(r.assets, hasLength(7));
    expect(r.assets.first.sha256, sha256.convert(utf8.encode('CaretNotes-Setup-1.4.0.exe')).toString());
  });

  test('each kind of install gets its own download', () {
    final r = ReleaseInfo.fromJson(release('v1.4.0', allAssets));
    expect(r.assetFor(InstallKind.windowsInstaller)?.name, 'CaretNotes-Setup-1.4.0.exe');
    expect(r.assetFor(InstallKind.windowsPortable)?.name, 'CaretNotes-1.4.0-portable.exe');
    expect(r.assetFor(InstallKind.appImage)?.name, 'CaretNotes-1.4.0-x86_64.AppImage');
    expect(r.assetFor(InstallKind.deb)?.name, 'caretnotes_1.4.0_amd64.deb');
    expect(r.assetFor(InstallKind.rpm)?.name, 'caretnotes-1.4.0-1.x86_64.rpm');
    expect(r.assetFor(InstallKind.arch)?.name, 'caretnotes-1.4.0-1-x86_64.pkg.tar.zst');
    expect(r.assetFor(InstallKind.android)?.name, 'CaretNotes-1.4.0.apk');
    expect(r.assetFor(InstallKind.other), isNull);
    expect(ReleaseInfo.fromJson(release('v1.4.0', ['CaretNotes-1.4.0.apk'])).assetFor(InstallKind.deb), isNull);
  });

  test('only installer and AppImage copies replace themselves', () {
    expect(InstallKind.windowsInstaller.selfUpdates, isTrue);
    expect(InstallKind.appImage.selfUpdates, isTrue);
    for (final k in [InstallKind.windowsPortable, InstallKind.deb, InstallKind.rpm, InstallKind.arch, InstallKind.android, InstallKind.other]) {
      expect(k.selfUpdates, isFalse, reason: k.name);
    }
  });

  group('UpdateChecker', () {
    UpdateChecker checker(http.Response Function(http.Request) reply) =>
        UpdateChecker(client: MockClient((r) async => reply(r)), current: AppVersion.parse('1.3.0'));

    test('asks GitHub for the latest release of this repo', () async {
      Uri? asked;
      await checker((r) {
        asked = r.url;
        return http.Response(jsonEncode(release('v1.3.0', allAssets)), 200);
      }).check();
      expect(asked.toString(), 'https://api.github.com/repos/Sooeeren/CaretNotes/releases/latest');
    });

    test('reports a newer release', () async {
      final r = await checker((_) => http.Response(jsonEncode(release('v1.4.0', allAssets)), 200)).check();
      expect(r?.version.toString(), '1.4.0');
    });

    test('nothing when this version is the latest or newer', () async {
      expect(await checker((_) => http.Response(jsonEncode(release('v1.3.0', allAssets)), 200)).check(), isNull);
      expect(await checker((_) => http.Response(jsonEncode(release('v1.2.9', allAssets)), 200)).check(), isNull);
    });

    test('no releases yet is not an error', () async {
      expect(await checker((_) => http.Response('{"message":"Not Found"}', 404)).check(), isNull);
    });

    test('a server error is reported', () async {
      expect(checker((_) => http.Response('rate limited', 403)).check(), throwsA(isA<UpdateException>()));
    });
  });

  test('a download only passes when its SHA-256 matches', () {
    final bytes = utf8.encode('installer');
    final good = ReleaseAsset(name: 'x', url: 'u', size: bytes.length, sha256: sha256.convert(bytes).toString());
    expect(good.matches(bytes), isTrue);
    expect(good.matches(utf8.encode('tampered')), isFalse);
    // GitHub lists no digest for some old assets: then only the size is checked
    expect(ReleaseAsset(name: 'x', url: 'u', size: bytes.length).matches(bytes), isTrue);
    expect(ReleaseAsset(name: 'x', url: 'u', size: 3).matches(bytes), isFalse);
  });

  test('the install kind comes from the marker file, the AppImage variable or the OS', () {
    final dir = Directory.systemTemp.createTempSync('cn_kind_');
    final exe = '${dir.path}/caret_notes';
    InstallKind kind(String os, {String? marker, Map<String, String> env = const {}}) {
      final f = File('${dir.path}/install_kind');
      if (marker == null) {
        if (f.existsSync()) f.deleteSync();
      } else {
        f.writeAsStringSync('$marker\n');
      }
      return detectInstallKind(executable: exe, environment: env, os: os);
    }

    expect(kind('windows', marker: 'inno'), InstallKind.windowsInstaller);
    expect(kind('windows'), InstallKind.windowsPortable);
    expect(kind('linux', marker: 'deb'), InstallKind.deb);
    expect(kind('linux', marker: 'rpm'), InstallKind.rpm);
    expect(kind('linux', marker: 'arch'), InstallKind.arch);
    expect(kind('linux', marker: 'deb', env: {'APPIMAGE': '/home/me/CaretNotes.AppImage'}), InstallKind.appImage);
    expect(kind('linux'), InstallKind.other);
    expect(kind('android'), InstallKind.android);
    dir.deleteSync(recursive: true);
  });
}
