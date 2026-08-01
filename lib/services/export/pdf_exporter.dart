import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../models/manuscript.dart';
import '../../models/project.dart';
import '../manuscript_service.dart';
import 'manuscript_outline_builder.dart';
import 'markdown_lite.dart';
import 'pdf_widget_builder.dart';

/// PDF export via the `pdf` package — the one export format here with a
/// genuinely mature pure-Dart library to lean on (unlike DOCX/EPUB, which
/// are hand-rolled). `maxPages` is raised well past the package's default
/// of 20, since a full novel is routinely hundreds of pages.
///
/// General-purpose PDF, not KDP print-ready — no trim size, bleed, or
/// page-count-scaled margins. See `KdpPaperbackExporter` for that; both
/// share their Markdown-to-widget rendering via `PdfWidgetBuilder` rather
/// than duplicating it.
class PdfExporter {
  PdfExporter(this.projectDir);

  final Directory projectDir;
  final _widgets = const PdfWidgetBuilder();

  Future<Uint8List> buildBytes(Project project, ManuscriptStructure structure) async {
    final manuscript = ManuscriptService(projectDir);
    final sections = ManuscriptOutlineBuilder.build(structure);

    final widgets = <pw.Widget>[..._widgets.titlePageWidgets(project)];
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      // Chapter-boundary sections (see ExportSection.startsNewPage) always
      // start on a fresh page. Skip it for the very first section: the
      // title page already ends with its own NewPage, so adding another
      // here would insert a blank page (pw.NewPage() with no freeSpace
      // forces a break unconditionally, even immediately after one).
      if (section.startsNewPage && i > 0) {
        widgets.add(pw.NewPage());
      }
      final doc = await manuscript.readScene(section.id, fallbackTitle: section.title);
      if (section.showTitle) {
        widgets.addAll(_widgets.sectionHeadingWidgets(section.title, section.depth));
      }
      for (final block in MarkdownLite.parse(doc.content)) {
        widgets.addAll(_widgets.blockWidgets(block));
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
}
