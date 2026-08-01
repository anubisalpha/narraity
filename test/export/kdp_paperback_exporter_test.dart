import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/export/kdp_paperback_exporter.dart';
import 'package:narraity/services/manuscript_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory projectDir;
  late ManuscriptService manuscriptService;
  late KdpPaperbackExporter exporter;
  late Project project;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_kdp_paperback_test_');
    manuscriptService = ManuscriptService(projectDir);
    // Small injected page-count range so tests can hit the boundary with a
    // realistic, fast-to-parse manuscript rather than a genuinely 24- or
    // 828-page one.
    exporter = KdpPaperbackExporter(projectDir, minPageCount: 1, maxPageCount: 50);
    project = Project(
      id: 'p1',
      folderName: 'My Novel',
      title: 'My Novel',
      author: 'Jane Author',
      created: DateTime.utc(2026),
      modified: DateTime.utc(2026),
    );
  });

  tearDown(() => projectDir.deleteSync(recursive: true));

  /// Counts physical PDF page objects via a raw-bytes scan — same proxy
  /// `pdf_exporter_test.dart` uses, since content streams are compressed but
  /// page dictionaries aren't.
  int pageCountOf(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    return RegExp(r'/Type\s*/Page(?!s)').allMatches(text).length;
  }

  /// Extracts every `/MediaBox [x0 y0 x1 y1]` from the raw PDF bytes (one
  /// per page object) — gives the actual page dimensions in points (1/72in)
  /// without needing a real PDF parser dependency.
  List<(double width, double height)> mediaBoxesOf(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    return RegExp(r'/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\]')
        .allMatches(text)
        .map((m) => (double.parse(m.group(3)!), double.parse(m.group(4)!)))
        .toList();
  }

  group('gutterInches (page-count margin banding)', () {
    test('matches KDP\'s published bands exactly', () {
      expect(KdpPaperbackExporter.gutterInches(24), 0.375);
      expect(KdpPaperbackExporter.gutterInches(150), 0.375);
      expect(KdpPaperbackExporter.gutterInches(151), 0.5);
      expect(KdpPaperbackExporter.gutterInches(300), 0.5);
      expect(KdpPaperbackExporter.gutterInches(301), 0.625);
      expect(KdpPaperbackExporter.gutterInches(500), 0.625);
      expect(KdpPaperbackExporter.gutterInches(501), 0.75);
      expect(KdpPaperbackExporter.gutterInches(700), 0.75);
      expect(KdpPaperbackExporter.gutterInches(701), 0.875);
      expect(KdpPaperbackExporter.gutterInches(828), 0.875);
    });
  });

  group('outsideMinInches', () {
    test('is 0.25" without bleed and 0.375" with bleed', () {
      expect(KdpPaperbackExporter.outsideMinInches(false), 0.25);
      expect(KdpPaperbackExporter.outsideMinInches(true), 0.375);
    });
  });

  group('pageFormatFor', () {
    test('a 6x9 trim with no bleed has no size padding', () {
      final format = KdpPaperbackExporter.pageFormatFor(KdpTrimSize.in6x9, false, 100);
      expect(format.width, closeTo(6.0 * 72, 0.01));
      expect(format.height, closeTo(9.0 * 72, 0.01));
    });

    test('bleed adds 0.125" to width (outer edge only) and 0.25" to height (top+bottom)', () {
      final noBleed = KdpPaperbackExporter.pageFormatFor(KdpTrimSize.in6x9, false, 100);
      final withBleed = KdpPaperbackExporter.pageFormatFor(KdpTrimSize.in6x9, true, 100);

      expect(withBleed.width - noBleed.width, closeTo(0.125 * 72, 0.01));
      expect(withBleed.height - noBleed.height, closeTo(0.25 * 72, 0.01));
    });

    test('inside (left/right) margin follows the page-count gutter band', () {
      final shortBook = KdpPaperbackExporter.pageFormatFor(KdpTrimSize.in6x9, false, 100);
      final longBook = KdpPaperbackExporter.pageFormatFor(KdpTrimSize.in6x9, false, 600);

      expect(shortBook.marginLeft, closeTo(0.375 * 72, 0.01));
      expect(longBook.marginLeft, closeTo(0.75 * 72, 0.01));
      expect(shortBook.marginLeft, shortBook.marginRight);
      expect(longBook.marginLeft, longBook.marginRight);
    });
  });

  test('produces bytes that look like a real PDF (magic header + trailer)', () async {
    final bytes = await exporter.buildBytes(project, ManuscriptStructure(), trimSize: KdpTrimSize.in6x9);

    expect(ascii.decode(bytes.take(5).toList(), allowInvalid: true), '%PDF-');
    final tail = ascii.decode(
        bytes.skip((bytes.length - 32).clamp(0, bytes.length)).toList(),
        allowInvalid: true);
    expect(tail, contains('%%EOF'));
  });

  test('the actual PDF page size matches the requested trim size', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

    final bytes =
        await exporter.buildBytes(project, structure, trimSize: KdpTrimSize.in5_5x8_5);
    final boxes = mediaBoxesOf(bytes);

    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      expect(box.$1, closeTo(5.5 * 72, 0.5));
      expect(box.$2, closeTo(8.5 * 72, 0.5));
    }
  });

  test('bleed produces a visibly larger physical page than no bleed', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

    final noBleedBytes =
        await exporter.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9, bleed: false);
    final bleedBytes =
        await exporter.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9, bleed: true);

    final noBleedBox = mediaBoxesOf(noBleedBytes).first;
    final bleedBox = mediaBoxesOf(bleedBytes).first;

    expect(bleedBox.$1 - noBleedBox.$1, closeTo(0.125 * 72, 0.5));
    expect(bleedBox.$2 - noBleedBox.$2, closeTo(0.25 * 72, 0.5));
  });

  test('a manuscript producing fewer pages than the minimum throws KdpPaperbackExportException',
      () async {
    // minPageCount injected as 1 in setUp is trivially satisfied by any
    // real content, so use a higher injected minimum here to actually
    // trigger the "too short" path without needing a real 24-page draft.
    final strictExporter = KdpPaperbackExporter(projectDir, minPageCount: 50, maxPageCount: 100);
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

    expect(
      () => strictExporter.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9),
      throwsA(isA<KdpPaperbackExportException>()),
    );
  });

  test('a manuscript producing more pages than the maximum throws KdpPaperbackExportException',
      () async {
    final strictExporter = KdpPaperbackExporter(projectDir, minPageCount: 1, maxPageCount: 2);
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    // A long unbroken paragraph forces several real pages, comfortably over
    // an injected max of 2.
    await manuscriptService.writeScene(
      SceneDoc(id: 'ch-1', title: 'x', content: List.filled(400, 'A sentence of prose.').join(' ')),
    );

    expect(
      () => strictExporter.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9),
      throwsA(isA<KdpPaperbackExportException>()),
    );
  });

  test('page-count range is null (resolved from trim size + ink type) when not overridden', () {
    final defaultExporter = KdpPaperbackExporter(projectDir);
    expect(defaultExporter.minPageCount, null);
    expect(defaultExporter.maxPageCount, null);
  });

  test('page-count range varies by trim size and ink/paper type, per KDP\'s own table', () {
    expect(
      KdpTrimSize.in6x9.pageCountRange(KdpInkPaperType.blackWhite),
      (24, 828),
    );
    expect(
      KdpTrimSize.in6x9.pageCountRange(KdpInkPaperType.blackCream),
      (24, 776),
    );
    expect(
      KdpTrimSize.in6x9.pageCountRange(KdpInkPaperType.standardColor),
      (72, 600),
    );
    // 8.5"x8.5" has a tighter band than most trim sizes.
    expect(
      KdpTrimSize.in8_5x8_5.pageCountRange(KdpInkPaperType.blackWhite),
      (24, 590),
    );
    // 8.27"x11.69" doesn't offer standard color ink at all.
    expect(
      KdpTrimSize.in8_27x11_69.pageCountRange(KdpInkPaperType.standardColor),
      null,
    );
    expect(
      KdpTrimSize.in8_27x11_69.pageCountRange(KdpInkPaperType.premiumColor),
      (24, 590),
    );
  });

  test('buildBytes requires inkPaperType for a real paperback trim size when no override is set',
      () async {
    final defaultExporter = KdpPaperbackExporter(projectDir);
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

    expect(
      () => defaultExporter.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('buildBytes throws KdpPrintExportException for an ink/paper combo KDP does not offer',
      () async {
    final defaultExporter = KdpPaperbackExporter(projectDir);
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

    expect(
      () => defaultExporter.buildBytes(
        project,
        structure,
        trimSize: KdpTrimSize.in8_27x11_69,
        inkPaperType: KdpInkPaperType.standardColor,
      ),
      throwsA(isA<KdpPrintExportException>()),
    );
  });

  test('a book long enough to cross a gutter band rebuilds with the wider margin, changing '
      'the final page count from a naive single-pass build', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    // Many short paragraphs (not one enormous unbroken line, which is both
    // slow to lay out and doesn't reliably grow page count the way real
    // paragraph breaks do) — comfortably past the first (24-150 page)
    // gutter band, forcing the rebuild path to actually engage.
    final content = List.generate(
      3000,
      (i) => 'Paragraph number $i with a little more filler text to take up real space on the page.',
    ).join('\n\n');
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: content));

    final relaxedExporter = KdpPaperbackExporter(projectDir, minPageCount: 1, maxPageCount: 10000);
    final bytes =
        await relaxedExporter.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9);
    final pages = pageCountOf(bytes);

    // Comfortably past 150 pages confirms the wider (0.5"+) gutter band's
    // margin was actually used for the returned bytes, not just computed
    // and discarded.
    expect(pages, greaterThan(150));
    final finalGutter = KdpPaperbackExporter.gutterInches(pages);
    expect(finalGutter, greaterThan(0.375));
  });

  group('page numbering and running headers', () {
    /// Extracts every literal parenthesized PDF string-show operand from an
    /// *uncompressed* PDF's content streams — covers both `(text) Tj` and
    /// the kerning-adjusted `[(t) -20 (ext)] TJ` array form the `pdf`
    /// package actually emits (a first attempt matching only `(...) Tj`
    /// found nothing, since real output uses the array form). Only reliable
    /// with `compressPdf: false`, since compressed streams hide this
    /// entirely from a raw-bytes scan. Multiple adjacent strings in one TJ
    /// array (e.g. "M" "y" " " "N" ...) are joined back together, since
    /// that's how the package splits a run for kerning even when nothing
    /// unusual is happening.
    List<String> textStringsOf(List<int> bytes) {
      final text = latin1.decode(bytes, allowInvalid: true);
      final strings = RegExp(r'\(((?:[^()\\]|\\.)*)\)').allMatches(text).map((m) => m.group(1)!);
      return strings.toList();
    }

    /// Joins every extracted string into one blob, so a value that got
    /// split across multiple adjacent TJ array entries (e.g. "1" alone is
    /// fine, but multi-char text may be split character-by-character) can
    /// still be found via `contains`, without needing to reconstruct exact
    /// per-page boundaries.
    String allTextOf(List<int> bytes) => textStringsOf(bytes).join();

    test('title page has no stray blank page before the copyright/body starts (regression: '
        'title\'s own trailing NewPage was previously left in when title became its own '
        'MultiPage)', () async {
      final structure = ManuscriptStructure(
        nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
      );
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

      final bytes = await exporter.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9);

      // Title page (1) + auto-generated copyright page (1) + a single short
      // body page (1) = 3. If the stray trailing NewPage bug were still
      // present, this would be 4.
      expect(pageCountOf(bytes), 3);
    });

    test('body pages are numbered with Arabic numerals restarting at 1 when there is no '
        'front matter', () async {
      final noCompress = KdpPaperbackExporter(projectDir, minPageCount: 1, maxPageCount: 50, compressPdf: false);
      final structure = ManuscriptStructure(nodes: [
        ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter'),
        ManuscriptNode(id: 'ch-2', title: 'Chapter 2', typeLabel: 'Chapter'),
      ]);
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));
      await manuscriptService.writeScene(SceneDoc(id: 'ch-2', title: 'x', content: 'Short too.'));

      final bytes = await noCompress.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9);
      final allText = allTextOf(bytes);

      expect(allText, contains('1'));
      expect(allText, contains('2'));
    });

    test('front matter is numbered with lowercase roman numerals, and body resets to Arabic 1 '
        'afterward', () async {
      final noCompress = KdpPaperbackExporter(projectDir, minPageCount: 1, maxPageCount: 50, compressPdf: false);
      final structure = ManuscriptStructure(
        frontMatter: [
          SpecialSection(id: 'dedication-1', type: SpecialSectionType.dedication),
        ],
        nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
      );
      await manuscriptService
          .writeScene(SceneDoc(id: 'dedication-1', title: 'Dedication', content: 'For someone.'));
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

      final bytes = await noCompress.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9);
      final allText = allTextOf(bytes);

      // Front matter (now copyright + dedication) is roman-numbered.
      expect(allText, contains('i'));
      // Body still restarts at Arabic "1", not continuing from front
      // matter's page count.
      expect(allText, contains('1'));
    });

    test('the running header alternates book title (odd/recto pages) and author name '
        '(even/verso pages)', () async {
      final noCompress = KdpPaperbackExporter(projectDir, minPageCount: 1, maxPageCount: 50, compressPdf: false);
      final structure = ManuscriptStructure(nodes: [
        ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter'),
        ManuscriptNode(id: 'ch-2', title: 'Chapter 2', typeLabel: 'Chapter'),
      ]);
      // Enough content to force at least 2 body pages so both header
      // variants actually render.
      final content = List.generate(80, (i) => 'Paragraph $i with a bit of extra filler text.')
          .join('\n\n');
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: content));
      await manuscriptService.writeScene(SceneDoc(id: 'ch-2', title: 'x', content: 'Short.'));

      final bytes = await noCompress.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9);
      // Spaces between words aren't preserved as their own literal glyph in
      // the extracted text (the `pdf` package positions them via inter-
      // string offsets in the TJ array, not a literal " " character), so
      // compare with spaces stripped from both sides rather than requiring
      // an exact "My Novel" substring match.
      final allText = allTextOf(bytes).replaceAll(' ', '');

      expect(allText, contains(project.title.replaceAll(' ', '')));
      expect(allText, contains(project.author!.replaceAll(' ', '')));
    });

    /// Splits an *uncompressed* PDF into its ordered content streams (one
    /// per physical page, in document order) and extracts each stream's own
    /// literal text — lets a test check what's on a *specific* page rather
    /// than just "does this text appear anywhere in the whole document."
    /// Filters to streams containing a text-show operator (`Tj`/`TJ`) to
    /// skip any non-content streams (e.g. object streams) that might also
    /// match a bare `stream`/`endstream` pair.
    List<String> perPageTextOf(List<int> bytes) {
      final text = latin1.decode(bytes, allowInvalid: true);
      final streams = RegExp(r'stream\r?\n([\s\S]*?)endstream').allMatches(text).map((m) => m.group(1)!);
      // Matches both the singular `(text) Tj` operator and the kerning-
      // adjusted array form `[(t) -20 (ext)] TJ` the `pdf` package actually
      // emits (see `allTextOf`'s doc comment) — case matters (Tj vs TJ are
      // distinct operators), so both must be checked explicitly.
      return streams.where((s) => s.contains('Tj') || s.contains('TJ')).map((s) {
        return RegExp(r'\(((?:[^()\\]|\\.)*)\)').allMatches(s).map((m) => m.group(1)!).join();
      }).toList();
    }

    test('the header is suppressed specifically on each chapter\'s own first page, but shown on '
        'later pages within that same chapter', () async {
      final noCompress = KdpPaperbackExporter(projectDir, minPageCount: 1, maxPageCount: 50, compressPdf: false);
      final structure = ManuscriptStructure(nodes: [
        ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter'),
        ManuscriptNode(id: 'ch-2', title: 'Chapter 2', typeLabel: 'Chapter'),
      ]);
      // Chapter 1 spans several pages (so its 2nd+ pages can be checked for
      // a present header); chapter 2 is a single page (so its only page —
      // which is also its first — can be checked for a suppressed header).
      final longContent = List.generate(80, (i) => 'Paragraph $i with a bit of extra filler text.')
          .join('\n\n');
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: longContent));
      await manuscriptService.writeScene(SceneDoc(id: 'ch-2', title: 'x', content: 'Short.'));

      final bytes = await noCompress.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9);
      final pages = perPageTextOf(bytes);
      final title = project.title.replaceAll(' ', '');
      final author = project.author!.replaceAll(' ', '');
      bool hasHeader(String pageText) {
        final stripped = pageText.replaceAll(' ', '');
        return stripped.contains(title) || stripped.contains(author);
      }

      // pages[0] = title page, pages[1] = auto-generated copyright page
      // (neither expected to have a running header regardless).
      // pages[2] = chapter 1's own first page — header suppressed.
      // pages[3] = chapter 1's second page — header present.
      expect(hasHeader(pages[2]), isFalse,
          reason: 'chapter 1\'s own first page should have no running header');
      expect(hasHeader(pages[3]), isTrue,
          reason: 'chapter 1\'s second page should show the running header normally');

      // Chapter 2 is a single page, which is therefore also its own first
      // page — suppressed too, proving the suppression flag resets fresh
      // per chapter rather than only ever firing once for the whole body.
      expect(hasHeader(pages.last), isFalse,
          reason: 'chapter 2\'s own first (and only) page should also have its header suppressed');
    });

    test('the auto-generated copyright page is always present, even with no user front matter, '
        'and is numbered roman "i"', () async {
      final noCompress = KdpPaperbackExporter(projectDir, minPageCount: 1, maxPageCount: 50, compressPdf: false);
      final structure = ManuscriptStructure(
        nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
      );
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

      final bytes = await noCompress.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9);

      // Title page (1) + copyright page (1) + one body page (1) = 3.
      expect(pageCountOf(bytes), 3);

      final allText = allTextOf(bytes).replaceAll(' ', '');
      expect(allText, contains('Copyright'));
      expect(allText, contains(project.author!.replaceAll(' ', '')));

      // Copyright specifically lands on page index 1 (after the title
      // page), confirming it's the front matter's own first page.
      final pages = perPageTextOf(bytes);
      expect(pages[1], contains('Copyright'));
    });

    test('the copyright page comes before any of the project\'s own front matter, both landing '
        'in the same roman-numbered sequence', () async {
      final noCompress = KdpPaperbackExporter(projectDir, minPageCount: 1, maxPageCount: 50, compressPdf: false);
      final structure = ManuscriptStructure(
        frontMatter: [SpecialSection(id: 'dedication-1', type: SpecialSectionType.dedication)],
        nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
      );
      await manuscriptService
          .writeScene(SceneDoc(id: 'dedication-1', title: 'Dedication', content: 'For someone.'));
      await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

      final bytes = await noCompress.buildBytes(project, structure, trimSize: KdpTrimSize.in6x9);
      final pages = perPageTextOf(bytes);

      // pages[0] = title, pages[1] = copyright ("i"), pages[2] = dedication
      // ("ii"), pages[3] = body page 1. Spaces aren't preserved as literal
      // glyphs in the extracted text (see `allTextOf`'s doc comment), so
      // "For someone." lands as "Forsomeone."
      expect(pages[1], contains('Copyright'));
      expect(pages[2], contains('Forsomeone.'));
    });
  });

  test('exportToFile writes a real file to disk', () async {
    final outputPath = p.join(projectDir.path, 'out', 'novel-paperback.pdf');
    final file = await exporter.exportToFile(
      project,
      ManuscriptStructure(),
      outputPath,
      trimSize: KdpTrimSize.in6x9,
    );

    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(0));
  });
}
