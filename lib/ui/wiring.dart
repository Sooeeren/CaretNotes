import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/library/library_store.dart';
import '../core/sync/secret_store.dart';
import 'app.dart';
import 'controllers.dart';
import 'editor/canvas_view.dart';
import 'editor/editor_screen.dart';
import 'editor/image_box.dart';
import 'export_dialog.dart';
import 'home/folder_grid.dart';
import 'home/home_screen.dart';
import 'settings_screen.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_widgets.dart';

/// Connects feature modules (editor, sync, export) to the shell. Returns extra providers.
Future<List<SingleChildWidget>> wireFeatures({
  required LibraryStore store,
  required SettingsController settings,
  required LibraryController library,
  required String supportDir,
}) async {
  final sync = SyncController(store: store, settings: settings, library: library, secrets: SecretStore(p.join(supportDir, 'secrets')));

  appRoutes['/editor'] = (args) => EditorScreen(relPath: args as String);
  appRoutes['/settings'] = (_) => const SettingsScreen();
  importPdfAction = importPdfIntoLibrary;
  cropImageAction = cropImage;
  exportNoteAction = exportEntry;
  editorExportAction = (ctx, note, relPath) => showExportDialog(ctx, note);
  exportSelectionAction = exportSelectionImage;
  sidebarFooterBuilder = (_) => const SyncStatusTile();
  onNoteOpened = sync.noteOpened;
  onNoteClosed = sync.noteClosed;

  WidgetsBinding.instance.addPostFrameCallback((_) => sync.start());
  return <SingleChildWidget>[
    Provider<LibraryStore>.value(value: store),
    ChangeNotifierProvider<SyncController>.value(value: sync),
  ];
}
