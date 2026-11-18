import 'package:caret_notes/core/code_stats.dart';
import 'package:caret_notes/core/code_stats.g.dart';
import 'package:caret_notes/ui/code_stats_view.dart';
import 'package:caret_notes/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the AI section lists lines per area with totals', (tester) async {
    const s = CodeStats(
      commit: 'abc1234',
      date: '2026-11-18',
      commits: 10,
      aiCommits: 4,
      areas: [CodeArea('App code', 12000, 3000), CodeArea('Tests', 2000, 1000)],
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Color(0xFFD9772B), Brightness.light),
      home: const Scaffold(body: CodeStatsView(stats: s)),
    ));
    expect(find.text('4,000 of 14,000 lines written with AI (29 %)'), findsOneWidget);
    expect(find.text('App code'), findsOneWidget);
    expect(find.text('3,000 of 12,000 lines'), findsOneWidget);
    expect(find.text('50 %'), findsOneWidget);
    expect(find.textContaining('4 of 10 commits'), findsOneWidget);
  });

  test('the generated stats are filled in', () {
    expect(codeStats.lines, greaterThan(0));
    expect(codeStats.aiLines, inInclusiveRange(0, codeStats.lines));
  });
}
