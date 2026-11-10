import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/update_check.dart';
import 'update_controller.dart';

/// "CaretNotes 1.4.0 is available": the release notes and Skip / Later / Update.
Future<void> showUpdateDialog(BuildContext context, UpdateController updates, ReleaseInfo r) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(updates: updates, release: r),
  );
}

/// The Settings button: checks now and always says what it found.
Future<void> checkForUpdatesNow(BuildContext context, UpdateController updates) async {
  final r = await updates.check();
  if (!context.mounted) return;
  if (r != null) return showUpdateDialog(context, updates, r);
  final msg = updates.error != null ? 'Could not check for updates: ${updates.error}' : 'CaretNotes ${UpdateController.current} is up to date.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _UpdateDialog extends StatefulWidget {
  final UpdateController updates;
  final ReleaseInfo release;
  const _UpdateDialog({required this.updates, required this.release});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  String? _error;
  bool _busy = false;

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.updates.install(widget.release);
      if (mounted && !widget.updates.selfUpdates) Navigator.of(context).pop();
    } on UpdateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final u = widget.updates;
    final r = widget.release;
    final canInstall = u.selfUpdates && r.assetFor(u.kind) != null;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) => AlertDialog(
        title: const Text('Update available'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CaretNotes ${r.version} is available. You have ${UpdateController.current}.'),
            if (r.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: DecoratedBox(
                  decoration: BoxDecoration(border: Border.all(color: t.dividerColor), borderRadius: BorderRadius.circular(8)),
                  child: Markdown(data: r.notes, shrinkWrap: true, padding: const EdgeInsets.all(12), onTapLink: (_, href, _) => _open(href)),
                ),
              ),
            ],
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => _open(r.pageUrl),
              child: const Text('Full release notes on GitHub'),
            ),
            if (!canInstall && u.manualHint != null) Text(u.manualHint!, style: t.textTheme.bodySmall),
            if (u.progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: u.progress),
              const SizedBox(height: 4),
              Text('Downloading… ${(u.progress! * 100).round()} %', style: t.textTheme.bodySmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error)),
            ],
          ]),
        ),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await u.skip(r);
                    if (context.mounted) Navigator.of(context).pop();
                  },
            child: const Text('Skip this version'),
          ),
          TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Later')),
          FilledButton(onPressed: _busy ? null : _install, child: Text(canInstall ? 'Update and restart' : 'Download')),
        ],
      ),
    );
  }

  void _open(String? href) {
    if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
  }
}
