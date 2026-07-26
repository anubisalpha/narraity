import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/export/epub_exporter.dart';
import 'package:narraity/services/manuscript_service.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

void main() {
  late Directory projectDir;
  late ManuscriptService manuscriptService;
  late EpubExporter exporter;
  late Project project;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_epub_export_test_');
    manuscriptService = ManuscriptService(projectDir);
    exporter = EpubExporter(projectDir);
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

  test('mimetype is the first entry and is stored uncompressed', () async {
    final bytes = await exporter.buildBytes(project, ManuscriptStructure());
    final archive = ZipDecoder().decodeBytes(bytes);

    expect(archive.files.first.name, 'mimetype');
    expect(archive.files.first.compression, CompressionType.none);
    expect(
      String.fromCharCodes(archive.files.first.content as List<int>),
      'application/epub+zip',
    );
  });

  test('contains the required EPUB structural parts', () async {
    final bytes = await exporter.buildBytes(project, ManuscriptStructure());
    final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toSet();

    expect(names, contains('META-INF/container.xml'));
    expect(names, contains('OEBPS/content.opf'));
    expect(names, contains('OEBPS/nav.xhtml'));
  });

  test('every XML/XHTML part is well-formed', () async {
    final structure = ManuscriptStructure(
      frontMatter: [SpecialSection(id: 'prologue-1', type: SpecialSectionType.prologue)],
      nodes: [
        ManuscriptNode(
          id: 'ch-1',
          title: 'Chapter 1',
          typeLabel: 'Chapter',
          children: [ManuscriptNode(id: 'sc-1', title: 'Scene 1', typeLabel: 'Scene')],
        ),
      ],
    );
    await manuscriptService.writeScene(SceneDoc(
      id: 'prologue-1',
      title: 'Prologue',
      content: 'A **bold** start with Tom & Jerry < 5 > 0.\n\n> A quote.\n\n***\n\nAfter.',
    ));
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'Chapter 1', content: '*Italic* text.'));
    await manuscriptService.writeScene(SceneDoc(id: 'sc-1', title: 'Scene 1', content: 'Plain.'));

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final entry in archive.files) {
      if (!entry.name.endsWith('.xml') && !entry.name.endsWith('.xhtml')) continue;
      final content = String.fromCharCodes(entry.content as List<int>);
      expect(
        () => XmlDocument.parse(content),
        returnsNormally,
        reason: '${entry.name} should be well-formed XML',
      );
    }
  });

  test('nav.xhtml lists every section title as a TOC entry', () async {
    final structure = ManuscriptStructure(nodes: [
      ManuscriptNode(id: 'ch-1', title: 'Chapter One', typeLabel: 'Chapter'),
      ManuscriptNode(id: 'ch-2', title: 'Chapter Two', typeLabel: 'Chapter'),
    ]);
    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);
    final nav = String.fromCharCodes(archive.findFile('OEBPS/nav.xhtml')!.content as List<int>);

    expect(nav, contains('Chapter One'));
    expect(nav, contains('Chapter Two'));
  });

  test('bold/italic/strikethrough map to strong/em/s tags', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(
      id: 'ch-1',
      title: 'Chapter 1',
      content: '**bold** *italic* ~~gone~~',
    ));

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);
    final section = String.fromCharCodes(archive.findFile('OEBPS/text/section-1.xhtml')!.content as List<int>);

    expect(section, contains('<strong>bold</strong>'));
    expect(section, contains('<em>italic</em>'));
    expect(section, contains('<s>gone</s>'));
  });

  test('exportToFile writes a real file to disk', () async {
    final outputPath = p.join(projectDir.path, 'out', 'novel.epub');
    final file = await exporter.exportToFile(project, ManuscriptStructure(), outputPath);

    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(0));
  });
}
