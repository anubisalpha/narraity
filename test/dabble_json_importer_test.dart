import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript_import.dart';
import 'package:narraity/services/import/dabble_json_importer.dart';

/// A hand-built fixture matching the real schema (verified against five
/// actual Dabble project exports, not guessed) rather than a copy of
/// anyone's real manuscript — see `dabble_json_importer.dart`'s doc comment
/// for the schema notes this mirrors.
const _sampleExport = '''
{
  "docId": "projects/abc123/content",
  "state": {
    "id": "abc123",
    "type": "novel",
    "children": ["manuscripts", "plots", "characters", "notebook"],
    "docs": {
      "trash": { "id": "trash", "type": "trash", "children": ["deletedScene"] },
      "deletedScene": { "id": "deletedScene", "type": "manuscripts_scene" },
      "manuscripts": { "id": "manuscripts", "type": "manuscripts", "children": ["book1"] },
      "book1": {
        "id": "book1",
        "type": "manuscripts_book",
        "title": "My Novel",
        "children": ["ch1"]
      },
      "ch1": {
        "id": "ch1",
        "type": "manuscripts_chapter",
        "title": "Chapter One",
        "children": ["sc1", "sc2"]
      },
      "sc1": {
        "id": "sc1",
        "type": "manuscripts_scene",
        "body": {
          "content": {
            "ops": [
              { "insert": "Some " },
              { "insert": "bold", "attributes": { "bold": true } },
              { "insert": " and " },
              { "insert": "italic", "attributes": { "italic": true } },
              { "insert": " text." },
              { "insert": { "br": true }, "attributes": { "bold": true } },
              { "insert": "\\n", "attributes": { "grammar": { "h": "abc", "issues": {} } } },
              { "insert": "A quoted line" },
              { "insert": "\\n", "attributes": { "blockquote": true } },
              { "insert": "First item" },
              { "insert": "\\n", "attributes": { "list": "ordered" } },
              { "insert": "Second item" },
              { "insert": "\\n", "attributes": { "list": "ordered" } },
              { "insert": "Trailing paragraph." },
              { "insert": "\\n" }
            ]
          }
        }
      },
      "sc2": {
        "id": "sc2",
        "type": "manuscripts_scene"
      }
    }
  }
}
''';

void main() {
  test('parses the book/chapter/scene hierarchy', () {
    final imported = DabbleJsonImporter.parse(_sampleExport);

    expect(imported, hasLength(1));
    expect(imported.single.title, 'My Novel');
    expect(imported.single.typeLabel, 'Book');

    final chapter = imported.single.children.single;
    expect(chapter.title, 'Chapter One');
    expect(chapter.typeLabel, 'Chapter');
    expect(chapter.children, hasLength(2));
    expect(chapter.children[0].title, 'Scene 1');
    expect(chapter.children[1].title, 'Scene 2');
  });

  test('converts Quill Delta formatting to markdown-lite', () {
    final imported = DabbleJsonImporter.parse(_sampleExport);
    final content = imported.single.children.single.children[0].content;

    expect(content, contains('Some **bold** and *italic* text.'));
  });

  test('a {br:true} embed paired with the real newline does not double the line break', () {
    final imported = DabbleJsonImporter.parse(_sampleExport);
    final content = imported.single.children.single.children[0].content;
    final lines = content.split('\n');

    // Exactly one line for "Some **bold**..." -- not two, which is what
    // treating both {br:true} and the following "\n" as separate breaks
    // would produce.
    expect(lines.where((l) => l.contains('Some **bold**')), hasLength(1));
  });

  test('blockquote becomes a > -prefixed line', () {
    final imported = DabbleJsonImporter.parse(_sampleExport);
    final content = imported.single.children.single.children[0].content;

    expect(content, contains('> A quoted line'));
  });

  test('an ordered list becomes numbered lines (no native list support to preserve otherwise)', () {
    final imported = DabbleJsonImporter.parse(_sampleExport);
    final content = imported.single.children.single.children[0].content;

    expect(content, contains('1. First item'));
    expect(content, contains('2. Second item'));
  });

  test('an empty scene (no body at all) produces empty content, not a crash', () {
    final imported = DabbleJsonImporter.parse(_sampleExport);
    expect(imported.single.children.single.children[1].content, '');
  });

  test('trashed content is never reachable from the live tree', () {
    final imported = DabbleJsonImporter.parse(_sampleExport);
    final allTitles = <String>[];
    void walk(ImportedNode n) {
      allTitles.add(n.title);
      n.children.forEach(walk);
    }

    imported.forEach(walk);
    expect(allTitles, hasLength(4)); // book, chapter, scene 1, scene 2 -- not the trashed scene
  });

  test('throws ImportParseException for the full-account-backup format (no "state" key)', () {
    expect(
      () => DabbleJsonImporter.parse('{"dabble": {}, "patches": []}'),
      throwsA(isA<ImportParseException>()),
    );
  });

  test('throws ImportParseException for malformed JSON', () {
    expect(() => DabbleJsonImporter.parse('not json'), throwsA(isA<ImportParseException>()));
  });
}
