import 'package:caret_notes/core/settings.dart';
import 'package:caret_notes/ui/editor/toolbar.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const area = Size(1200, 800);
  test('dropping near an edge docks the toolbar there, elsewhere it floats', () {
    expect(dockFor(const Offset(500, 30), area), ToolbarDock.top);
    expect(dockFor(const Offset(30, 400), area), ToolbarDock.left);
    expect(dockFor(const Offset(1170, 400), area), ToolbarDock.right);
    expect(dockFor(const Offset(600, 400), area), ToolbarDock.floating);
  });
}
