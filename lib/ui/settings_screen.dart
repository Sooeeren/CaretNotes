import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/library/library_store.dart';
import '../core/settings.dart';
import 'controllers.dart';
import 'folder_style.dart';
import 'sync/sync_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SettingsController>();
    final s = sc.value;
    final t = Theme.of(context);
    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                ...children,
              ]),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: t.scaffoldBackgroundColor),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            section('Appearance', [
              ListTile(
                title: const Text('Theme'),
                trailing: SegmentedButton<ThemePref>(
                  segments: const [
                    ButtonSegment(value: ThemePref.system, label: Text('System')),
                    ButtonSegment(value: ThemePref.light, label: Text('Light')),
                    ButtonSegment(value: ThemePref.dark, label: Text('Dark')),
                  ],
                  selected: {s.theme},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => sc.update((x) => x.copyWith(theme: v.first)),
                ),
              ),
              ListTile(
                title: const Text('Accent color'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final c in folderColors.skip(1))
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => sc.update((x) => x.copyWith(accent: c)),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(color: s.accent == c ? t.colorScheme.onSurface : Colors.transparent, width: 3),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ]),
            section('Pen & touch', [
              SwitchListTile(
                title: const Text('Draw with finger'),
                subtitle: const Text('Off: fingers scroll and zoom, only the pen writes. Your palm is always ignored while the pen is near.'),
                value: s.fingerDrawing,
                onChanged: (v) => sc.update((x) => x.copyWith(fingerDrawing: v)),
              ),
              ListTile(
                title: const Text('S Pen side button'),
                subtitle: const Text('What happens while you hold the button and write'),
                trailing: SegmentedButton<SideButtonAction>(
                  segments: const [
                    ButtonSegment(value: SideButtonAction.eraser, label: Text('Eraser')),
                    ButtonSegment(value: SideButtonAction.lasso, label: Text('Select')),
                  ],
                  selected: {s.sideButton},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => sc.update((x) => x.copyWith(sideButton: v.first)),
                ),
              ),
              ListTile(
                title: const Text('Toolbar position'),
                subtitle: const Text('You can also hold the toolbar and drag it while writing'),
                trailing: DropdownButton<ToolbarDock>(
                  value: s.toolbarDock,
                  items: const [
                    DropdownMenuItem(value: ToolbarDock.top, child: Text('Top')),
                    DropdownMenuItem(value: ToolbarDock.left, child: Text('Left')),
                    DropdownMenuItem(value: ToolbarDock.right, child: Text('Right')),
                    DropdownMenuItem(value: ToolbarDock.floating, child: Text('Floating')),
                  ],
                  onChanged: (v) => sc.update((x) => x.copyWith(toolbarDock: v)),
                ),
              ),
            ]),
            section('Sync', [const _SyncSettings()]),
            section('Device & storage', [
              ListTile(
                title: const Text('Device name'),
                subtitle: Text('${s.deviceName}  ·  shown when a note was changed on two devices'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final c = TextEditingController(text: s.deviceName);
                  final v = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Device name'),
                      content: TextField(controller: c, autofocus: true),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
                      ],
                    ),
                  );
                  if (v != null && v.isNotEmpty) await sc.update((x) => x.copyWith(deviceName: v));
                },
              ),
              ListTile(
                title: const Text('Library folder on this device'),
                subtitle: Text(context.read<LibraryStore>().root),
                trailing: const Icon(Icons.folder_open_rounded),
                onTap: () => launchUrl(Uri.file(context.read<LibraryStore>().root)),
              ),
            ]),
            Center(child: Text('CaretNotes · open source (MIT)', style: t.textTheme.bodySmall)),
          ]),
        ),
      ),
    );
  }
}

class _SyncSettings extends StatefulWidget {
  const _SyncSettings();
  @override
  State<_SyncSettings> createState() => _SyncSettingsState();
}

