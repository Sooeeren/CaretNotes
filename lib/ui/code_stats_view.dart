import 'package:flutter/material.dart';

import '../core/code_stats.dart';
import 'theme.dart';

String _n(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
String _pct(double f) => '${(f * 100).round()} %';

/// The "Made with AI" lines in Settings: how many lines of the source came from
/// commits co-written by an AI, overall and per area.
class CodeStatsView extends StatelessWidget {
  final CodeStats stats;
  const CodeStatsView({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = AppTokens.of(context).muted;
    Widget bar(double v) => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: t.colorScheme.surfaceContainerHighest),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_n(stats.aiLines)} of ${_n(stats.lines)} lines written with AI (${_pct(stats.aiShare)})', style: t.textTheme.bodyLarge),
        const SizedBox(height: 8),
        bar(stats.aiShare),
        const SizedBox(height: 12),
        for (final a in stats.areas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(a.name)),
              Text('${_n(a.aiLines)} of ${_n(a.lines)} lines', style: t.textTheme.bodyMedium),
              SizedBox(width: 52, child: Text(_pct(a.aiShare), textAlign: TextAlign.right, style: t.textTheme.bodyMedium?.copyWith(color: muted))),
            ]),
          ),
        const SizedBox(height: 8),
        Text(
          'Counted with git blame: a line counts for the commit that last changed it, and a commit counts as AI-made '
          'when it was co-written by an AI (${stats.aiCommits} of ${stats.commits} commits). '
          'Blank lines, generated files and docs are left out. As of commit ${stats.commit} (${stats.date}).',
          style: t.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ]),
    );
  }
}
