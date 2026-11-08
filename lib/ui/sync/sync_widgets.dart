import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sync/sync_engine.dart';
import '../home/folder_grid.dart';
import 'sync_controller.dart';

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return formatDate(t.toUtc());
}

/// Sidebar footer: sync status, "Sync now", conflicts.
class SyncStatusTile extends StatelessWidget {
  const SyncStatusTile({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SyncController>();
    final t = Theme.of(context);
    final (icon, text, color) = switch (s.status) {
      SyncStatus.disabled => (Icons.cloud_off_rounded, 'Sync is off', t.colorScheme.onSurfaceVariant),
      SyncStatus.syncing => (Icons.cloud_sync_rounded, 'Syncing…', t.colorScheme.primary),
      SyncStatus.offline => (Icons.cloud_off_rounded, 'Offline — will retry', t.colorScheme.onSurfaceVariant),
      SyncStatus.error => (Icons.error_outline_rounded, s.lastError ?? 'Sync failed', t.colorScheme.error),
      SyncStatus.idle => (Icons.cloud_done_rounded, s.lastSync == null ? 'Ready to sync' : 'Synced ${_ago(s.lastSync!)}', t.colorScheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Column(children: [
        if (s.conflicts.isNotEmpty)
          Material(
            color: t.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showConflicts(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Icon(Icons.merge_type_rounded, color: t.colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${s.conflicts.length} note${s.conflicts.length == 1 ? '' : 's'} changed on two devices — choose',
                        style: TextStyle(color: t.colorScheme.onErrorContainer)),
                  ),
                ]),
              ),
            ),
          ),
        Row(children: [
          const SizedBox(width: 4),
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: s.lastError ?? text,
              child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall?.copyWith(color: color)),
            ),
          ),
          if (s.enabled)
            IconButton(
              tooltip: 'Sync now',
              icon: const Icon(Icons.sync_rounded),
              onPressed: s.status == SyncStatus.syncing ? null : () => s.syncNow(),
            ),
        ]),
      ]),
    );
  }
}

Future<void> showConflicts(BuildContext context) => showDialog(context: context, builder: (_) => const _ConflictDialog());

class _ConflictDialog extends StatelessWidget {
  const _ConflictDialog();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SyncController>();
    if (s.conflicts.isEmpty) {
      return AlertDialog(
        title: const Text('All sorted'),
        content: const Text('No notes are waiting for a decision.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      );
    }
    final c = s.conflicts.first;
    return AlertDialog(
      title: Text('"${c.path.split('/').last.replaceAll('.cnote', '')}" changed on two devices'),
      content: SizedBox(
        width: 640,
        child: FutureBuilder<(ConflictSide, ConflictSide)>(
          key: ValueKey('${c.path}|${c.remotePath}'),
          future: s.preview(c),
          builder: (ctx, snap) {
            if (snap.hasError) return Text('Could not load both versions: ${snap.error}');
            if (!snap.hasData) return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
            final (l, r) = snap.data!;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Pick what to keep. Nothing is lost: a version you don\'t keep goes to Recently deleted.',
                  style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _side(ctx, 'This device (${l.device})', l)),
                const SizedBox(width: 16),
                Expanded(child: _side(ctx, r.device, r)),
              ]),
              if (s.conflicts.length > 1) ...[
                const SizedBox(height: 8),
                Text('${s.conflicts.length - 1} more after this one', style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ]);
          },
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
        OutlinedButton(onPressed: () => s.resolve(c, Resolution.keepBoth), child: const Text('Keep both as separate notes')),
        OutlinedButton(onPressed: () => s.resolve(c, Resolution.keepLocal), child: const Text('Keep this device\'s')),
        OutlinedButton(onPressed: () => s.resolve(c, Resolution.keepRemote), child: const Text('Keep other device\'s')),
        FilledButton.icon(
          onPressed: () => s.resolve(c, Resolution.combine),
          icon: const Icon(Icons.merge_rounded),
          label: const Text('Combine both'),
        ),
      ],
    );
  }

  Widget _side(BuildContext context, String label, ConflictSide s) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: t.textTheme.titleSmall),
      Text('Edited ${formatDate(s.modified)}', style: t.textTheme.bodySmall),
      const SizedBox(height: 8),
      AspectRatio(
        aspectRatio: 0.75,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: t.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: s.thumb == null ? const Center(child: Icon(Icons.description_outlined, size: 48)) : Image.memory(s.thumb!, fit: BoxFit.cover, alignment: Alignment.topCenter),
        ),
      ),
    ]);
  }
}
