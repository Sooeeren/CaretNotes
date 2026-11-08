import 'package:path/path.dart' as p;

/// Sync clients create their own copies when two devices change a file:
///   Proton Drive: `Note (# Name clash 2026-11-08 ab12cd #).cnote`
///   Dropbox:      `Note (Laptop's conflicted copy 2026-11-08).cnote`
///   Google/other: `Note (conflict 1).cnote`, `Note (1).cnote` is NOT treated as a conflict.
///   OneDrive:     `Note-LAPTOP.cnote` (only when the inner note id matches, see [maybeHostSuffixCopy]).
final _patterns = [
  RegExp(r' ?\(# ?Name clash[^)]*#\)', caseSensitive: false),
  RegExp(r' ?\([^()]*conflicted copy[^()]*\)', caseSensitive: false),
  RegExp(r' ?\([^()]*conflict[^()]*\)', caseSensitive: false),
];

/// Original path a conflict copy belongs to, or null if [path] isn't a known conflict copy.
String? conflictOriginal(String path) {
  final dir = p.posix.dirname(path);
  final name = p.posix.basename(path);
  final ext = p.posix.extension(name);
  final base = name.substring(0, name.length - ext.length);
  for (final re in _patterns) {
    if (re.hasMatch(base)) {
      final clean = base.replaceFirst(re, '').trimRight();
      if (clean.isEmpty) return null;
      return dir == '.' ? '$clean$ext' : '$dir/$clean$ext';
    }
  }
  return null;
}

final _hostSuffix = RegExp(r'-[A-Za-z0-9][A-Za-z0-9-]{2,}$');

/// OneDrive-style `Name-HOSTNAME.ext`; caller must confirm via the note id.
String? maybeHostSuffixCopy(String path) {
  final dir = p.posix.dirname(path);
  final name = p.posix.basename(path);
  final ext = p.posix.extension(name);
  final base = name.substring(0, name.length - ext.length);
  final m = _hostSuffix.firstMatch(base);
  if (m == null || m.start == 0) return null;
  final clean = base.substring(0, m.start);
  return dir == '.' ? '$clean$ext' : '$dir/$clean$ext';
}
