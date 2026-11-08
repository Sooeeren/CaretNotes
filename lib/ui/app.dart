import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import 'controllers.dart';
import 'home/home_screen.dart';
import 'theme.dart';

/// Route builders registered by feature modules (editor, settings).
final Map<String, Widget Function(Object? args)> appRoutes = {};

class CaretNotesApp extends StatelessWidget {
  const CaretNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>().value;
    final accent = Color(s.accent);
    return MaterialApp(
      title: 'CaretNotes',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(accent, Brightness.light),
      darkTheme: buildTheme(accent, Brightness.dark),
      themeMode: switch (s.theme) {
        ThemePref.system => ThemeMode.system,
        ThemePref.light => ThemeMode.light,
        ThemePref.dark => ThemeMode.dark,
      },
      home: const HomeScreen(),
      onGenerateRoute: (rs) {
        final b = appRoutes[rs.name];
        if (b == null) return null;
        return MaterialPageRoute(settings: rs, builder: (_) => b(rs.arguments));
      },
    );
  }
}
