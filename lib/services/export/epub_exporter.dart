import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../../models/annotation.dart';
import '../../models/manuscript.dart';
import '../../models/project.dart';
import '../annotation_service.dart';
import '../manuscript_service.dart';
import 'manuscript_outline_builder.dart';
import 'markdown_lite.dart';

const _uuid = Uuid();

/// Private-Use-Area character pair used to mark a footnote's position
/// inside a scene's raw markdown *before* `MarkdownLite.parse` runs — never
/// appears in real user content, and isn't one of `MarkdownLite`'s special
/// characters (`*`, `~`, `#`, `>`), so it survives parsing as ordinary
/// literal text inside whatever run it lands in. Substituted for a real
/// `<sup><a epub:type="noteref">` reference after the block/run HTML is
/// generated, rather than threading footnote data through
/// `_blockHtml`/`_runHtml`'s signatures.
final _footnoteMarker = String.fromCharCode(0xE000);
final _footnoteMarkerPattern =
    RegExp('${String.fromCharCode(0xE000)}(\\d+)${String.fromCharCode(0xE000)}');

String _wrapFootnoteMarker(int number) => '$_footnoteMarker$number$_footnoteMarker';

/// KDP's hard technical limits for a Kindle eBook (per its QA Standards
/// help page — see `KDP_CRIBSHEET.md`'s QA Standards section): each
/// individual HTML file under 30MB, and fewer than 300 HTML files total.
/// Checked at export time rather than left to fail silently at KDP upload —
/// a book that trips either of these needs restructuring (split an
/// enormous chapter, or reconsider a scene-per-file granularity), not a
/// corrupted export handed to the user.
const kEpubMaxFileBytes = 30 * 1000 * 1000;
const kEpubMaxFileCount = 300;

/// Thrown when the built EPUB would violate one of KDP's hard technical
/// limits — see [kEpubMaxFileBytes]/[kEpubMaxFileCount].
class EpubExportException implements Exception {
  EpubExportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One EPUB spine file's worth of sections — a chapter-boundary section plus
/// every non-boundary section (e.g. Scenes) that follows it before the next
/// boundary. [title]/[depth] (used for the nav/TOC entry and `<head><title>`)
/// come from the boundary section that started the group.
class _EpubSectionGroup {
  _EpubSectionGroup({required this.title, required this.depth});

  final String title;
  final int depth;
  final List<({String title, String content, bool showTitle})> parts = [];
}

/// EPUB export, hand-rolled directly (a `.epub` is a specifically-structured
/// ZIP: an uncompressed `mimetype` entry first, an EPUB3 package document,
/// and a nav document reused as the in-app Automatic TOC's export
/// counterpart) — like DOCX, no mature pure-Dart EPUB writer exists, so this
/// is built the same way as that exporter, via `archive`.
class EpubExporter {
  /// [maxFileBytes]/[maxFileCount] default to KDP's real limits — overridden
  /// only by tests, so a limit-check test can use a small threshold and
  /// small content instead of building a pathologically large (and slow to
  /// parse) real string to trip the real 30MB/300-file limits.
  EpubExporter(
    this.projectDir, {
    this.maxFileBytes = kEpubMaxFileBytes,
    this.maxFileCount = kEpubMaxFileCount,
  });

  final Directory projectDir;
  final int maxFileBytes;
  final int maxFileCount;

  Future<Uint8List> buildBytes(Project project, ManuscriptStructure structure) async {
    final manuscript = ManuscriptService(projectDir);
    final annotations = AnnotationService(projectDir);
    final sections = ManuscriptOutlineBuilder.build(structure);

    // Footnote bodies, keyed by their global sequential number (assigned in
    // document reading order as encountered below) — shared across every
    // group/file, since numbering runs continuously through the whole book
    // rather than resetting per chapter.
    final footnoteBodies = <int, String>{};
    var nextFootnoteNumber = 1;

    final archive = Archive();
    void addStored(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes)..compression = CompressionType.none);
    }

