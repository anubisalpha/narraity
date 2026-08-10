import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Loads the bundled Noto Sans TTFs (`assets/fonts/noto_sans/`, OFL-licensed
/// via Google Fonts) once and exposes them as a `pw.ThemeData` for every PDF
/// export path to use. The `pdf` package's default base-14 Helvetica has no
/// glyphs outside WinAnsi Latin-1 — real Unicode text (curly quotes/dashes,
/// non-Latin scripts) rendered as missing-glyph boxes without this. Loaded
/// as raw asset bytes via `rootBundle`, not registered as a Flutter `fonts:`
/// family — `pw.Font.ttf` needs the TTF bytes directly and is independent of
/// Flutter's own font system.
class PdfFonts {
  static pw.ThemeData? _cached;

  static Future<pw.ThemeData> theme() async {
    final cached = _cached;
    if (cached != null) return cached;

    Future<pw.Font> load(String name) async {
      final data = await rootBundle.load('assets/fonts/noto_sans/NotoSans-$name.ttf');
      return pw.Font.ttf(data);
    }

    final theme = pw.ThemeData.withFont(
      base: await load('Regular'),
      bold: await load('Bold'),
      italic: await load('Italic'),
      boldItalic: await load('BoldItalic'),
    );
    _cached = theme;
    return theme;
  }
}
