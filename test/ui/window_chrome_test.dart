import 'package:caret_notes/ui/window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget header() => const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 60,
            child: CaptionArea(child: Row(children: [Expanded(child: Text('All notes')), WindowButtons(height: 60, inactiveWidth: 20)])),
          ),
        ),
      );

  tearDown(() => WindowChrome.active.value = false);

  testWidgets('with the system title bar there are no window buttons', (tester) async {
    await tester.pumpWidget(header());
    expect(find.byTooltip('Close'), findsNothing);
  });

  testWidgets('the close button asks the app to exit, so open notes get saved first', (tester) async {
    var closes = 0;
    final saved = WindowChrome.requestClose;
    WindowChrome.requestClose = () async => closes++;
    addTearDown(() => WindowChrome.requestClose = saved);
    WindowChrome.active.value = true;
    await tester.pumpWidget(header());
    expect(find.byTooltip('Minimize'), findsOneWidget);
    expect(find.byTooltip('Maximize'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(closes, 1);
  });
}