    void addFile(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    // The mimetype entry must be the first file in the archive, stored
    // uncompressed — EPUB readers use it to identify the format before
    // parsing any XML at all.
    addStored('mimetype', 'application/epub+zip');
    addFile('META-INF/container.xml', _containerXml);

    final manifestItems = <(String id, String href)>[];
    final navEntries = <(String href, String title, int depth)>[];

    // Group sections into files at chapter boundaries (ExportSection.
    // startsNewPage) rather than one file per section — otherwise every
    // Scene under a Chapter got its own EPUB spine file, fragmenting a
    // single chapter's continuous prose into a dozen separate reader
    // "pages" even though no heading was ever shown for those scenes.
    final groups = <_EpubSectionGroup>[];
    for (final section in sections) {
      if (groups.isEmpty || section.startsNewPage) {
        groups.add(_EpubSectionGroup(title: section.title, depth: section.depth));
      }
      final doc = await manuscript.readScene(section.id, fallbackTitle: section.title);
      var content = doc.content;

      // Numbered in ascending document order (so numbering reads naturally
      // through the book), but *inserted* rightmost-first so each
      // insertion's length doesn't shift the still-unprocessed offsets
      // earlier in the same scene.
      final footnotes = (await annotations.listForScene(section.id))
          .where((a) => a.kind == AnnotationKind.footnote)
          .toList()
        ..sort((a, b) => a.anchor.start.compareTo(b.anchor.start));

      final numbered = <(int number, Annotation footnote)>[];
      for (final footnote in footnotes) {
        final number = nextFootnoteNumber++;
        footnoteBodies[number] = footnote.body;
        numbered.add((number, footnote));
      }

      for (final (number, footnote) in numbered.reversed) {
        final clamped = footnote.anchor.start.clamp(0, content.length);
        content = content.substring(0, clamped) +
            _wrapFootnoteMarker(number) +
            content.substring(clamped);
      }

      groups.last.parts.add((title: section.title, content: content, showTitle: section.showTitle));
    }

    var index = 0;
    for (final group in groups) {
      index++;
      final id = 'section-$index';
      final href = 'text/$id.xhtml';
      final xhtml = _groupXhtml(group, footnoteBodies);

      final byteLength = utf8.encode(xhtml).length;
      if (byteLength > maxFileBytes) {
        throw EpubExportException(
          'Section "${group.title}" is ${(byteLength / 1000000).toStringAsFixed(1)}MB, over '
          'KDP\'s 30MB-per-file limit. Split it into smaller sections before exporting.',
        );
      }

      addFile('OEBPS/$href', xhtml);
      manifestItems.add((id, href));
      navEntries.add((href, group.title, group.depth));
    }

    if (manifestItems.length + 1 > maxFileCount) {
      // +1 accounts for nav.xhtml, an XHTML file itself — styles.css and
      // content.opf aren't HTML documents, so they don't count toward this.
      throw EpubExportException(
        'This EPUB would contain ${manifestItems.length + 1} HTML files, over KDP\'s 300-file '
        'limit. Consider merging some sections or reducing the chapter-boundary granularity.',
      );
    }

    addFile('OEBPS/nav.xhtml', _navXhtml(project.title, navEntries));
    addFile('OEBPS/styles.css', _stylesCss);
    addFile('OEBPS/content.opf', _contentOpf(project, manifestItems));

    return ZipEncoder().encodeBytes(archive);
  }

  Future<File> exportToFile(
    Project project,
    ManuscriptStructure structure,
    String outputPath,
  ) async {
    final bytes = await buildBytes(project, structure);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file;
  }

  // ---- XML/XHTML building ----------------------------------------------

  String _escape(String text) =>
      text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  static const _containerXml = '<?xml version="1.0" encoding="UTF-8"?>'
      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';

  String _runHtml(MdRun run) {
    var text = _escape(run.text);
    if (run.bold) text = '<strong>$text</strong>';
    if (run.italic) text = '<em>$text</em>';
    if (run.strikethrough) text = '<s>$text</s>';
    return text;
  }

