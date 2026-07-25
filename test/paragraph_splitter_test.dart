import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/paragraph_splitter.dart';

void main() {
  test('splits on blank-line-separated paragraphs with correct offsets', () {
    const content = 'First paragraph.\n\nSecond paragraph.';
    final paragraphs = splitParagraphs(content);

    expect(paragraphs, hasLength(2));
    expect(paragraphs[0].index, 0);
    expect(content.substring(paragraphs[0].start, paragraphs[0].end), 'First paragraph.');
    expect(paragraphs[1].index, 1);
    expect(content.substring(paragraphs[1].start, paragraphs[1].end), 'Second paragraph.');
  });

  test('a multi-line paragraph (no blank line inside) stays one paragraph', () {
    const content = 'Line one\nline two\nline three.';
    final paragraphs = splitParagraphs(content);

    expect(paragraphs, hasLength(1));
    expect(paragraphs.single.text, content);
  });

  test('collapses multiple consecutive blank lines into one separator', () {
    const content = 'First.\n\n\n\nSecond.';
    final paragraphs = splitParagraphs(content);

    expect(paragraphs.map((p) => p.text), ['First.', 'Second.']);
  });

  test('empty content has no paragraphs', () {
    expect(splitParagraphs(''), isEmpty);
  });

  test('whitespace-only content has no paragraphs', () {
    expect(splitParagraphs('   \n\n   \n'), isEmpty);
  });

  test('offsets round-trip: substring at (start,end) always equals text', () {
    const content = 'Alpha.\n\nBeta line one\nBeta line two.\n\n\nGamma.';
    for (final paragraph in splitParagraphs(content)) {
      expect(content.substring(paragraph.start, paragraph.end), paragraph.text);
    }
  });
}
