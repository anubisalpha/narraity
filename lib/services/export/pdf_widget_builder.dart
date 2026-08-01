import 'package:pdf/widgets.dart' as pw;

import '../../models/project.dart';
import 'markdown_lite.dart';

/// Shared `pw.Widget` construction for every PDF-based export path — general
/// PDF (`PdfExporter`) and KDP-ready print (`KdpPaperbackExporter`) render
/// the same manuscript content, just onto a different page/margin setup, so
/// this is the one place the Markdown-block-to-PDF-widget mapping lives
/// rather than being duplicated per exporter.
class PdfWidgetBuilder {
  const PdfWidgetBuilder();

  double headingFontSize(int depth) => switch (depth) {
        0 => 20,
        1 => 16,
        _ => 14,
      };

  List<pw.Widget> titlePageWidgets(Project project) {
    final widgets = <pw.Widget>[
      pw.SizedBox(height: 220),
      pw.Center(
        child: pw.Text(
          pdfSafeText(project.title),
          style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
        ),
      ),
    ];
    if (project.subtitle != null && project.subtitle!.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 12));
      widgets.add(pw.Center(
          child:
              pw.Text(pdfSafeText(project.subtitle!), style: const pw.TextStyle(fontSize: 16))));
    }
    if (project.author != null && project.author!.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 24));
      widgets.add(
        pw.Center(
            child: pw.Text('by ${pdfSafeText(project.author!)}',
                style: const pw.TextStyle(fontSize: 14))),
      );
    }
    widgets.add(pw.NewPage());
    return widgets;
  }

  // A section heading is small and finite, but every paragraph below it
  // (a whole chapter can be one continuous block of prose with no blank
  // lines) is not — so headings and body text alike are emitted as flat
  // top-level widgets with SizedBox spacers rather than wrapped in Padding.
  // `pw.Padding` is a SingleChildWidget, not a SpanningWidget like
  // `pw.RichText`/`pw.Text` are, so wrapping a paragraph in it makes the
  // whole thing an atomic block MultiPage must fit on one page. On top of
  // that, RichText/Text only actually behave as a SpanningWidget (its
  // `canSpan` getter) when `overflow: TextOverflow.span` is set — the
  // package's own default overflow is `visible`, which does NOT span. Both
  // conditions must hold, or MultiPage throws "Widget won't fit into the
  // page" for any paragraph taller than one page. See narraity issue #1's
  // follow-up PDF-export crash.
  List<pw.Widget> sectionHeadingWidgets(String title, int depth) => [
        pw.SizedBox(height: 20),
        pw.Text(
          pdfSafeText(title),
          style: pw.TextStyle(fontSize: headingFontSize(depth), fontWeight: pw.FontWeight.bold),
          overflow: pw.TextOverflow.span,
        ),
        pw.SizedBox(height: 10),
      ];

  // The `pdf` package's default theme uses the base-14 Helvetica font, which
  // has no glyphs outside WinAnsi Latin-1 — any real Unicode character (the
  // curly quotes/dashes/ellipsis a word processor or this app's own smart
  // typography produces) renders as a missing-glyph box. Embedding a real
  // Unicode TTF is the thorough fix but is a bigger call (which font,
  // licensing, app size) left for later; normalizing to the closest ASCII
  // equivalent here is enough to stop visibly broken output today.
  static final Map<String, String> _pdfUnsafeChars = {
    '‘': "'", '’': "'", // ‘ ’
    '“': '"', '”': '"', // “ ”
    '–': '-', '—': '--', // – —
    '…': '...', // …
    ' ': ' ', // non-breaking space
  };

  String pdfSafeText(String text) {
    var result = text;
    _pdfUnsafeChars.forEach((unsafe, safe) => result = result.replaceAll(unsafe, safe));
    return result;
  }

  pw.TextSpan spansFor(List<MdRun> runs, pw.TextStyle base) => pw.TextSpan(
        children: [
          for (final run in runs)
            pw.TextSpan(
              text: pdfSafeText(run.text),
              style: base.copyWith(
                fontWeight: run.bold ? pw.FontWeight.bold : base.fontWeight,
                fontStyle: run.italic ? pw.FontStyle.italic : base.fontStyle,
                decoration: run.strikethrough ? pw.TextDecoration.lineThrough : base.decoration,
              ),
            ),
        ],
      );

  List<pw.Widget> blockWidgets(MdBlock block) {
    switch (block.type) {
      case MdBlockType.sceneBreak:
        return [
          pw.SizedBox(height: 12),
          pw.Center(child: pw.Text('* * *')),
          pw.SizedBox(height: 12),
        ];

      case MdBlockType.heading:
        final size = headingFontSize((block.headingLevel - 1).clamp(0, 5));
        return [
          pw.SizedBox(height: 12),
          pw.RichText(
            text: spansFor(block.lines.first, pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold)),
            overflow: pw.TextOverflow.span,
          ),
          pw.SizedBox(height: 6),
        ];

      case MdBlockType.quote:
        // Left-indent still uses Padding (a SingleChildWidget), so an
        // individual quote line can't span pages if it alone is taller than
        // one page. Accepted trade-off: block quotes are short excerpts in
        // practice, unlike full chapters (see `paragraph` below, and the
        // wider comment above `sectionHeadingWidgets`). A Row-based indent
        // wouldn't help either — Flex.canSpan is hard-false for horizontal.
        return block.lines.expand((line) sync* {
          yield pw.Padding(
            padding: const pw.EdgeInsets.only(left: 24),
            child: pw.RichText(
              text: spansFor(line, const pw.TextStyle()),
              overflow: pw.TextOverflow.span,
            ),
          );
          yield pw.SizedBox(height: 4);
        }).toList();

      case MdBlockType.paragraph:
        return block.lines.expand((line) sync* {
          yield pw.RichText(
            text: spansFor(line, const pw.TextStyle()),
            overflow: pw.TextOverflow.span,
          );
          yield pw.SizedBox(height: 4);
        }).toList();
    }
  }
}
