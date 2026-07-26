import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/manuscript.dart';
import '../../models/project.dart';
import '../manuscript_service.dart';
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
    final sections = ManuscriptOutlineBuilder.build(structure);

    final body = StringBuffer()..write(_titlePageXml(project));
    for (final section in sections) {
      final doc = await manuscript.readScene(section.id, fallbackTitle: section.title);
      body.write(_sectionHeadingXml(section.title, section.depth));
      for (final block in MarkdownLite.parse(doc.content)) {
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

  String _runXml(MdRun run) {
    final props = StringBuffer();
    if (run.bold) props.write('<w:b/>');
    if (run.italic) props.write('<w:i/>');
    if (run.strikethrough) props.write('<w:strike/>');
    final propsXml = props.isEmpty ? '' : '<w:rPr>$props</w:rPr>';
    return '<w:r>$propsXml<w:t xml:space="preserve">${_escape(run.text)}</w:t></w:r>';
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
      '</Types>';

  static const _rootRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/>'
      '</Relationships>';
}
