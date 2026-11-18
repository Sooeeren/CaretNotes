/// How much of CaretNotes' source was written with AI help, counted from git history.
///
/// A commit counts as AI-made when it carries a `Co-Authored-By:` trailer naming an AI
/// assistant (Claude adds `Co-Authored-By: Claude … <noreply@anthropic.com>`), or when it
/// is one of the early commits that were all made with Claude (`allAiThrough` in the tool). Lines are
/// attributed with `git blame`, so a line counts for the commit that last changed it.
/// `tool/code_stats.dart` fills in `code_stats.g.dart`; run it before a release.
library;

class CodeArea {
  final String name;
  final int lines;
  final int aiLines;
  const CodeArea(this.name, this.lines, this.aiLines);

  double get aiShare => lines == 0 ? 0 : aiLines / lines;
}

class CodeStats {
  /// Short hash of the commit the numbers were taken from.
  final String commit;
  final String date;
  final int commits;
  final int aiCommits;
  final List<CodeArea> areas;
  const CodeStats({required this.commit, required this.date, required this.commits, required this.aiCommits, required this.areas});

  int get lines => areas.fold(0, (a, e) => a + e.lines);
  int get aiLines => areas.fold(0, (a, e) => a + e.aiLines);
  double get aiShare => lines == 0 ? 0 : aiLines / lines;
}

final _aiTrailer = RegExp(r'claude|anthropic|copilot|codex|openai|chatgpt|gemini|cursor', caseSensitive: false);

/// Whether a commit's `Co-Authored-By` trailer values name an AI assistant.
bool isAiCoAuthor(String trailers) => _aiTrailer.hasMatch(trailers);

/// Non-blank lines per commit hash, from `git blame -l -s` output
/// (`<hash> <line>) <text>`, boundary commits prefixed with `^`).
Map<String, int> blameLinesByCommit(String blame) {
  final out = <String, int>{};
  for (final line in blame.split('\n')) {
    final close = line.indexOf(') ');
    final sp = line.indexOf(' ');
    if (sp <= 0) continue;
    var sha = line.substring(0, sp);
    if (sha.startsWith('^')) sha = sha.substring(1);
    if (!RegExp(r'^[0-9a-f]{7,40}$').hasMatch(sha)) continue;
    final text = close < 0 ? '' : line.substring(close + 2);
    if (text.trim().isEmpty) continue;
    out[sha] = (out[sha] ?? 0) + 1;
  }
  return out;
}

/// Which area a tracked file belongs to, or null when it isn't hand-written source
/// (generated files, assets, docs).
String? codeAreaOf(String path) {
  final p = path.replaceAll('\\', '/');
  final name = p.split('/').last;
  if (name.endsWith('.g.dart') || name.contains('generated_plugin') || p.contains('/flutter/ephemeral/')) return null;
  if (p.startsWith('windows/flutter/') || p.startsWith('linux/flutter/')) return null;
  const exts = ['.dart', '.cpp', '.cc', '.h', '.kt', '.kts', '.ps1', '.sh', '.yml', '.yaml', '.iss', '.cmake', '.rc'];
  if (!(name == 'CMakeLists.txt' || exts.any(name.endsWith))) return null;
  if (name == 'pubspec.lock' || name == 'analysis_options.yaml') return null;
  if (p.startsWith('lib/')) return 'App code';
  if (p.startsWith('test/')) return 'Tests';
  return 'Tools, build and platform code';
}
