import 'package:caret_notes/core/code_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI co-authors are recognized from commit trailers', () {
    expect(isAiCoAuthor('Claude Opus 5.5 <noreply@anthropic.com>'), isTrue);
    expect(isAiCoAuthor('GitHub Copilot <copilot@github.com>'), isTrue);
    expect(isAiCoAuthor('Jane Doe <jane@example.com>'), isFalse);
    expect(isAiCoAuthor(''), isFalse);
  });

  test('blame output is counted per commit, skipping blank lines', () {
    const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const blame = '$a 1) import x;\n'
        '$a 2) \n'
        '^$b 3) void main() {}\n'
        '$b 4)   print(1);\n'
        '$a 5) // a ) b\n';
    expect(blameLinesByCommit(blame), {a: 2, b: 2});
  });

  test('only hand-written source is counted, by area', () {
    expect(codeAreaOf('lib/ui/app.dart'), 'App code');
    expect(codeAreaOf('test/core/sync_test.dart'), 'Tests');
    expect(codeAreaOf('windows/runner/main.cpp'), 'Tools, build and platform code');
    expect(codeAreaOf('windows/CMakeLists.txt'), 'Tools, build and platform code');
    expect(codeAreaOf('lib/core/code_stats.g.dart'), isNull);
    expect(codeAreaOf('windows/flutter/generated_plugins.cmake'), isNull);
    expect(codeAreaOf('docs/FEATURES.md'), isNull);
    expect(codeAreaOf('assets/icon.png'), isNull);
    expect(codeAreaOf('pubspec.lock'), isNull);
  });

  test('totals add up the areas', () {
    const s = CodeStats(commit: 'x', date: 'd', commits: 3, aiCommits: 2, areas: [CodeArea('A', 100, 80), CodeArea('B', 50, 10)]);
    expect(s.lines, 150);
    expect(s.aiLines, 90);
    expect(s.aiShare, closeTo(0.6, 1e-9));
  });
}
