import 'dart:convert';

import 'package:caret_notes/core/settings.dart';
import 'package:caret_notes/core/update/update_check.dart';
import 'package:caret_notes/ui/controllers.dart';
import 'package:caret_notes/ui/update/update_controller.dart';
import 'package:caret_notes/ui/update/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final release = ReleaseInfo.fromJson({
    'tag_name': 'v9.0.0',
    'html_url': 'https://github.com/Sooeeren/CaretNotes/releases/tag/v9.0.0',
    'body': '### What\'s new\n- Something nice',
    'assets': [
      {'name': 'caretnotes_9.0.0_amd64.deb', 'browser_download_url': 'https://example.invalid/a.deb', 'size': 10},
    ],
  });

  testWidgets('the update dialog shows the versions and Skip remembers the version', (tester) async {
    final settings = SettingsController(const AppSettings(), null);
    final updates = UpdateController(
      settings: settings,
      client: MockClient((_) async => http.Response(jsonEncode({}), 404)),
      kind: InstallKind.deb,
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(onPressed: () => showUpdateDialog(context, updates, release), child: const Text('open')),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('CaretNotes 9.0.0 is available'), findsOneWidget);
    expect(find.text('Something nice'), findsOneWidget);
    // a .deb install can't replace itself: the button downloads, with a hint how to install
    expect(find.text('Download'), findsOneWidget);
    expect(find.textContaining('package manager'), findsOneWidget);

    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();
    expect(settings.value.skippedVersion, '9.0.0');
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('a skipped version stays quiet on start, a newer one does not', (tester) async {
    await tester.runAsync(() async {
      final settings = SettingsController(const AppSettings(skippedVersion: '9.0.0'), null);
      UpdateController controller(String tag) => UpdateController(
            settings: settings,
            client: MockClient((_) async => http.Response(jsonEncode({'tag_name': tag, 'assets': []}), 200)),
            kind: InstallKind.other,
          );
      expect(await controller('v9.0.0').startupCheck(), isNull);
      expect((await controller('v9.1.0').startupCheck())?.version.toString(), '9.1.0');
      await settings.update((s) => s.copyWith(checkUpdates: false));
      expect(await controller('v9.1.0').startupCheck(), isNull);
    });
  });
}
