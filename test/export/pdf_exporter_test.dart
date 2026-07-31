import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/export/pdf_exporter.dart';
import 'package:narraity/services/manuscript_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory projectDir;
  late ManuscriptService manuscriptService;
  late PdfExporter exporter;
  late Project project;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_pdf_export_test_');
    manuscriptService = ManuscriptService(projectDir);
    exporter = PdfExporter(projectDir);
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

  test('produces bytes that look like a real PDF (magic header + trailer)', () async {
    final bytes = await exporter.buildBytes(project, ManuscriptStructure());

    // PDF magic header.
    expect(ascii.decode(bytes.take(5).toList(), allowInvalid: true), '%PDF-');
    // Every valid PDF ends with an EOF marker somewhere near the tail.
    final tail = ascii.decode(bytes.skip((bytes.length - 32).clamp(0, bytes.length)).toList(),
        allowInvalid: true);
    expect(tail, contains('%%EOF'));
  });

  test('handles a manuscript exercising every block type without throwing', () async {
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
      backMatter: [SpecialSection(id: 'epilogue-1', type: SpecialSectionType.epilogue)],
    );
    await manuscriptService.writeScene(SceneDoc(
      id: 'prologue-1',
      title: 'Prologue',
      content: 'A **bold** start.\n\n> A quote here.\n\n***\n\nAfter break.',
    ));
    await manuscriptService.writeScene(SceneDoc(
      id: 'ch-1',
      title: 'Chapter 1',
      content: 'Chapter prose with *italic* and ~~strike~~.',
    ));
    await manuscriptService.writeScene(
      SceneDoc(id: 'sc-1', title: 'Scene 1', content: 'Scene prose.\nSecond line.'),
    );
    await manuscriptService.writeScene(
      SceneDoc(id: 'epilogue-1', title: 'Epilogue', content: 'The end.'),
    );

    final bytes = await exporter.buildBytes(project, structure);
    expect(bytes, isNotEmpty);
  });

  test('exportToFile writes a real, non-empty file to disk', () async {
    final outputPath = p.join(projectDir.path, 'out', 'novel.pdf');
    final file = await exporter.exportToFile(project, ManuscriptStructure(), outputPath);

    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(100));
  });

  test('showTitleInExport: false produces smaller output than with the heading shown', () async {
    // PDF content streams are binary/compressed, so we can't grep for the
    // heading text directly the way the other export formats' tests do —
    // a byte-size difference is the practical proxy that the heading
    // widgets were actually skipped, not just a no-throw smoke test.
    final shown = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'A Rather Long Chapter Heading', typeLabel: 'Chapter')],
    );
    final hidden = ManuscriptStructure(
      nodes: [
        ManuscriptNode(
          id: 'ch-1',
          title: 'A Rather Long Chapter Heading',
          typeLabel: 'Chapter',
          showTitleInExport: false,
        ),
      ],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Some prose.'));

    final shownBytes = await exporter.buildBytes(project, shown);
    final hiddenBytes = await exporter.buildBytes(project, hidden);

    expect(hiddenBytes.length, lessThan(shownBytes.length));
  });

  /// Counts physical PDF page objects via a raw-bytes scan. Content streams
  /// are FlateDecode-compressed, but page dictionaries themselves aren't, so
  /// `/Type /Page` (not `/Pages`, the page-tree root) is a reliable proxy
  /// for "how many pages did this actually produce" without needing a real
  /// PDF parser dependency.
  int pageCountOf(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    return RegExp(r'/Type\s*/Page(?!s)').allMatches(text).length;
  }

  test('top-level sections each start on a fresh page', () async {
    final structure = ManuscriptStructure(
      nodes: [
        ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter'),
        ManuscriptNode(id: 'ch-2', title: 'Chapter 2', typeLabel: 'Chapter'),
      ],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));
    await manuscriptService.writeScene(SceneDoc(id: 'ch-2', title: 'x', content: 'Short too.'));

    final bytes = await exporter.buildBytes(project, structure);

    // Title page + Chapter 1's own page + Chapter 2 forced onto a new page.
    expect(pageCountOf(bytes), 3);
  });

  test('a child section does NOT force a new page — only top-level ones do', () async {
    final structure = ManuscriptStructure(
      nodes: [
        ManuscriptNode(
          id: 'ch-1',
          title: 'Chapter 1',
          typeLabel: 'Chapter',
          children: [ManuscriptNode(id: 'sc-1', title: 'Scene 1', typeLabel: 'Scene')],
        ),
      ],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));
    await manuscriptService.writeScene(SceneDoc(id: 'sc-1', title: 'x', content: 'Short too.'));

    final bytes = await exporter.buildBytes(project, structure);

    // Title page + one page holding both Chapter 1 and its child Scene 1.
    expect(pageCountOf(bytes), 2);
  });

  test('front matter, then the first node, does not get a spurious blank page', () async {
    // The very first depth-0 section right after the title page must not
    // get an extra pw.NewPage() — the title page already ends on one, and
    // NewPage() with no freeSpace forces a break unconditionally, so a
    // second one back-to-back would insert a blank page.
    final structure = ManuscriptStructure(
      frontMatter: [SpecialSection(id: 'prologue-1', type: SpecialSectionType.prologue)],
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'prologue-1', title: 'x', content: 'Short.'));
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short too.'));

    final bytes = await exporter.buildBytes(project, structure);

    // Title page + prologue's page + Chapter 1 forced onto a new page —
    // NOT 4 (which would mean a blank page snuck in before the prologue).
    expect(pageCountOf(bytes), 3);
  });

  test('handles a chapter written as one long unbroken paragraph spanning many pages', () async {
    // Regression test: a whole chapter with no blank lines is a single
    // MarkdownLite paragraph block, i.e. one very tall pw.RichText. If it's
    // wrapped in pw.Padding (a SingleChildWidget, not a SpanningWidget),
    // MultiPage can't split it across pages and throws "Widget won't fit
    // into the page" for anything taller than one page.
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    final longParagraph = List.generate(400, (i) => 'Sentence number $i in a very long chapter.')
        .join(' ');
    await manuscriptService.writeScene(
      SceneDoc(id: 'ch-1', title: 'Chapter 1', content: longParagraph),
    );

    final bytes = await exporter.buildBytes(project, structure);
    expect(bytes, isNotEmpty);
  });
}
