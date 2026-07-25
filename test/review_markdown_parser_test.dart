import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/review_markdown_parser.dart';

void main() {
  group('parseReviewMarkdown', () {
    test('parses a single scene with two anchored paragraphs', () {
      const markdown = '''
## The Doorway

<!-- id: scene-1-p001 -->
Elena stepped through.

<!-- id: scene-1-p002 -->
She hesitated.
''';

      final paragraphs = parseReviewMarkdown(markdown);

      expect(paragraphs, hasLength(2));
      expect(paragraphs[0].anchorId, 'scene-1-p001');
      expect(paragraphs[0].sceneTitle, 'The Doorway');
      expect(paragraphs[0].text, 'Elena stepped through.');
      expect(paragraphs[1].anchorId, 'scene-1-p002');
      expect(paragraphs[1].text, 'She hesitated.');
    });

    test('attributes paragraphs to the scene heading above them', () {
      const markdown = '''
## One

<!-- id: scene-1-p001 -->
First scene text.

## Two

<!-- id: scene-2-p001 -->
Second scene text.
''';

      final paragraphs = parseReviewMarkdown(markdown);

      expect(paragraphs, hasLength(2));
      expect(paragraphs[0].sceneTitle, 'One');
      expect(paragraphs[1].sceneTitle, 'Two');
    });

    test('a multi-line paragraph is joined back with newlines', () {
      const markdown = '''
## One

<!-- id: scene-1-p001 -->
Line one
line two.
''';

      final paragraphs = parseReviewMarkdown(markdown);

      expect(paragraphs.single.text, 'Line one\nline two.');
    });

    test('ignores content before the first anchor id', () {
      const markdown = '''
Some preamble that is not part of any anchored paragraph.

## One

<!-- id: scene-1-p001 -->
Real paragraph.
''';

      final paragraphs = parseReviewMarkdown(markdown);

      expect(paragraphs, hasLength(1));
      expect(paragraphs.single.text, 'Real paragraph.');
    });

    test('an id marker immediately followed by another marker yields no paragraph', () {
      const markdown = '''
## One

<!-- id: scene-1-p001 -->
<!-- id: scene-1-p002 -->
Only this counts.
''';

      final paragraphs = parseReviewMarkdown(markdown);

      expect(paragraphs, hasLength(1));
      expect(paragraphs.single.anchorId, 'scene-1-p002');
    });

    test('empty markdown has no paragraphs', () {
      expect(parseReviewMarkdown(''), isEmpty);
    });

    test('a metadata comment line is never mistaken for a paragraph or heading', () {
      const markdown = '''
# My Novel
**Author:** Marc Saunders

<!-- narraity-review-export {"projectTitle":"My Novel","exportedAt":"2026-07-25T10:00:00.000Z"} -->

## Chapter 1

<!-- id: scene-1-p001 -->
Real paragraph.
''';

      final paragraphs = parseReviewMarkdown(markdown);

      expect(paragraphs, hasLength(1));
      expect(paragraphs.single.text, 'Real paragraph.');
      expect(paragraphs.single.sceneTitle, 'Chapter 1');
    });
  });

  group('parseReviewMetadata', () {
    test('reads project title, subtitle, author, and export timestamp back out', () {
      const markdown = '''
# My Novel
*A Tale*
**Author:** Marc Saunders
**Exported:** 2026-07-25T10:00:00.000Z

<!-- narraity-review-export {"projectTitle":"My Novel","subtitle":"A Tale","author":"Marc Saunders","exportedAt":"2026-07-25T10:00:00.000Z"} -->

## Chapter 1
''';

      final metadata = parseReviewMetadata(markdown);

      expect(metadata, isNotNull);
      expect(metadata!.projectTitle, 'My Novel');
      expect(metadata.subtitle, 'A Tale');
      expect(metadata.author, 'Marc Saunders');
      expect(metadata.exportedAt, DateTime.parse('2026-07-25T10:00:00.000Z'));
    });

    test('returns null when the file has no metadata comment', () {
      const markdown = '''
## Chapter 1

<!-- id: scene-1-p001 -->
Some prose.
''';

      expect(parseReviewMetadata(markdown), isNull);
    });

    test('returns null rather than throwing on a malformed metadata comment', () {
      const markdown = '<!-- narraity-review-export not valid json -->\n\n## One\n';
      expect(parseReviewMetadata(markdown), isNull);
    });
  });

  group('encodeReviewComments', () {
    test('round-trips through the exact JSON shape importComments expects', () {
      final json = encodeReviewComments([
        const ReviewComment(anchorId: 'scene-1-p001', text: 'Nice line.', category: 'prose'),
        const ReviewComment(anchorId: 'scene-1-p002', text: 'No category here.'),
      ]);

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final comments = decoded['comments'] as List<dynamic>;
      expect(comments, hasLength(2));
      expect(comments[0], {
        'anchorId': 'scene-1-p001',
        'text': 'Nice line.',
        'category': 'prose',
      });
      expect(comments[1], {'anchorId': 'scene-1-p002', 'text': 'No category here.'});
    });

    test('an empty or whitespace-only category is omitted, not written blank', () {
      final json = encodeReviewComments([
        const ReviewComment(anchorId: 'scene-1-p001', text: 'Text', category: '   '),
      ]);

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final comment = (decoded['comments'] as List<dynamic>).single as Map<String, dynamic>;
      expect(comment.containsKey('category'), isFalse);
    });

    test('no comments still encodes a valid (empty) comments array', () {
      final json = encodeReviewComments([]);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['comments'], isEmpty);
    });
  });
}
