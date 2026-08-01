import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/annotation.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/annotation_service.dart';
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

  test('nav.xhtml nests chapter-boundary groups two levels deep for a Book > Act > Chapter tree, '
      'capping at Kindle\'s 2-level limit rather than mirroring the full tree depth', () async {
    // Book > Act > Chapter is 3 levels of chapter-boundary groups (Book,
    // Act, and Chapter are all "chapter-like" labels per
    // ManuscriptOutlineBuilder), but Kindle only supports 2 levels of nav
    // nesting — the third level must fold into the second, not nest further.
    final structure = ManuscriptStructure(nodes: [
      ManuscriptNode(
        id: 'act-1',
        title: 'Act One',
        typeLabel: 'Act',
        children: [
          ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter'),
          ManuscriptNode(id: 'ch-2', title: 'Chapter 2', typeLabel: 'Chapter'),
        ],
      ),
      ManuscriptNode(
        id: 'act-2',
        title: 'Act Two',
        typeLabel: 'Act',
        children: [ManuscriptNode(id: 'ch-3', title: 'Chapter 3', typeLabel: 'Chapter')],
      ),
    ]);
    for (final id in ['act-1', 'ch-1', 'ch-2', 'act-2', 'ch-3']) {
      await manuscriptService.writeScene(SceneDoc(id: id, title: 'x', content: 'Prose.'));
    }

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);
    final nav = String.fromCharCodes(archive.findFile('OEBPS/nav.xhtml')!.content as List<int>);

    // Well-formed XML confirms the <ol>/<li> nesting balances correctly.
    expect(() => XmlDocument.parse(nav), returnsNormally);

    final doc = XmlDocument.parse(nav);
    final topOl = doc.findAllElements('ol').first;
    final topLis = topOl.childElements.where((e) => e.name.local == 'li').toList();
    expect(topLis, hasLength(2)); // Act One, Act Two — not 5 flat entries

    final actOneChildren = topLis[0].findElements('ol').single.findAllElements('li');
    expect(actOneChildren.map((e) => e.innerText), ['Chapter 1', 'Chapter 2']);

    final actTwoChildren = topLis[1].findElements('ol').single.findAllElements('li');
    expect(actTwoChildren.map((e) => e.innerText), ['Chapter 3']);

    // No third level anywhere, however deep the source tree nominally goes.
    expect(nav.split('<ol>').length - 1, 3); // outer + 2 nested, never more
  });

  test('a flat chapter-only book (no Act grouping) still produces a plain flat list, matching '
      'prior behavior', () async {
    final structure = ManuscriptStructure(nodes: [
      ManuscriptNode(id: 'ch-1', title: 'Chapter One', typeLabel: 'Chapter'),
      ManuscriptNode(id: 'ch-2', title: 'Chapter Two', typeLabel: 'Chapter'),
    ]);
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Prose.'));
    await manuscriptService.writeScene(SceneDoc(id: 'ch-2', title: 'x', content: 'Prose.'));

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);
    final nav = String.fromCharCodes(archive.findFile('OEBPS/nav.xhtml')!.content as List<int>);

    final doc = XmlDocument.parse(nav);
    final topOl = doc.findAllElements('ol').first;
    expect(topOl.findElements('ol'), isEmpty); // no nested <ol> at all
    expect(topOl.childElements.where((e) => e.name.local == 'li'), hasLength(2));
  });

  test('throws EpubExportException when a single section exceeds the configured byte limit',
      () async {
    // A tiny injected limit + ordinary content, rather than building a
    // real ~30MB string — keeps the test fast and still exercises the same
    // check `maxFileBytes` defaults to KDP's real 30MB limit for.
    final smallLimitExporter = EpubExporter(projectDir, maxFileBytes: 50);
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(
      id: 'ch-1',
      title: 'x',
      content: 'This paragraph alone is longer than fifty bytes of encoded XHTML.',
    ));

    expect(
      () => smallLimitExporter.buildBytes(project, structure),
      throwsA(isA<EpubExportException>()),
    );
  });

  test('throws EpubExportException when the section count exceeds the configured file-count limit',
      () async {
    final smallLimitExporter = EpubExporter(projectDir, maxFileCount: 2);
    final nodes = List.generate(
      3,
      (i) => ManuscriptNode(id: 'ch-$i', title: 'Chapter $i', typeLabel: 'Chapter'),
    );
    final structure = ManuscriptStructure(nodes: nodes);
    for (final node in nodes) {
      await manuscriptService.writeScene(SceneDoc(id: node.id, title: 'x', content: 'Prose.'));
    }

    // 3 chapter sections + nav.xhtml = 4 files, over the injected limit of 2.
    expect(
      () => smallLimitExporter.buildBytes(project, structure),
      throwsA(isA<EpubExportException>()),
    );
  });

  test('the real KDP limits (30MB/300 files) are the defaults when not overridden', () {
    expect(EpubExporter(projectDir).maxFileBytes, kEpubMaxFileBytes);
    expect(EpubExporter(projectDir).maxFileCount, kEpubMaxFileCount);
  });

  group('footnotes', () {
    test('a footnote annotation renders as a noteref + aside, KDP\'s recommended structure',
        () async {
      final structure = ManuscriptStructure(
        nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
      );
      const content = 'A word needs explaining.';
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: content));

      final annotations = AnnotationService(projectDir);
      await annotations.create(
        sceneId: 'ch-1',
        kind: AnnotationKind.footnote,
        anchor: const TextAnchor(start: 6, end: 6, quotedText: ''), // point anchor after "A word"
        body: 'An explanatory note.',
      );

      final bytes = await exporter.buildBytes(project, structure);
      final archive = ZipDecoder().decodeBytes(bytes);
      final section =
          String.fromCharCodes(archive.findFile('OEBPS/text/section-1.xhtml')!.content as List<int>);

      expect(() => XmlDocument.parse(section), returnsNormally);
      expect(
        section,
        contains(
          '<a id="src-1" href="#fn-1" epub:type="noteref" class="footnote-ref">1</a>',
        ),
      );
      expect(
        section,
        contains('<aside id="fn-1" epub:type="footnote">'
            '<p><a href="#src-1" epub:type="noteref">1.</a> An explanatory note.</p></aside>'),
      );
      // epub:type is used in the body, so the namespace must be declared.
      expect(section, contains('xmlns:epub="http://www.idpf.org/2007/ops"'));
    });

    test('multiple footnotes in one scene are numbered in reading order, not insertion order',
        () async {
      final structure = ManuscriptStructure(
        nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
      );
      const content = 'First point. Second point.';
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: content));

      final annotations = AnnotationService(projectDir);
      // Created out of document order deliberately — the second (later)
      // footnote is created first, to prove numbering follows position in
      // the text, not creation order.
      await annotations.create(
        sceneId: 'ch-1',
        kind: AnnotationKind.footnote,
        anchor: const TextAnchor(start: 26, end: 26, quotedText: ''), // after "Second point."
        body: 'Note on second point.',
      );
      await annotations.create(
        sceneId: 'ch-1',
        kind: AnnotationKind.footnote,
        anchor: const TextAnchor(start: 11, end: 11, quotedText: ''), // after "First point."
        body: 'Note on first point.',
      );

      final bytes = await exporter.buildBytes(project, structure);
      final archive = ZipDecoder().decodeBytes(bytes);
      final section =
          String.fromCharCodes(archive.findFile('OEBPS/text/section-1.xhtml')!.content as List<int>);

      final firstNoteIndex = section.indexOf('id="src-1"');
      final secondNoteIndex = section.indexOf('id="src-2"');
      expect(firstNoteIndex, greaterThan(0));
      expect(secondNoteIndex, greaterThan(firstNoteIndex));
      expect(section, contains('id="fn-1"'));
      expect(section, contains('Note on first point.'));
      expect(section, contains('id="fn-2"'));
      expect(section, contains('Note on second point.'));
    });

    test('a footnote\'s aside is placed in the same file its reference appears in', () async {
      final structure = ManuscriptStructure(nodes: [
        ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter'),
        ManuscriptNode(id: 'ch-2', title: 'Chapter 2', typeLabel: 'Chapter'),
      ]);
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Note here.'));
      await manuscriptService.writeScene(SceneDoc(id: 'ch-2', title: 'x', content: 'No notes here.'));

      final annotations = AnnotationService(projectDir);
      await annotations.create(
        sceneId: 'ch-1',
        kind: AnnotationKind.footnote,
        anchor: const TextAnchor(start: 4, end: 4, quotedText: ''),
        body: 'A note.',
      );

      final bytes = await exporter.buildBytes(project, structure);
      final archive = ZipDecoder().decodeBytes(bytes);
      final chapterOne =
          String.fromCharCodes(archive.findFile('OEBPS/text/section-1.xhtml')!.content as List<int>);
      final chapterTwo =
          String.fromCharCodes(archive.findFile('OEBPS/text/section-2.xhtml')!.content as List<int>);

      expect(chapterOne, contains('epub:type="footnote"'));
      expect(chapterTwo, isNot(contains('epub:type="footnote"')));
    });

    test('a scene with no footnotes renders no aside and no stray marker characters', () async {
      final structure = ManuscriptStructure(
        nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
      );
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Plain prose.'));

      final bytes = await exporter.buildBytes(project, structure);
      final archive = ZipDecoder().decodeBytes(bytes);
      final section =
          String.fromCharCodes(archive.findFile('OEBPS/text/section-1.xhtml')!.content as List<int>);

      expect(section, isNot(contains('epub:type="noteref"')));
      expect(section, isNot(contains('epub:type="footnote"')));
      expect(section, isNot(contains(String.fromCharCode(0xE000))));
    });
  });

  test('xhtml documents declare the primary language, per KDP accessibility guidance', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Prose.'));

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);
    final section =
        String.fromCharCodes(archive.findFile('OEBPS/text/section-1.xhtml')!.content as List<int>);
    final nav = String.fromCharCodes(archive.findFile('OEBPS/nav.xhtml')!.content as List<int>);

    expect(section, contains('xml:lang="en"'));
    expect(nav, contains('xml:lang="en"'));
  });

  test('exportToFile writes a real file to disk', () async {
    final outputPath = p.join(projectDir.path, 'out', 'novel.epub');
    final file = await exporter.exportToFile(project, ManuscriptStructure(), outputPath);

    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(0));
  });
}
