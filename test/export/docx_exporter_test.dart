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
