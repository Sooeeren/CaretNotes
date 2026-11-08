import 'dart:convert';
import 'dart:io';

enum ThemePref { system, light, dark }

enum SideButtonAction { eraser, lasso }

enum ToolbarDock { top, left, right, floating }

enum SyncProvider { none, folder, webdav, gdrive }

class AppSettings {
  static const defaultAccent = 0xFFD9772B;
  static const _oldDefaultAccent = 0xFFFF8A1F;

  final ThemePref theme;
  final int accent;
  final bool fingerDrawing;
  final SideButtonAction sideButton;
  final ToolbarDock toolbarDock;
  final double floatX, floatY;
  final SyncProvider syncProvider;

  /// Provider-specific, non-secret config (folder path, WebDAV url/user, Google client id).
  final Map<String, String> syncConfig;
  final String deviceName;
  final bool leftHanded;
  final List<int> penColors;

  const AppSettings({
    this.theme = ThemePref.system,
    this.accent = defaultAccent,
    this.fingerDrawing = false,
    this.sideButton = SideButtonAction.eraser,
    this.toolbarDock = ToolbarDock.top,
    this.floatX = 80,
    this.floatY = 80,
    this.syncProvider = SyncProvider.none,
    this.syncConfig = const {},
    this.deviceName = '',
    this.leftHanded = false,
    this.penColors = const [0xFF111111, 0xFF1B2A6B, 0xFFD23B3B, 0xFF1A8F3C, 0xFF3B6FE0, 0xFF9B3FD1, 0xFFE07A1F],
  });

  AppSettings copyWith({
    ThemePref? theme,
    int? accent,
    bool? fingerDrawing,
    SideButtonAction? sideButton,
    ToolbarDock? toolbarDock,
    double? floatX,
    double? floatY,
    SyncProvider? syncProvider,
    Map<String, String>? syncConfig,
    String? deviceName,
    bool? leftHanded,
    List<int>? penColors,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        accent: accent ?? this.accent,
        fingerDrawing: fingerDrawing ?? this.fingerDrawing,
        sideButton: sideButton ?? this.sideButton,
        toolbarDock: toolbarDock ?? this.toolbarDock,
        floatX: floatX ?? this.floatX,
        floatY: floatY ?? this.floatY,
        syncProvider: syncProvider ?? this.syncProvider,
        syncConfig: syncConfig ?? this.syncConfig,
        deviceName: deviceName ?? this.deviceName,
        leftHanded: leftHanded ?? this.leftHanded,
        penColors: penColors ?? this.penColors,
      );

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'accent': accent,
        'finger': fingerDrawing,
        'sideButton': sideButton.name,
        'dock': toolbarDock.name,
        'floatX': floatX,
        'floatY': floatY,
        'sync': syncProvider.name,
        'syncConfig': syncConfig,
        'device': deviceName,
        'leftHanded': leftHanded,
        'penColors': penColors,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    T e<T extends Enum>(List<T> values, Object? v, T d) => values.asNameMap()[v] ?? d;
    const d = AppSettings();
    return AppSettings(
      theme: e(ThemePref.values, j['theme'], d.theme),
      accent: switch (j['accent'] as int?) {
        null || _oldDefaultAccent => d.accent, // move users off the old, louder default
        final int a => a,
      },
      fingerDrawing: j['finger'] as bool? ?? d.fingerDrawing,
      sideButton: e(SideButtonAction.values, j['sideButton'], d.sideButton),
      toolbarDock: e(ToolbarDock.values, j['dock'], d.toolbarDock),
      floatX: (j['floatX'] as num?)?.toDouble() ?? d.floatX,
      floatY: (j['floatY'] as num?)?.toDouble() ?? d.floatY,
      syncProvider: e(SyncProvider.values, j['sync'], d.syncProvider),
      syncConfig: (j['syncConfig'] as Map?)?.cast<String, String>() ?? const {},
      deviceName: j['device'] as String? ?? '',
      leftHanded: j['leftHanded'] as bool? ?? false,
      penColors: (j['penColors'] as List?)?.cast<int>() ?? d.penColors,
    );
  }

  static Future<AppSettings> load(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return const AppSettings();
      return AppSettings.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(String path) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()), flush: true);
    await tmp.rename(path);
  }
}
