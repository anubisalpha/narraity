import 'dart:io';

import '../../models/manuscript.dart';
import '../../models/project.dart';
import '../manuscript_service.dart';
import 'manuscript_outline_builder.dart';
import 'markdown_lite.dart';

/// Plain-text export — PLAN.md's explicit "stripped-down" option: every
/// formatting marker (bold/italic/strikethrough/heading/quote) is stripped
/// down to its bare text, and images don't exist in a `.txt` file at all.
/// The export UI is responsible for the "images and formatting are
/// excluded" warning this format calls for; this class just produces the
/// content.
class TxtExporter {
  TxtExporter(this.projectDir);

  final Directory projectDir;

  Future<String> buildContent(Project project, ManuscriptStructure structure) async {
    final manuscript = ManuscriptService(projectDir);
    final sections = ManuscriptOutlineBuilder.build(structure);
    final buffer = StringBuffer()..writeln(project.title);
    if (project.subtitle != null && project.subtitle!.isNotEmpty) {
      buffer.writeln(project.subtitle);
    }
    if (project.author != null && project.author!.isNotEmpty) {
      buffer.writeln('by ${project.author}');
    }
    buffer.writeln();

    for (final section in sections) {
      final doc = await manuscript.readScene(section.id, fallbackTitle: section.title);
      buffer
        ..writeln(section.title)
        ..writeln();

      for (final block in MarkdownLite.parse(doc.content)) {
        if (block.type == MdBlockType.sceneBreak) {
          buffer
            ..writeln('***')
            ..writeln();
          continue;
        }
        for (final line in block.lines) {
          buffer.writeln(line.map((run) => run.text).join());
        }
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  Future<File> exportToFile(
    Project project,
    ManuscriptStructure structure,
    String outputPath,
  ) async {
    final content = await buildContent(project, structure);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }
}
