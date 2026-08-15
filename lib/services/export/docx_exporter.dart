import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/manuscript.dart';
import '../../models/project.dart';
import '../annotation_service.dart';
import '../manuscript_service.dart';
import 'footnote_markers.dart';
import 'manuscript_outline_builder.dart';
import 'markdown_lite.dart';

/// DOCX export, hand-rolled directly as OOXML (a `.docx` is just a ZIP of
/// XML parts) via the `archive` package already used elsewhere in this
/// project — no mature pure-Dart DOCX writer exists on pub.dev, same
/// situation as Hunspell/Vosk needing a hand-written binding instead of a
/// missing package. Uses direct paragraph/run formatting (bold, size,
/// indentation) rather than named styles, so the package needs no
/// `word/styles.xml` at all — fewer moving parts to get wrong without a
/// copy of Word on hand to verify against.
class DocxExporter {
  DocxExporter(this.projectDir);

  final Directory projectDir;

  Future<Uint8List> buildBytes(Project project, ManuscriptStructure structure) async {
    final manuscript = ManuscriptService(projectDir);
    final annotations = AnnotationService(projectDir);
    final sections = ManuscriptOutlineBuilder.build(structure);

    // Footnote bodies, keyed by their global sequential number — same
    // book-wide numbering scheme as EPUB/PDF, via the shared
    // `FootnoteMarkers` marker-insertion pattern.
    final footnoteBodies = <int, String>{};
    var nextFootnoteNumber = 1;

    final body = StringBuffer()..write(_titlePageXml(project));
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      // Skip the very first section: the title page already ends with its
      // own page break, so another one here would insert a blank page.
      if (section.startsNewPage && i > 0) {
        body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
      final doc = await manuscript.readScene(section.id, fallbackTitle: section.title);
      final marked = await FootnoteMarkers.markContent(
        annotations: annotations,
        sceneId: section.id,
        content: doc.content,
        startNumber: nextFootnoteNumber,
      );
      footnoteBodies.addAll(marked.bodies);
      nextFootnoteNumber = marked.nextNumber;

      if (section.showTitle) {
        body.write(_sectionHeadingXml(section.title, section.depth));
      }
      for (final block in MarkdownLite.parse(marked.content)) {
        body.write(_blockXml(block));
      }
    }

    final archive = Archive();
    void addFile(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addFile('[Content_Types].xml', _contentTypesXml);
    addFile('_rels/.rels', _rootRelsXml);
    addFile('word/document.xml', _documentXml(body.toString()));
    addFile('word/_rels/document.xml.rels', _documentRelsXml);
    addFile('word/footnotes.xml', _footnotesXml(footnoteBodies));

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

  // ---- XML building ---------------------------------------------------

  String _escape(String text) =>
      text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// Half-points (OOXML's `w:sz` unit) for a structural heading at [depth]
  /// (0 = top-level chapter/act) — decreasing size for deeper nesting.
  int _headingHalfPoints(int depth) => switch (depth) {
        0 => 32, // 16pt
        1 => 28, // 14pt
        _ => 24, // 12pt
      };

  String _titlePageXml(Project project) {
    final buffer = StringBuffer();
    buffer.write(
      '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="56"/></w:rPr>'
      '<w:t xml:space="preserve">${_escape(project.title)}</w:t></w:r></w:p>',
    );
    if (project.subtitle != null && project.subtitle!.isNotEmpty) {
      buffer.write(
        '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="32"/></w:rPr>'
        '<w:t xml:space="preserve">${_escape(project.subtitle!)}</w:t></w:r></w:p>',
      );
    }
    if (project.author != null && project.author!.isNotEmpty) {
      buffer.write(
        '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="24"/></w:rPr>'
        '<w:t xml:space="preserve">${_escape('by ${project.author}')}</w:t></w:r></w:p>',
      );
    }
    buffer.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
    return buffer.toString();
  }

  String _sectionHeadingXml(String title, int depth) {
    final size = _headingHalfPoints(depth);
    return '<w:p><w:pPr><w:spacing w:before="480" w:after="240"/></w:pPr>'
        '<w:r><w:rPr><w:b/><w:sz w:val="$size"/></w:rPr>'
        '<w:t xml:space="preserve">${_escape(title)}</w:t></w:r></w:p>';
  }

  /// Splits [run]'s text on any `FootnoteMarkers`-wrapped number, emitting
  /// a real `<w:footnoteReference>` run in place of each marker (styled
  /// superscript directly, since this exporter uses no `word/styles.xml` —
  /// see the class doc) interspersed with plain text runs for everything
  /// else, rather than one `<w:r>` for the whole run the way non-footnote
  /// text does.
  String _runXml(MdRun run) {
    if (!FootnoteMarkers.mayContainMarker(run.text)) return _plainRunXml(run.text, run);
    final matches = FootnoteMarkers.pattern.allMatches(run.text).toList();
    if (matches.isEmpty) return _plainRunXml(run.text, run);

    final buffer = StringBuffer();
    var lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        buffer.write(_plainRunXml(run.text.substring(lastEnd, match.start), run));
      }
      buffer.write(_footnoteReferenceXml(int.parse(match.group(1)!)));
      lastEnd = match.end;
    }
    if (lastEnd < run.text.length) {
      buffer.write(_plainRunXml(run.text.substring(lastEnd), run));
    }
    return buffer.toString();
  }

