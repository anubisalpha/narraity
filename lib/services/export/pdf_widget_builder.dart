import 'package:pdf/widgets.dart' as pw;

import '../../models/export_outline.dart';
import '../../models/project.dart';
import '../annotation_service.dart';
import '../manuscript_service.dart';
import 'footnote_markers.dart';
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

  /// [indent] prepends [_paragraphIndent] to the very first run's text only
  /// — since `pw.RichText` has no CSS-style `text-indent`, this is the
  /// established workaround: leading spaces inside the text itself only
  /// ever show up on the first rendered line of the block, matching real
  /// first-line-indent behavior without needing per-line layout knowledge.
  pw.TextSpan spansFor(List<MdRun> runs, pw.TextStyle base, {bool indent = false}) => pw.TextSpan(
        children: [
          for (var i = 0; i < runs.length; i++)
            pw.TextSpan(
              text: pdfSafeText(_withSuperscriptFootnoteMarkers(
                  i == 0 && indent ? '$_paragraphIndent${runs[i].text}' : runs[i].text)),
              style: base.copyWith(
                fontWeight: runs[i].bold ? pw.FontWeight.bold : base.fontWeight,
                fontStyle: runs[i].italic ? pw.FontStyle.italic : base.fontStyle,
                decoration:
                    runs[i].strikethrough ? pw.TextDecoration.lineThrough : base.decoration,
              ),
            ),
        ],
      );

  /// Approximates a 0.5in first-line indent (matching `DocxExporter`'s
  /// `w:firstLine="720"` twips and the EPUB stylesheet's `text-indent:
  /// 1.5em`) via literal leading spaces — the only lever `pw.RichText`
  /// offers, since the `pdf` package has no first-line-only indent concept.
  static const _paragraphIndent = '      ';

  static const _superscriptDigits = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  };

  /// Replaces every `FootnoteMarkers`-wrapped number with its literal
  /// Unicode superscript-digit rendering (`¹`, `²`, …) — no special text
  /// style needed, since these are genuine standalone characters the
  /// embedded Unicode font (`PdfFonts`) has glyphs for. `pw.MultiPage` has
  /// no per-page footnote area (fixed margins, no per-page callback), so
  /// true page-bottom footnotes aren't possible here — this is the
  /// in-text reference half; see `footnoteListWidgets` for where the body
  /// text ends up instead.
  String _withSuperscriptFootnoteMarkers(String text) {
    if (!FootnoteMarkers.mayContainMarker(text)) return text;
    return text.replaceAllMapped(FootnoteMarkers.pattern, (match) {
      final digits = match.group(1)!.split('').map((d) => _superscriptDigits[d]!).join();
      return digits;
    });
  }

  /// A small numbered list rendering each footnote's body text, meant to be
  /// inserted right before the next chapter boundary — the same "collected
  /// at chapter end" placement `EpubExporter` uses for its `<aside>`
  /// elements, since it's the closest analog available without true
  /// page-bottom footnotes.
  List<pw.Widget> footnoteListWidgets(Map<int, String> bodies) {
    if (bodies.isEmpty) return [];
    final numbers = bodies.keys.toList()..sort();
    return [
      pw.SizedBox(height: 16),
      pw.Divider(thickness: 0.5),
      pw.SizedBox(height: 4),
      for (final number in numbers)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.RichText(
            text: pw.TextSpan(
              text: '${number.toString().split('').map((d) => _superscriptDigits[d]!).join()} '
                  '${pdfSafeText(bodies[number]!)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            overflow: pw.TextOverflow.span,
          ),
        ),
    ];
  }

  /// Renders one section's content into widgets with its footnote markers
  /// already resolved via [FootnoteMarkers] — the lower-level primitive
  /// `buildManuscriptBody` composes into a flat single-pass build.
  /// `KdpPaperbackExporter` calls this directly instead, since it needs its
  /// own page-break/chapter-grouping strategy (separate `MultiPage`s per
  /// chapter, for header suppression on each one's first page).
  Future<SceneWidgetsResult> sceneWidgets({
    required ExportSection section,
    required ManuscriptService manuscript,
    required AnnotationService annotations,
    required int nextFootnoteNumber,
    ParagraphIndentState? indentState,
  }) async {
    final doc = await manuscript.readScene(section.id, fallbackTitle: section.title);
    final marked = await FootnoteMarkers.markContent(
      annotations: annotations,
      sceneId: section.id,
      content: doc.content,
      startNumber: nextFootnoteNumber,
    );
    final widgets = <pw.Widget>[
      if (section.showTitle) ...sectionHeadingWidgets(section.title, section.depth),
      for (final block in MarkdownLite.parse(marked.content))
        ...blockWidgets(block, indentState: indentState),
    ];
    return SceneWidgetsResult(
      widgets: widgets,
      footnoteBodies: marked.bodies,
      nextFootnoteNumber: marked.nextNumber,
    );
  }

  /// Builds every body widget for [sections], resolving footnote markers
  /// against [annotations] along the way — the shared "manuscript body"
  /// builder behind `PdfExporter`'s flat single-pass build. Footnote bodies
  /// are collected per chapter-group (the same `startsNewPage` grouping
  /// that decides page breaks) and flushed as a small list right before the
  /// next chapter boundary, or at the very end of the last one.
  Future<List<pw.Widget>> buildManuscriptBody({
    required List<ExportSection> sections,
    required ManuscriptService manuscript,
    required AnnotationService annotations,
  }) async {
    final widgets = <pw.Widget>[];
    var nextFootnoteNumber = 1;
    var groupFootnotes = <int, String>{};
    var indentState = ParagraphIndentState();

    void flushGroupFootnotes() {
      widgets.addAll(footnoteListWidgets(groupFootnotes));
      groupFootnotes = {};
    }

    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      if (section.startsNewPage && i > 0) {
        flushGroupFootnotes();
        widgets.add(pw.NewPage());
        // Fresh per chapter-boundary group, matching `EpubExporter`'s
        // per-chapter-file `noindent` reset — only each chapter's own
        // opening paragraph skips the first-line indent.
        indentState = ParagraphIndentState();
      }
      final result = await sceneWidgets(
        section: section,
        manuscript: manuscript,
        annotations: annotations,
        nextFootnoteNumber: nextFootnoteNumber,
        indentState: indentState,
      );
      groupFootnotes.addAll(result.footnoteBodies);
      nextFootnoteNumber = result.nextFootnoteNumber;
      widgets.addAll(result.widgets);
    }
    flushGroupFootnotes();
    return widgets;
  }

  List<pw.Widget> blockWidgets(MdBlock block, {ParagraphIndentState? indentState}) {
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
          // Per-line, not per-block: a paragraph `MdBlock` holds one entry
          // in `lines` per literal source line (dialogue, verse), and
          // `EpubExporter`'s `<p>`-per-line convention treats each the same
          // way — every one after the group's first counts as a "subsequent
          // paragraph" for indent purposes.
          final isFirst = indentState == null || !indentState.sawFirstParagraph;
          indentState?.sawFirstParagraph = true;
          yield pw.RichText(
            text: spansFor(line, const pw.TextStyle(), indent: !isFirst),
            textAlign: pw.TextAlign.justify,
            overflow: pw.TextOverflow.span,
          );
          yield pw.SizedBox(height: 4);
        }).toList();
    }
  }
}

/// Threaded through paragraph rendering within one chapter-boundary group
/// (see `buildManuscriptBody`/`KdpPaperbackExporter`) so only the group's
/// very first paragraph line skips the first-line indent — matching
/// `EpubExporter`'s per-chapter `noindent` rule. A plain mutable holder
/// rather than threading an immutable flag through return values, since
/// `sceneWidgets`/`blockWidgets` run in a simple sequential loop across
/// several scenes per group, not recursively.
class ParagraphIndentState {
  bool sawFirstParagraph = false;
}

/// Result of [PdfWidgetBuilder.sceneWidgets] — the rendered widgets plus the
/// running footnote-numbering state the caller threads into the next scene.
class SceneWidgetsResult {
  const SceneWidgetsResult({
    required this.widgets,
    required this.footnoteBodies,
    required this.nextFootnoteNumber,
  });

  final List<pw.Widget> widgets;
  final Map<int, String> footnoteBodies;
  final int nextFootnoteNumber;
}
