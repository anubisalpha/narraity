import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/mention_scanner.dart';

void main() {
  group('extractMentions', () {
    test('finds a simple mention', () {
      expect(extractMentions('She saw [[Elena Vance]] at the gate.'), ['Elena Vance']);
    });

    test('finds several mentions in order', () {
      expect(
        extractMentions('[[Elena]] rode to [[Ashfall Keep]] with [[Mikhail]].'),
        ['Elena', 'Ashfall Keep', 'Mikhail'],
      );
    });

    test('de-duplicates case-insensitively, keeping the first casing', () {
      expect(
        extractMentions('[[Elena]] and later [[elena]] and [[ELENA]].'),
        ['Elena'],
      );
    });

    test('trims whitespace inside the brackets', () {
      expect(extractMentions('[[  Elena Vance ]]'), ['Elena Vance']);
    });

    test('ignores empty, nested, and multi-line brackets', () {
      expect(extractMentions('[[]] [[ ]] [[a\nb]]'), isEmpty);
      expect(extractMentions('[[outer [[inner]] more]]'), ['inner']);
    });

    test('plain text has no mentions', () {
      expect(extractMentions('No brackets here, [single] does not count.'), isEmpty);
    });
  });

  group('mentionQueryAt', () {
    test('detects a query right after @', () {
      const text = 'She saw @Ele';
      final query = mentionQueryAt(text, text.length);
      expect(query, isNotNull);
      expect(query!.query, 'Ele');
      expect(query.start, 8);
    });

    test('a bare @ starts an empty query', () {
      const text = 'Hello @';
      expect(mentionQueryAt(text, text.length)!.query, '');
    });

    test('@ at the start of the text works', () {
      expect(mentionQueryAt('@El', 3)!.query, 'El');
    });

    test('an email address does not trigger', () {
      const text = 'write to elena@example.com';
      expect(mentionQueryAt(text, text.length), isNull);
    });

    test('a query cannot span a newline', () {
      const text = 'saw @Ele\nna';
      expect(mentionQueryAt(text, text.length), isNull);
    });

    test('an already-completed mention does not keep triggering', () {
      const text = 'saw @[[Elena]]';
      expect(mentionQueryAt(text, text.length), isNull);
    });

    test('overly long queries stop triggering', () {
      final text = 'saw @${'x' * 41}';
      expect(mentionQueryAt(text, text.length), isNull);
    });

    test('caret in the middle of the text uses only what precedes it', () {
      const text = 'saw @Ele and more prose';
      final query = mentionQueryAt(text, 8);
      expect(query!.query, 'Ele');
    });
  });
}
