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

  test('scenes under a chapter share the chapter\'s file instead of getting their own', () async {
    // Regression test: every outline section used to get its own spine
    // file, so a Book > Chapter > Scene x5 structure produced dozens of
    // separate EPUB files — fragmenting continuous chapter prose into
    // reader-visible "page" jumps at every scene boundary even though no
    // scene heading was ever shown. Scenes (non-chapter-boundary sections)
    // now merge into the enclosing chapter's file.
    final structure = ManuscriptStructure(nodes: [
      ManuscriptNode(
        id: 'ch-1',
        title: 'Chapter One',
        typeLabel: 'Chapter',
        children: [
          ManuscriptNode(id: 'sc-1', title: 'Scene 1', typeLabel: 'Scene'),
          ManuscriptNode(id: 'sc-2', title: 'Scene 2', typeLabel: 'Scene'),
        ],
      ),
      ManuscriptNode(id: 'ch-2', title: 'Chapter Two', typeLabel: 'Chapter'),
    ]);
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Chapter prose.'));
    await manuscriptService.writeScene(SceneDoc(id: 'sc-1', title: 'x', content: 'Scene one prose.'));
    await manuscriptService.writeScene(SceneDoc(id: 'sc-2', title: 'x', content: 'Scene two prose.'));
    await manuscriptService.writeScene(SceneDoc(id: 'ch-2', title: 'x', content: 'Chapter two prose.'));

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);
    final textFiles = archive.files.where((f) => f.name.startsWith('OEBPS/text/')).toList();

    // One file for Chapter One (carrying both its scenes' prose) + one for
    // Chapter Two — not four.
    expect(textFiles, hasLength(2));
    final chapterOne = String.fromCharCodes(textFiles[0].content as List<int>);
    expect(chapterOne, contains('Chapter prose.'));
    expect(chapterOne, contains('Scene one prose.'));
    expect(chapterOne, contains('Scene two prose.'));

    final nav = String.fromCharCodes(archive.findFile('OEBPS/nav.xhtml')!.content as List<int>);
    expect(nav, contains('Chapter One'));
    expect(nav, isNot(contains('Scene 1')));
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

  test('ships a stylesheet linked from every xhtml file, matching a real e-reader export\'s '
      'convention (previously no CSS at all — bare <p> tags relied on the reader\'s defaults)',
      () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Some prose.'));

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);

    expect(archive.findFile('OEBPS/styles.css'), isNotNull);
    final opf = String.fromCharCodes(archive.findFile('OEBPS/content.opf')!.content as List<int>);
    expect(opf, contains('href="styles.css"'));

    final section = String.fromCharCodes(archive.findFile('OEBPS/text/section-1.xhtml')!.content as List<int>);
    expect(section, contains('<link href="../styles.css" rel="stylesheet" type="text/css"/>'));

    final nav = String.fromCharCodes(archive.findFile('OEBPS/nav.xhtml')!.content as List<int>);
    expect(nav, contains('<link href="styles.css" rel="stylesheet" type="text/css"/>'));
  });

  test('a scene break renders as visible "* * *" text, not a bare invisible <hr/>', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(
      SceneDoc(id: 'ch-1', title: 'x', content: 'Before.\n\n***\n\nAfter.'),
    );

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);
    final section = String.fromCharCodes(archive.findFile('OEBPS/text/section-1.xhtml')!.content as List<int>);

    expect(section, contains('<p class="scenebreak">* * *</p>'));
    expect(section, isNot(contains('<hr')));
  });

  test('the first paragraph of a chapter has no first-line indent; later ones do — '
      'matches traditional book typesetting (and the reference Kindle Create export)', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(
      SceneDoc(id: 'ch-1', title: 'x', content: 'First paragraph.\n\nSecond paragraph.'),
    );

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);
    final section = String.fromCharCodes(archive.findFile('OEBPS/text/section-1.xhtml')!.content as List<int>);

    expect(section, contains('<p class="noindent">First paragraph.</p>'));
    expect(section, contains('<p>Second paragraph.</p>'));
  });

  test('showTitleInExport: false omits the <h1> but keeps <head><title> and the TOC entry', () async {
    final structure = ManuscriptStructure(
      nodes: [
        ManuscriptNode(
            id: 'ch-1', title: 'Hidden Scene', typeLabel: 'Scene', showTitleInExport: false),
      ],
    );
    await manuscriptService.writeScene(
      SceneDoc(id: 'ch-1', title: 'Hidden Scene', content: 'Prose here.'),
    );

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);
    final section =
        String.fromCharCodes(archive.findFile('OEBPS/text/section-1.xhtml')!.content as List<int>);
    final nav = String.fromCharCodes(archive.findFile('OEBPS/nav.xhtml')!.content as List<int>);

    expect(section, isNot(contains('<h1>Hidden Scene</h1>')));
    expect(section, contains('<title>Hidden Scene</title>'));
    expect(section, contains('Prose here.'));
    // The TOC still lists it — [showTitle] only governs the in-page heading.
    expect(nav, contains('Hidden Scene'));
  });

  test('exportToFile writes a real file to disk', () async {
    final outputPath = p.join(projectDir.path, 'out', 'novel.epub');
    final file = await exporter.exportToFile(project, ManuscriptStructure(), outputPath);

    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(0));
  });
}
