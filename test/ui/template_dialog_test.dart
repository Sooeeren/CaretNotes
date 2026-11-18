import 'package:caret_notes/core/model/page.dart';
import 'package:caret_notes/ui/editor/template_dialog.dart';
import 'package:caret_notes/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('grid paper is set by columns, other paper by spacing', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    (Template?, bool)? result;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(const Color(0xFFD9772B), Brightness.light),
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => result = await showTemplateDialog(ctx, const Template(kind: TemplateKind.grid, spacing: 5 * 2.83465)),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('42 columns'), findsOneWidget);
    expect(find.textContaining('Spacing'), findsNothing);

    // Slide all the way right: the most columns, squares fitting the page exactly.
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('60 columns'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result!.$1!.spacing * 60, closeTo(595.28, 1e-6));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lined'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Spacing'), findsOneWidget);
    expect(find.textContaining('columns'), findsNothing);
  });
}
