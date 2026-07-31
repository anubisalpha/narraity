import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/export/docx_exporter.dart';
import 'package:narraity/services/manuscript_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory projectDir;
  late ManuscriptService manuscriptService;
  late DocxExporter exporter;
  late Project project;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_docx_export_test_');
    manuscriptService = ManuscriptService(projectDir);
    exporter = DocxExporter(projectDir);
    project = Project(
      id: 'p1',
      folderName: 'My Novel',
      title: 'My Novel',
      subtitle: 'A Subtitle',
      author: 'Jane Author',
      created: DateTime.utc(2026),
      modified: DateTime.utc(2026),
    );
  });

  tearDown(() {
    projectDir.deleteSync(recursive: true);
  });

  /// Unzips the produced bytes and returns word/document.xml as a string —
  /// the real content worth asserting on, without needing Word itself.
  Future<String> documentXmlOf(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('word/document.xml');
    expect(entry, isNotNull, reason: 'word/document.xml must exist in the package');
    return String.fromCharCodes(entry!.content as List<int>);
  }

  test('produces a valid zip with the required OOXML parts', () async {
    final bytes = await exporter.buildBytes(project, ManuscriptStructure());
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();

    expect(names, contains('[Content_Types].xml'));
    expect(names, contains('_rels/.rels'));
    expect(names, contains('word/document.xml'));
  });

  test('title page includes title, subtitle, and author', () async {
    final xml = await documentXmlOf(await exporter.buildBytes(project, ManuscriptStructure()));
    expect(xml, contains('My Novel'));
    expect(xml, contains('A Subtitle'));
    expect(xml, contains('by Jane Author'));
  });

  test('bold/italic/strikethrough become the matching OOXML run properties', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(
      id: 'ch-1',
      title: 'Chapter 1',
      content: 'Some **bold** and *italic* and ~~gone~~ text.',
    ));

    final xml = await documentXmlOf(await exporter.buildBytes(project, structure));

    expect(xml, contains('<w:b/>'));
    expect(xml, contains('<w:i/>'));
    expect(xml, contains('<w:strike/>'));
    expect(xml, contains('bold'));
    expect(xml, contains('italic'));
    expect(xml, contains('gone'));
  });

  test('a Book > Chapter > Scene structure breaks pages between chapters, not just once', () async {
    // Regression test: a single top-level "Book" node wrapping many
    // "Chapter" children (all at depth 1) used to get exactly one page
    // break (after the title page) and none between chapters, because the
    // old rule only checked depth == 0. Chapter-like typeLabels now force a
    // break regardless of depth.
    final structure = ManuscriptStructure(nodes: [
      ManuscriptNode(id: 'book-1', title: 'Book 1', typeLabel: 'Book', children: [
        ManuscriptNode(
          id: 'ch-1',
          title: 'Chapter 1',
          typeLabel: 'Chapter',
          children: [ManuscriptNode(id: 'sc-1', title: 'Scene 1', typeLabel: 'Scene')],
        ),
        ManuscriptNode(id: 'ch-2', title: 'Chapter 2', typeLabel: 'Chapter'),
      ]),
    ]);
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'First.'));
    await manuscriptService.writeScene(SceneDoc(id: 'sc-1', title: 'x', content: 'Scene prose.'));
    await manuscriptService.writeScene(SceneDoc(id: 'ch-2', title: 'x', content: 'Second.'));

    final xml = await documentXmlOf(await exporter.buildBytes(project, structure));

    // Title page's own break + Chapter 1 + Chapter 2 = 3 total. Book itself
    // is the very first section overall, so it doesn't add a redundant
    // break right after the title page's; Scene 1 (depth 2, typeLabel
    // "Scene") must NOT add a 4th either.
    expect('w:type="page"'.allMatches(xml).length, 3);
  });

  test('showTitleInExport: false omits that section\'s heading', () async {
    final structure = ManuscriptStructure(nodes: [
      ManuscriptNode(id: 'ch-1', title: 'Chapter One', typeLabel: 'Chapter'),
      ManuscriptNode(
          id: 'sc-1', title: 'Hidden Scene', typeLabel: 'Scene', showTitleInExport: false),
    ]);
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'Chapter One', content: 'First.'));
    await manuscriptService.writeScene(SceneDoc(id: 'sc-1', title: 'Hidden Scene', content: 'Second.'));

    final xml = await documentXmlOf(await exporter.buildBytes(project, structure));

    expect(xml, contains('Chapter One'));
    expect(xml, isNot(contains('Hidden Scene')));
    expect(xml, contains('Second.'));
  });

  test('XML special characters in prose are escaped', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(
      SceneDoc(id: 'ch-1', title: 'Chapter 1', content: 'Tom & Jerry said "1 < 2 > 0".'),
    );

    final xml = await documentXmlOf(await exporter.buildBytes(project, structure));

    expect(xml, contains('Tom &amp; Jerry'));
    expect(xml, isNot(contains('1 < 2 > 0')));
  });

  test('deeper section nesting gets a smaller heading size', () async {
    final structure = ManuscriptStructure(nodes: [
      ManuscriptNode(
        id: 'ch-1',
        title: 'Chapter 1',
        typeLabel: 'Chapter',
        children: [ManuscriptNode(id: 'sc-1', title: 'Scene 1', typeLabel: 'Scene')],
      ),
    ]);
    final xml = await documentXmlOf(await exporter.buildBytes(project, structure));

    // depth 0 -> 32 half-points, depth 1 -> 28 -- just assert both appear,
    // proving the sizes actually differ by depth rather than being fixed.
    expect(xml, contains('w:sz w:val="32"'));
    expect(xml, contains('w:sz w:val="28"'));
  });

  test('exportToFile writes a real file to disk', () async {
    final outputPath = p.join(projectDir.path, 'out', 'novel.docx');
    final file = await exporter.exportToFile(project, ManuscriptStructure(), outputPath);

    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(0));
  });
}
