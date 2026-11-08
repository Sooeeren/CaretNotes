import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/library/library_store.dart';
import 'controllers.dart';

/// Connects feature modules (editor, sync, export) to the shell. Returns extra providers.
Future<List<SingleChildWidget>> wireFeatures({
  required LibraryStore store,
  required SettingsController settings,
  required LibraryController library,
  required String supportDir,
}) async {
  return <SingleChildWidget>[
    Provider<LibraryStore>.value(value: store),
  ];
}
