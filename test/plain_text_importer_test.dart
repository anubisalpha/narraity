import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/import/plain_text_importer.dart';

void main() {
  test('a single heading with body text becomes one chapter', () {
    final nodes = PlainTextImporter.parse('# Chapter One\n\nIt was a dark night.');

    expect(nodes, hasLength(1));
    expect(nodes.first.title, 'Chapter One');
    expect(nodes.first.typeLabel, 'Chapter');
    expect(nodes.first.content, contains('It was a dark night.'));
  });

  test('nested headings nest arbitrarily deep, not just chapter/scene', () {
    const text = '''
# Act One
## Chapter One
### Scene A
some prose
### Scene B
more prose
## Chapter Two
different prose
''';
    final nodes = PlainTextImporter.parse(text);

    expect(nodes, hasLength(1));
    final act = nodes.first;
    expect(act.title, 'Act One');
    expect(act.children, hasLength(2));

    final chapterOne = act.children[0];
    expect(chapterOne.title, 'Chapter One');
    expect(chapterOne.children, hasLength(2));
    expect(chapterOne.children[0].title, 'Scene A');
    expect(chapterOne.children[0].content, contains('some prose'));
    expect(chapterOne.children[1].title, 'Scene B');
    expect(chapterOne.children[1].content, contains('more prose'));

    final chapterTwo = act.children[1];
    expect(chapterTwo.title, 'Chapter Two');
    expect(chapterTwo.content, contains('different prose'));
    expect(chapterTwo.children, isEmpty);
  });

  test('a heading node can hold its own prose before a deeper subheading', () {
    const text = '''
# Chapter One
Opening paragraph directly under the chapter.
## Scene A
Scene prose.
''';
    final nodes = PlainTextImporter.parse(text);

    expect(nodes.first.content, contains('Opening paragraph directly under the chapter.'));
    expect(nodes.first.children.single.content, contains('Scene prose.'));
  });

  test('a scene break becomes a *** line inside the current node\'s content', () {
    const text = '''
# Chapter One
First scene text.
***
Second scene text.
''';
    final nodes = PlainTextImporter.parse(text);

    expect(nodes.first.content, contains('First scene text.\n***\nSecond scene text.'));
  });

  test('content before the first heading is kept, not dropped', () {
    final nodes = PlainTextImporter.parse('Some prose with no heading above it.');

    expect(nodes, hasLength(1));
    expect(nodes.first.title, 'Chapter 1');
    expect(nodes.first.content, contains('Some prose with no heading above it.'));
  });

  test('a document with no headings at all becomes a single chapter', () {
    final nodes = PlainTextImporter.parse('Line one.\nLine two.\nLine three.');

    expect(nodes, hasLength(1));
    expect(nodes.first.content, 'Line one.\nLine two.\nLine three.');
  });

  test('a same-depth heading after a deeper one closes the deeper one and starts a sibling', () {
    const text = '''
# Chapter One
## Scene A
scene a text
# Chapter Two
chapter two text
''';
    final nodes = PlainTextImporter.parse(text);

    expect(nodes, hasLength(2));
    expect(nodes[0].children.single.content, contains('scene a text'));
    expect(nodes[1].content, contains('chapter two text'));
    expect(nodes[1].children, isEmpty);
  });
}
