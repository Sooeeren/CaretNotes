import 'dart:io';

import 'package:path/path.dart' as p;

import 'update_check.dart';

/// How this copy of CaretNotes was installed. The Windows installer and the Linux
/// packages put a one-word `install_kind` file next to the executable ("inno", "deb",
/// "rpm", "arch"); an AppImage sets `$APPIMAGE`. Anything else on Windows is the
/// portable one-file exe.
InstallKind detectInstallKind({
  String? executable,
  Map<String, String>? environment,
  String? os,
}) {
  os ??= Platform.operatingSystem;
  final env = environment ?? Platform.environment;
  if (os == 'android') return InstallKind.android;
  if (os == 'linux' && (env['APPIMAGE'] ?? '').isNotEmpty) return InstallKind.appImage;
  String marker = '';
  try {
    final f = File(p.join(p.dirname(executable ?? Platform.resolvedExecutable), 'install_kind'));
    if (f.existsSync()) marker = f.readAsStringSync().trim().toLowerCase();
  } catch (_) {}
  return switch ((os, marker)) {
    ('windows', 'inno') => InstallKind.windowsInstaller,
    ('windows', _) => InstallKind.windowsPortable,
    ('linux', 'deb') => InstallKind.deb,
    ('linux', 'rpm') => InstallKind.rpm,
    ('linux', 'arch') => InstallKind.arch,
    _ => InstallKind.other,
  };
}
