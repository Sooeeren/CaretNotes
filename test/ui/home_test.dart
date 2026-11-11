import 'dart:io';

import 'package:caret_notes/core/library/library_store.dart';
import 'package:caret_notes/core/model/folder_meta.dart';
import 'package:caret_notes/core/model/note.dart';
import 'package:caret_notes/core/settings.dart';
import 'package:caret_notes/ui/controllers.dart';
import 'package:caret_notes/ui/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('home shows folder tile and note card; tapping folder updates breadcrumbs', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Directory tmp;
    late LibraryController lib;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('cn_home_');
      final store = LibraryStore(tmp.path);
      final sem = await store.createFolder('', 'Semester 3', const FolderMeta(color: 0xFF3B6FE0, icon: 'school'));
      await store.createNote('', Note.create(title: 'VL 1', layout: NoteLayout.paged, deviceName: 't'));
      await store.createNote(sem, Note.create(title: 'Inside', layout: NoteLayout.paged, deviceName: 't'));
      lib = LibraryController(store);
      await lib.refresh();
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryController>.value(value: lib),
        ChangeNotifierProvider(create: (_) => SettingsController(const AppSettings(), null)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('folder-tile-Semester 3')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-card-VL 1.cnote')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('folder-tile-Semester 3')));
    // The tap set currentDir synchronously; load it for real (file IO can't run in the fake clock).
    expect(lib.currentDir, 'Semester 3');
    await tester.runAsync(() => lib.refresh());
    await tester.pump();

    expect(find.byKey(const ValueKey('crumb-Semester 3')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-card-Semester 3/Inside.cnote')), findsOneWidget);

    await tester.runAsync(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {
        // Windows may still hold a handle from a pending thumbnail read; temp dir is cleaned by the OS.
      }
    });
  });

  testWidgets('a small window keeps the home header usable: search folds into a button', (tester) async {
    // The narrowest window (480) minus the window buttons, which tests don't show.
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Directory tmp;
    late LibraryController lib;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('cn_home_');
      lib = LibraryController(LibraryStore(tmp.path));
      await lib.refresh();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryController>.value(value: lib),
        ChangeNotifierProvider(create: (_) => SettingsController(const AppSettings(), null)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'no overflow in the header');
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget, reason: 'select and grid/list fold into a menu');
    await tester.runAsync(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
  });
}