  /// [firstParagraph] drops the first-line indent — traditional book
  /// typesetting convention (matches the reference Kindle Create export):
  /// the paragraph immediately opening a chapter isn't indented, every one
  /// after it is.
  String _blockHtml(MdBlock block, {bool firstParagraph = false}) {
    switch (block.type) {
      case MdBlockType.sceneBreak:
        // Previously a bare <hr/> with no visible marker at all — every
        // other export format (TXT/DOCX/PDF) renders literal "* * *" text,
        // so this was silently inconsistent.
        return '<p class="scenebreak">* * *</p>';
      case MdBlockType.heading:
        final level = block.headingLevel.clamp(2, 6); // h1 reserved for the section title itself
        final runs = block.lines.first.map(_runHtml).join();
        return '<h$level>$runs</h$level>';
      case MdBlockType.quote:
        final paragraphs = block.lines.map((line) => '<p>${line.map(_runHtml).join()}</p>').join();
        return '<blockquote>$paragraphs</blockquote>';
      case MdBlockType.paragraph:
        var isFirst = firstParagraph;
        return block.lines.map((line) {
          final cls = isFirst ? ' class="noindent"' : '';
          isFirst = false;
          return '<p$cls>${line.map(_runHtml).join()}</p>';
        }).join();
    }
  }

  /// [footnoteBodies] is the whole book's footnote text keyed by global
  /// number — only the numbers actually referenced via markers *within this
  /// group* get rendered as `<aside>` elements, placed at this file's end
  /// (i.e. the enclosing chapter's end, since one group = one chapter file)
  /// per KDP's footnote-placement guidance.
  String _groupXhtml(_EpubSectionGroup group, Map<int, String> footnoteBodies) {
    final buffer = StringBuffer();
    var sawFirstParagraph = false;
    for (final part in group.parts) {
      // `<head><title>` (below) is reader/OS-chrome metadata — kept
      // regardless, since a part's own `showTitle` only controls whether
      // its heading is printed in the visible page body.
      if (part.showTitle) buffer.write('<h1>${_escape(part.title)}</h1>');
      for (final block in MarkdownLite.parse(part.content)) {
        final isFirstParagraphOfChapter =
            !sawFirstParagraph && block.type == MdBlockType.paragraph;
        buffer.write(_blockHtml(block, firstParagraph: isFirstParagraphOfChapter));
        if (isFirstParagraphOfChapter) sawFirstParagraph = true;
      }
    }

    // Footnote markers survive `_escape` untouched (they're not &/</>), so
    // they're still literally present in the buffer at this point — collect
    // which numbers this file actually references before replacing them,
    // so only relevant asides get appended here.
    final referenced = _footnoteMarkerPattern
        .allMatches(buffer.toString())
        .map((m) => int.parse(m.group(1)!))
        .toSet();

    var body = buffer.toString().replaceAllMapped(_footnoteMarkerPattern, (match) {
      final number = match.group(1)!;
      // Not <sup> — it's absent from KDP's Kindle Format 8 supported-tag list
      // (see KDP_CRIBSHEET.md). class="footnote-ref" gets the same raised,
      // smaller look via styles.css instead.
      return '<a id="src-$number" href="#fn-$number" '
          'epub:type="noteref" class="footnote-ref">$number</a>';
    });

    if (referenced.isNotEmpty) {
      final asides = (referenced.toList()..sort()).map((number) {
        final text = footnoteBodies[number] ?? '';
        return '<aside id="fn-$number" epub:type="footnote">'
            '<p><a href="#src-$number" epub:type="noteref">$number.</a> ${_escape(text)}</p>'
            '</aside>';
      }).join();
      body += asides;
    }

    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" '
        'xml:lang="en" lang="en">'
        '<head><title>${_escape(group.title)}</title>'
        '<link href="../styles.css" rel="stylesheet" type="text/css"/></head>'
        '<body>$body</body></html>';
  }

