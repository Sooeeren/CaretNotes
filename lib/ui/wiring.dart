import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/library/library_store.dart';
import 'app.dart';
import 'controllers.dart';
import 'editor/canvas_view.dart';
import 'editor/editor_screen.dart';
import 'editor/image_box.dart';
import 'home/home_screen.dart';

/// Connects feature modules (editor, sync, export) to the shell. Returns extra providers.
Future<List<SingleChildWidget>> wireFeatures({
  required LibraryStore store,
  required SettingsController settings,
  required LibraryController library,
  required String supportDir,
}) async {
  appRoutes['/editor'] = (args) => EditorScreen(relPath: args as String);
  importPdfAction = importPdfIntoLibrary;
  cropImageAction = cropImage;
  return <SingleChildWidget>[
    Provider<LibraryStore>.value(value: store),
  ];
}