  String _plainRunXml(String text, MdRun run) {
    if (text.isEmpty) return '';
    final props = StringBuffer();
    if (run.bold) props.write('<w:b/>');
    if (run.italic) props.write('<w:i/>');
    if (run.strikethrough) props.write('<w:strike/>');
    final propsXml = props.isEmpty ? '' : '<w:rPr>$props</w:rPr>';
    return '<w:r>$propsXml<w:t xml:space="preserve">${_escape(text)}</w:t></w:r>';
  }

  String _footnoteReferenceXml(int number) =>
      '<w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr>'
      '<w:footnoteReference w:id="$number"/></w:r>';

  /// The `word/footnotes.xml` part — always present, same as a real Word
  /// document, even with no footnotes (an empty body still needs the two
  /// mandatory separator/continuationSeparator entries OOXML readers
  /// expect). One `<w:footnote>` per body, referenced by `document.xml`'s
  /// `<w:footnoteReference w:id="…">` elements via matching `w:id` — not a
  /// relationship id, so `document.xml` itself needs no change beyond the
  /// reference runs `_runXml` already emits.
  String _footnotesXml(Map<int, String> bodies) {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
          '<w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">')
      ..write('<w:footnote w:type="separator" w:id="-1">'
          '<w:p><w:r><w:separator/></w:r></w:p></w:footnote>')
      ..write('<w:footnote w:type="continuationSeparator" w:id="0">'
          '<w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>');

    final numbers = bodies.keys.toList()..sort();
    for (final number in numbers) {
      buffer.write('<w:footnote w:id="$number"><w:p>'
          '<w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:footnoteRef/></w:r>'
          '<w:r><w:t xml:space="preserve"> ${_escape(bodies[number]!)}</w:t></w:r>'
          '</w:p></w:footnote>');
    }
    buffer.write('</w:footnotes>');
    return buffer.toString();
  }

  String _blockXml(MdBlock block) {
    switch (block.type) {
      case MdBlockType.sceneBreak:
        return '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t>* * *</w:t></w:r></w:p>';

      case MdBlockType.heading:
        final size = _headingHalfPoints((block.headingLevel - 1).clamp(0, 5));
        final runs = block.lines.first.map(_runXml).join();
        return '<w:p><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr>'
            '<w:r><w:rPr><w:b/><w:sz w:val="$size"/></w:rPr></w:r>$runs</w:p>';

      case MdBlockType.quote:
        return block.lines.map((line) {
          final runs = line.map(_runXml).join();
          return '<w:p><w:pPr><w:ind w:left="720"/></w:pPr>$runs</w:p>';
        }).join();

      case MdBlockType.paragraph:
        return block.lines.map((line) {
          final runs = line.map(_runXml).join();
          return '<w:p><w:pPr><w:ind w:firstLine="720"/></w:pPr>$runs</w:p>';
        }).join();
    }
  }

  String _documentXml(String bodyXml) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$bodyXml'
      '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>'
      '</w:body></w:document>';

  static const _contentTypesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/footnotes.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>'
      '</Types>';

  static const _rootRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/>'
      '</Relationships>';

  /// `document.xml`'s own relationship to `footnotes.xml` — declared for
  /// package-structure correctness even though `<w:footnoteReference>`
  /// links to `<w:footnote>` by matching `w:id`, not by relationship id.
  static const _documentRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" '
      'Target="footnotes.xml"/>'
      '</Relationships>';
}
