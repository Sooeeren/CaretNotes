import 'dart:io';
import 'dart:typed_data';

/// TrueType fonts embedded in exported PDFs so typed text stays real, selectable text.
class ExportFonts {
  final Uint8List? regular, bold, italic, mono;
  const ExportFonts({this.regular, this.bold, this.italic, this.mono});

  /// System fonts: Segoe UI / Consolas on Windows, Roboto / Droid Sans Mono on Android.
  static Future<ExportFonts> system() async {
    Future<Uint8List?> load(List<String> candidates) async {
      for (final c in candidates) {
        final f = File(c);
        if (await f.exists()) return f.readAsBytes();
      }
      return null;
    }

    if (Platform.isWindows) {
      final dir = '${Platform.environment['WINDIR'] ?? r'C:\Windows'}\\Fonts';
      return ExportFonts(
        regular: await load(['$dir\\segoeui.ttf', '$dir\\arial.ttf']),
        bold: await load(['$dir\\segoeuib.ttf', '$dir\\arialbd.ttf']),
        italic: await load(['$dir\\segoeuii.ttf', '$dir\\ariali.ttf']),
        mono: await load(['$dir\\consola.ttf', '$dir\\cour.ttf']),
      );
    }
    if (Platform.isAndroid) {
      return ExportFonts(
        regular: await load(['/system/fonts/Roboto-Regular.ttf']),
        bold: await load(['/system/fonts/Roboto-Bold.ttf']),
        italic: await load(['/system/fonts/Roboto-Italic.ttf']),
        mono: await load(['/system/fonts/DroidSansMono.ttf']),
      );
    }
    if (Platform.isLinux) {
      // DejaVu ships with nearly every distro (Debian/Ubuntu, Fedora, Arch paths), Liberation as fallback.
      List<String> paths(String file) => [
            for (final d in [
              '/usr/share/fonts/truetype/dejavu',
              '/usr/share/fonts/dejavu-sans-fonts',
              '/usr/share/fonts/dejavu-sans-mono-fonts',
              '/usr/share/fonts/TTF',
              '/usr/share/fonts/dejavu',
            ])
              '$d/$file',
          ];
      List<String> liberation(String file) =>
          ['/usr/share/fonts/truetype/liberation/$file', '/usr/share/fonts/liberation-sans/$file', '/usr/share/fonts/liberation/$file'];
      return ExportFonts(
        regular: await load([...paths('DejaVuSans.ttf'), ...liberation('LiberationSans-Regular.ttf')]),
        bold: await load([...paths('DejaVuSans-Bold.ttf'), ...liberation('LiberationSans-Bold.ttf')]),
        italic: await load([...paths('DejaVuSans-Oblique.ttf'), ...liberation('LiberationSans-Italic.ttf')]),
        mono: await load([...paths('DejaVuSansMono.ttf'), ...liberation('LiberationMono-Regular.ttf')]),
      );
    }
    return const ExportFonts();
  }
}