class _SyncSettingsState extends State<_SyncSettings> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pw = TextEditingController();
  final _clientId = TextEditingController();
  final _secret = TextEditingController();
  bool _googleSignedIn = false;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<SettingsController>().value.syncConfig;
    _url.text = cfg['url'] ?? '';
    _user.text = cfg['user'] ?? '';
    _clientId.text = cfg['clientId'] ?? '';
    _secret.text = cfg['clientSecret'] ?? '';
    context.read<SyncController>().google.signedIn.then((v) {
      if (mounted) setState(() => _googleSignedIn = v);
    });
  }

  Future<void> _setConfig(Map<String, String> patch, {SyncProvider? provider}) => context
      .read<SettingsController>()
      .update((x) => x.copyWith(syncProvider: provider ?? x.syncProvider, syncConfig: {...x.syncConfig, ...patch}));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>().value;
    final sync = context.watch<SyncController>();
    final t = Theme.of(context);
    final note = t.textTheme.bodySmall;

    Widget providerTile(SyncProvider p, String title, String subtitle, IconData icon) => RadioListTile<SyncProvider>(
          value: p,
          groupValue: s.syncProvider,
          onChanged: (v) => _setConfig({}, provider: v),
          title: Text(title),
          subtitle: Text(subtitle),
          secondary: Icon(icon),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      providerTile(SyncProvider.none, 'Off', 'Notes stay on this device only', Icons.cloud_off_rounded),
      providerTile(SyncProvider.folder, 'Synced folder (Proton Drive, OneDrive, Dropbox…)',
          'Pick a folder that your cloud\'s desktop app keeps in sync', Icons.folder_shared_rounded),
      if (s.syncProvider == SyncProvider.folder)
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(s.syncConfig['path']?.isNotEmpty == true ? s.syncConfig['path']! : 'No folder chosen', style: t.textTheme.bodyMedium)),
              FilledButton.tonal(
                onPressed: () async {
                  final d = await getDirectoryPath(confirmButtonText: 'Use this folder');
                  if (d != null) await _setConfig({'path': d});
                },
                child: const Text('Choose folder…'),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'Proton Drive: install the Proton Drive app for Windows, then choose a folder inside your Proton Drive '
              '(for example "Proton Drive\\CaretNotes"). Use the same folder on every device.',
              style: note,
            ),
          ]),
        ),
      providerTile(SyncProvider.gdrive, 'Google Drive', 'Signs in with your Google account; notes go into a "CaretNotes" folder', Icons.add_to_drive_rounded),
      if (s.syncProvider == SyncProvider.gdrive)
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Google needs a free "OAuth client" for apps that aren\'t in a store. The README explains how to make one in 5 minutes.', style: note),
            const SizedBox(height: 8),
            TextField(
              controller: _clientId,
              decoration: const InputDecoration(labelText: 'Client ID (….apps.googleusercontent.com)'),
              onChanged: (v) => _setConfig({'clientId': v.trim()}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _secret,
              decoration: const InputDecoration(labelText: 'Client secret'),
              obscureText: true,
              onChanged: (v) => _setConfig({'clientSecret': v.trim()}),
            ),
            const SizedBox(height: 8),
            Row(children: [
              if (!_googleSignedIn)
                FilledButton.icon(
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Sign in with Google'),
                  onPressed: _clientId.text.trim().isEmpty
                      ? null
                      : () async {
                          try {
                            await sync.signInGoogle();
                            if (mounted) setState(() => _googleSignedIn = true);
                          } catch (e) {
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
                          }
                        },
                )
              else ...[
                const Icon(Icons.check_circle_rounded, color: Colors.green),
                const SizedBox(width: 8),
                const Text('Signed in'),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () async {
                    await sync.signOutGoogle();
                    if (mounted) setState(() => _googleSignedIn = false);
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ]),
          ]),
        ),
      providerTile(SyncProvider.webdav, 'WebDAV (Nextcloud and others)', 'Any server that speaks WebDAV', Icons.dns_rounded),
      if (s.syncProvider == SyncProvider.webdav)
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Column(children: [
            TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: 'Address, e.g. https://cloud.example.org/remote.php/dav/files/me/CaretNotes'),
              onChanged: (v) => _setConfig({'url': v.trim()}),
            ),
            const SizedBox(height: 8),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'User name'), onChanged: (v) => _setConfig({'user': v.trim()})),
            const SizedBox(height: 8),
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password or app password (stored encrypted)'),
              onSubmitted: (v) => sync.setWebDavPassword(v),
              onChanged: (v) => sync.setWebDavPassword(v),
            ),
          ]),
        ),
      if (s.syncProvider != SyncProvider.none)
        ListTile(
          leading: Icon(sync.status == SyncStatus.error ? Icons.error_outline_rounded : Icons.cloud_sync_rounded,
              color: sync.status == SyncStatus.error ? t.colorScheme.error : null),
          title: Text(switch (sync.status) {
            SyncStatus.syncing => 'Syncing…',
            SyncStatus.error => 'Last sync failed',
            SyncStatus.offline => 'Offline',
            _ => sync.lastSync == null ? 'Not synced yet' : 'Last synced ${TimeOfDay.fromDateTime(sync.lastSync!).format(context)}',
          }),
          subtitle: sync.lastError == null ? const Text('Syncs at start, every 3 minutes and when you close a note') : Text(sync.lastError!),
          trailing: FilledButton(onPressed: sync.status == SyncStatus.syncing ? null : () => sync.syncNow(), child: const Text('Sync now')),
        ),
      if (Platform.isWindows && s.syncProvider == SyncProvider.folder)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Tip: notes are saved here first and copied into the synced folder, so writing never waits for the cloud.', style: note),
        ),
    ]);
  }
}
