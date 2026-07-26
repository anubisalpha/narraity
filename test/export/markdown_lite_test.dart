import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/export/markdown_lite.dart';

void main() {
  group('parseInline', () {
    test('plain text with no markers is a single unstyled run', () {
      final runs = MarkdownLite.parseInline('hello world');
      expect(runs, hasLength(1));
      expect(runs.single.text, 'hello world');
      expect(runs.single.bold, isFalse);
      expect(runs.single.italic, isFalse);
      expect(runs.single.strikethrough, isFalse);
    });

    test('bold, italic, and strikethrough each parse correctly', () {
      expect(MarkdownLite.parseInline('**bold**').single, isA<Object>());
      final bold = MarkdownLite.parseInline('**bold**').single;
      expect(bold.text, 'bold');
      expect(bold.bold, isTrue);

      final italic = MarkdownLite.parseInline('*italic*').single;
      expect(italic.text, 'italic');
      expect(italic.italic, isTrue);

      final strike = MarkdownLite.parseInline('~~strike~~').single;
      expect(strike.text, 'strike');
      expect(strike.strikethrough, isTrue);
    });

    test('bold is not misparsed as two adjacent italics', () {
      final runs = MarkdownLite.parseInline('**bold**');
      expect(runs, hasLength(1));
      expect(runs.single.bold, isTrue);
      expect(runs.single.italic, isFalse);
    });

    test('mixed plain and styled text preserves order and surrounding text', () {
      final runs = MarkdownLite.parseInline('plain **bold** and *italic* end');
      expect(runs.map((r) => r.text), ['plain ', 'bold', ' and ', 'italic', ' end']);
      expect(runs[1].bold, isTrue);
      expect(runs[3].italic, isTrue);
    });

    test('unmatched delimiters are left as plain text', () {
      final runs = MarkdownLite.parseInline('a * b');
      expect(runs.single.text, 'a * b');
    });
  });

  group('parse (block-level)', () {
    test('blank-line-separated lines become separate paragraphs', () {
      final blocks = MarkdownLite.parse('First paragraph.\n\nSecond paragraph.');
      expect(blocks, hasLength(2));
      expect(blocks[0].type, MdBlockType.paragraph);
      expect(blocks[0].lines.single.single.text, 'First paragraph.');
      expect(blocks[1].lines.single.single.text, 'Second paragraph.');
    });

    test('consecutive non-blank lines stay as one paragraph with separate lines preserved', () {
      final blocks = MarkdownLite.parse('Line one.\nLine two.');
      expect(blocks, hasLength(1));
      expect(blocks[0].type, MdBlockType.paragraph);
      expect(blocks[0].lines, hasLength(2));
      expect(blocks[0].lines[0].single.text, 'Line one.');
      expect(blocks[0].lines[1].single.text, 'Line two.');
    });

    test('a heading line becomes its own block with the right level', () {
      final blocks = MarkdownLite.parse('## Chapter Title');
      expect(blocks.single.type, MdBlockType.heading);
      expect(blocks.single.headingLevel, 2);
      expect(blocks.single.lines.single.single.text, 'Chapter Title');
    });

    test('a lone *** line is a scene break with no content', () {
      final blocks = MarkdownLite.parse('Before.\n\n***\n\nAfter.');
      expect(blocks.map((b) => b.type),
          [MdBlockType.paragraph, MdBlockType.sceneBreak, MdBlockType.paragraph]);
      expect(blocks[1].lines, isEmpty);
    });

    test('consecutive quote lines become one quote block', () {
      final blocks = MarkdownLite.parse('> line one\n> line two');
      expect(blocks.single.type, MdBlockType.quote);
      expect(blocks.single.lines, hasLength(2));
      expect(blocks.single.lines[0].single.text, 'line one');
    });

    test('a quote is interrupted by a blank line', () {
      final blocks = MarkdownLite.parse('> quoted\n\nplain paragraph');
      expect(blocks.map((b) => b.type), [MdBlockType.quote, MdBlockType.paragraph]);
    });

    test('empty content produces no blocks', () {
      expect(MarkdownLite.parse(''), isEmpty);
    });

    test('heading text can itself contain inline styling', () {
      final blocks = MarkdownLite.parse('# The **Bold** Title');
      final runs = blocks.single.lines.single;
      expect(runs.map((r) => r.text), ['The ', 'Bold', ' Title']);
      expect(runs[1].bold, isTrue);
    });
  });
}