  static const _stylesCss = '''
body { font-family: serif; line-height: 1.4; margin: 5% 8%; }
h1 { text-align: center; text-transform: uppercase; font-size: 1.4em; margin: 2em 0 1.5em; }
h2, h3, h4, h5, h6 { margin: 1.5em 0 0.5em; }
p { margin: 0; text-indent: 1.5em; }
p.noindent, p.scenebreak { text-indent: 0; }
p.scenebreak { text-align: center; margin: 1.2em 0; }
blockquote { margin: 1em 2em; }
blockquote p { text-indent: 0; }
a.footnote-ref { vertical-align: super; font-size: 0.7em; text-decoration: none; }
''';

  /// Builds the nav doc's `<ol>`, nested **at most two levels deep** —
  /// Kindle devices/apps only support two levels of ToC nesting (see
  /// `KDP_CRIBSHEET.md`'s Navigation section); a manuscript tree can easily
  /// go deeper than that (Book > Act > Chapter all count as chapter-boundary
  /// groups per `ManuscriptOutlineBuilder`), so this must actively collapse
  /// rather than mirror the tree's real depth. Top level = the shallowest
  /// depth present among the boundary groups; everything else, regardless
  /// of how much deeper it nominally sits, becomes a second-level leaf
  /// under the nearest preceding top-level entry rather than nesting
  /// further — matching KDP's cap instead of silently exceeding it.
  String _navList(List<(String href, String title, int depth)> entries) {
    if (entries.isEmpty) return '<ol></ol>';
    final topDepth = entries.map((e) => e.$3).reduce((a, b) => a < b ? a : b);

    final buffer = StringBuffer('<ol>');
    var topLevelOpen = false; // a top-level <li> is open, awaiting its closing tag
    var childrenOpen = false; // that <li>'s nested <ol> for second-level entries is open

    void closeTopLevelLi() {
      if (childrenOpen) {
        buffer.write('</ol></li>');
        childrenOpen = false;
      } else if (topLevelOpen) {
        buffer.write('</li>');
      }
      topLevelOpen = false;
    }

    for (final entry in entries) {
      final (href, title, depth) = entry;
      final link = '<a href="$href">${_escape(title)}</a>';
      // Falls back to top-level even when depth > topDepth if no top-level
      // <li> is open yet to nest under — shouldn't happen given how
      // `ManuscriptOutlineBuilder` walks (front matter and the tree both
      // start at depth 0), but nesting an <ol> directly under another <ol>
      // with no <li> ancestor would produce invalid HTML if it ever did.
      if (depth <= topDepth || !topLevelOpen) {
        closeTopLevelLi();
        buffer.write('<li>$link');
        topLevelOpen = true;
      } else {
        if (!childrenOpen) {
          buffer.write('<ol>');
          childrenOpen = true;
        }
        buffer.write('<li>$link</li>');
      }
    }
    closeTopLevelLi();
    buffer.write('</ol>');
    return buffer.toString();
  }

  String _navXhtml(String bookTitle, List<(String href, String title, int depth)> entries) {
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" '
        'xml:lang="en" lang="en">'
        '<head><title>Table of Contents</title>'
        '<link href="styles.css" rel="stylesheet" type="text/css"/></head>'
        '<body><nav epub:type="toc" id="toc">'
        '<h1>${_escape(bookTitle)}</h1>${_navList(entries)}'
        '</nav></body></html>';
  }

  String _contentOpf(Project project, List<(String id, String href)> items) {
    final manifest = items
        .map((i) => '<item id="${i.$1}" href="${i.$2}" media-type="application/xhtml+xml"/>')
        .join();
    final spine = items.map((i) => '<itemref idref="${i.$1}"/>').join();
    final author = project.author != null && project.author!.isNotEmpty
        ? '<dc:creator>${_escape(project.author!)}</dc:creator>'
        : '';

    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="pub-id">urn:uuid:${_uuid.v4()}</dc:identifier>'
        '<dc:title>${_escape(project.title)}</dc:title>'
        '$author'
        '<dc:language>en</dc:language>'
        '</metadata>'
        '<manifest>'
        '<item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>'
        '<item id="css" href="styles.css" media-type="text/css"/>'
        '$manifest'
        '</manifest>'
        '<spine>$spine</spine>'
        '</package>';
  }
}
