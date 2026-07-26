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
}
