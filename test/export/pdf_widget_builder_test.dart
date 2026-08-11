import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:narraity/services/export/markdown_lite.dart';
import 'package:narraity/services/export/pdf_widget_builder.dart';

void main() {
  const builder = PdfWidgetBuilder();

  String textOf(pw.RichText widget) {
    final span = widget.text as pw.TextSpan;
    final first = span.children!.first as pw.TextSpan;
    return first.text!;
  }

  /// Quote blocks wrap their `RichText` in a `Padding` for the left indent
  /// (see `PdfWidgetBuilder.blockWidgets`), so a plain `whereType` over the
  /// returned widget list misses it — this looks one level into any
  /// `Padding` wrapper too.
  pw.RichText firstRichText(List<pw.Widget> widgets) {
    for (final widget in widgets) {
      if (widget is pw.RichText) return widget;
      if (widget is pw.Padding && widget.child is pw.RichText) {
        return widget.child as pw.RichText;
      }
    }
    throw StateError('no RichText found');
  }

  group('paragraph indent', () {
    test('the first paragraph in a fresh indent state has no leading indent', () {
      final block = MarkdownLite.parse('First line of the chapter.').single;
      final state = ParagraphIndentState();
      final widgets = builder.blockWidgets(block, indentState: state);
      final richText = widgets.whereType<pw.RichText>().first;
      expect(textOf(richText), 'First line of the chapter.');
    });

    test('every paragraph after the first gets a leading-space indent', () {
      final blocks = MarkdownLite.parse('First paragraph.\n\nSecond paragraph.');
      final state = ParagraphIndentState();
      final widgets = <pw.Widget>[];
      for (final block in blocks) {
        widgets.addAll(builder.blockWidgets(block, indentState: state));
      }
      final richTexts = widgets.whereType<pw.RichText>().toList();
      expect(textOf(richTexts[0]), 'First paragraph.');
      expect(textOf(richTexts[1]), startsWith('  '));
      expect(textOf(richTexts[1]).trim(), 'Second paragraph.');
    });

    test('a null indent state (no tracking requested) never indents', () {
      final blocks = MarkdownLite.parse('First paragraph.\n\nSecond paragraph.');
      final widgets = <pw.Widget>[];
      for (final block in blocks) {
        widgets.addAll(builder.blockWidgets(block));
      }
      final richTexts = widgets.whereType<pw.RichText>().toList();
      expect(textOf(richTexts[0]), 'First paragraph.');
      expect(textOf(richTexts[1]), 'Second paragraph.');
    });

    test('multiple literal source lines within one paragraph block only skip indent on the first',
        () {
      final block = MarkdownLite.parse('Line one.\nLine two.\nLine three.').single;
      final state = ParagraphIndentState();
      final richTexts =
          builder.blockWidgets(block, indentState: state).whereType<pw.RichText>().toList();
      expect(textOf(richTexts[0]), 'Line one.');
      expect(textOf(richTexts[1]), startsWith(' '));
      expect(textOf(richTexts[2]), startsWith(' '));
    });
  });

  group('body text alignment', () {
    test('paragraph text is fully justified', () {
      final block = MarkdownLite.parse('Some prose that should be justified.').single;
      final richText = builder.blockWidgets(block).whereType<pw.RichText>().first;
      expect(richText.textAlign, pw.TextAlign.justify);
    });

    test('quotes and headings are not force-justified', () {
      final quoteBlock = MarkdownLite.parse('> A quoted line.').single;
      final quoteRichText = firstRichText(builder.blockWidgets(quoteBlock));
      expect(quoteRichText.textAlign, isNot(pw.TextAlign.justify));

      final headingBlock = MarkdownLite.parse('## A heading').single;
      final headingRichText = firstRichText(builder.blockWidgets(headingBlock));
      expect(headingRichText.textAlign, isNot(pw.TextAlign.justify));
    });
  });
}
