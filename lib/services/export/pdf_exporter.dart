import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../models/manuscript.dart';
import '../../models/project.dart';
import '../annotation_service.dart';
import '../manuscript_service.dart';
import 'manuscript_outline_builder.dart';
import 'pdf_fonts.dart';
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
    final annotations = AnnotationService(projectDir);
    final sections = ManuscriptOutlineBuilder.build(structure);

    final widgets = <pw.Widget>[
      ..._widgets.titlePageWidgets(project),
      ...await _widgets.buildManuscriptBody(
        sections: sections,
        manuscript: manuscript,
        annotations: annotations,
      ),
    ];

    final pdfDoc = pw.Document(theme: await PdfFonts.theme());
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
