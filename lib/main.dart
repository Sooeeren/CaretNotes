import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import 'core/library/library_store.dart';
import 'core/settings.dart';
import 'ui/app.dart';
import 'ui/controllers.dart';
import 'ui/window_chrome.dart';
import 'ui/wiring.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  // CARETNOTES_HOME lets you run a separate profile (tests, demos, a second "device").
  final home = Platform.environment['CARETNOTES_HOME'];
  final support = home != null && home.isNotEmpty ? await Directory(home).create(recursive: true) : await getApplicationSupportDirectory();
  final settingsPath = p.join(support.path, 'settings.json');
  var settings = await AppSettings.load(settingsPath);
  if (settings.deviceName.isEmpty) {
    settings = settings.copyWith(deviceName: Platform.localHostname);
    await settings.save(settingsPath);
  }

  WindowChrome.apply(custom: !settings.nativeTitleBar);

  final store = LibraryStore(p.join(support.path, 'library'));
  await store.ensureRoot();
  // Recently deleted keeps items for 30 days.
  await store.purgeOlderThan(const Duration(days: 30));

  final settingsCtl = SettingsController(settings, settingsPath);
  final lib = LibraryController(store);
  await lib.refresh();

  final extra = await wireFeatures(store: store, settings: settingsCtl, library: lib, supportDir: support.path);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settingsCtl),
      ChangeNotifierProvider.value(value: lib),
      ...extra,
    ],
    child: const CaretNotesApp(),
  ));

  // `--open=<path relative to the library>` opens a note directly (handy for testing).
  for (final a in args) {
    if (a.startsWith('--open=')) {
      final rel = a.substring(7);
      WidgetsBinding.instance.addPostFrameCallback((_) => appNavigatorKey.currentState?.pushNamed('/editor', arguments: rel));
    }
  }
}
