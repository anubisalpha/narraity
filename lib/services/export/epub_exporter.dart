import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../../models/manuscript.dart';
import '../../models/project.dart';
import '../manuscript_service.dart';
import 'manuscript_outline_builder.dart';
import 'markdown_lite.dart';

const _uuid = Uuid();

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
  EpubExporter(this.projectDir);

  final Directory projectDir;

  Future<Uint8List> buildBytes(Project project, ManuscriptStructure structure) async {
    final manuscript = ManuscriptService(projectDir);
    final sections = ManuscriptOutlineBuilder.build(structure);

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
      groups.last.parts.add((title: section.title, content: doc.content, showTitle: section.showTitle));
    }

    var index = 0;
    for (final group in groups) {
      index++;
      final id = 'section-$index';
      final href = 'text/$id.xhtml';
      addFile('OEBPS/$href', _groupXhtml(group));
      manifestItems.add((id, href));
      navEntries.add((href, group.title, group.depth));
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

  String _groupXhtml(_EpubSectionGroup group) {
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
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml">'
        '<head><title>${_escape(group.title)}</title>'
        '<link href="../styles.css" rel="stylesheet" type="text/css"/></head>'
        '<body>${buffer.toString()}</body></html>';
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
''';

  String _navXhtml(String bookTitle, List<(String href, String title, int depth)> entries) {
    final items = entries.map((e) => '<li><a href="${e.$1}">${_escape(e.$2)}</a></li>').join();
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
        '<head><title>Table of Contents</title>'
        '<link href="styles.css" rel="stylesheet" type="text/css"/></head>'
        '<body><nav epub:type="toc" id="toc">'
        '<h1>${_escape(bookTitle)}</h1><ol>$items</ol>'
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
