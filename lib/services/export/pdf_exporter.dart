import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../models/manuscript.dart';
import '../../models/project.dart';
import '../manuscript_service.dart';
import 'manuscript_outline_builder.dart';
import 'markdown_lite.dart';

/// PDF export via the `pdf` package — the one export format here with a
/// genuinely mature pure-Dart library to lean on (unlike DOCX/EPUB, which
/// are hand-rolled). `maxPages` is raised well past the package's default
/// of 20, since a full novel is routinely hundreds of pages.
class PdfExporter {
  PdfExporter(this.projectDir);

  final Directory projectDir;

  Future<Uint8List> buildBytes(Project project, ManuscriptStructure structure) async {
    final manuscript = ManuscriptService(projectDir);
    final sections = ManuscriptOutlineBuilder.build(structure);

    final widgets = <pw.Widget>[..._titlePageWidgets(project)];
    for (final section in sections) {
      final doc = await manuscript.readScene(section.id, fallbackTitle: section.title);
      widgets.add(_sectionHeadingWidget(section.title, section.depth));
      for (final block in MarkdownLite.parse(doc.content)) {
        widgets.addAll(_blockWidgets(block));
      }
    }

    final pdfDoc = pw.Document();
    pdfDoc.addPage(
      pw.MultiPage(
        maxPages: 100000,
        margin: const pw.EdgeInsets.all(48),
        build: (context) => widgets,
      ),
    );
    return pdfDoc.save();
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

  // ---- widget building --------------------------------------------------

  double _headingFontSize(int depth) => switch (depth) {
        0 => 20,
        1 => 16,
        _ => 14,
      };

  List<pw.Widget> _titlePageWidgets(Project project) {
    final widgets = <pw.Widget>[
      pw.SizedBox(height: 220),
      pw.Center(
        child: pw.Text(
          project.title,
          style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
        ),
      ),
    ];
    if (project.subtitle != null && project.subtitle!.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 12));
      widgets.add(pw.Center(child: pw.Text(project.subtitle!, style: const pw.TextStyle(fontSize: 16))));
    }
    if (project.author != null && project.author!.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 24));
      widgets.add(
        pw.Center(child: pw.Text('by ${project.author}', style: const pw.TextStyle(fontSize: 14))),
      );
    }
    widgets.add(pw.NewPage());
    return widgets;
  }

  pw.Widget _sectionHeadingWidget(String title, int depth) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 20, bottom: 10),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: _headingFontSize(depth), fontWeight: pw.FontWeight.bold),
        ),
      );

  pw.TextSpan _spansFor(List<MdRun> runs, pw.TextStyle base) => pw.TextSpan(
        children: [
          for (final run in runs)
            pw.TextSpan(
              text: run.text,
              style: base.copyWith(
                fontWeight: run.bold ? pw.FontWeight.bold : base.fontWeight,
                fontStyle: run.italic ? pw.FontStyle.italic : base.fontStyle,
                decoration: run.strikethrough ? pw.TextDecoration.lineThrough : base.decoration,
              ),
            ),
        ],
      );

  List<pw.Widget> _blockWidgets(MdBlock block) {
    switch (block.type) {
      case MdBlockType.sceneBreak:
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 12),
            child: pw.Center(child: pw.Text('* * *')),
          ),
        ];

      case MdBlockType.heading:
        final size = _headingFontSize((block.headingLevel - 1).clamp(0, 5));
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
            child: pw.RichText(
              text: _spansFor(block.lines.first, pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold)),
            ),
          ),
        ];

      case MdBlockType.quote:
        return block.lines
            .map((line) => pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 24, bottom: 4),
                  child: pw.RichText(text: _spansFor(line, const pw.TextStyle())),
                ))
            .toList();

      case MdBlockType.paragraph:
        return block.lines
            .map((line) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.RichText(text: _spansFor(line, const pw.TextStyle())),
                ))
            .toList();
    }
  }
}
