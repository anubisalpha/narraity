import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/export/kdp_hardcover_exporter.dart';
import 'package:narraity/services/export/kdp_paperback_exporter.dart';
import 'package:narraity/services/manuscript_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory projectDir;
  late ManuscriptService manuscriptService;
  late KdpHardcoverExporter exporter;
  late Project project;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_kdp_hardcover_test_');
    manuscriptService = ManuscriptService(projectDir);
    // Small injected page-count range so tests can hit the boundary with a
    // realistic, fast manuscript rather than a genuinely 75- or 550-page one.
    exporter = KdpHardcoverExporter(projectDir, minPageCount: 1, maxPageCount: 50);
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

  int pageCountOf(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    return RegExp(r'/Type\s*/Page(?!s)').allMatches(text).length;
  }

  List<(double width, double height)> mediaBoxesOf(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    return RegExp(r'/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\]')
        .allMatches(text)
        .map((m) => (double.parse(m.group(3)!), double.parse(m.group(4)!)))
        .toList();
  }

  test('the default page-count range is KDP\'s real hardcover range (75-550), distinct from '
      'paperback\'s (24-828)', () {
    final defaultExporter = KdpHardcoverExporter(projectDir);
    expect(defaultExporter.minPageCount, 75);
    expect(defaultExporter.maxPageCount, 550);
  });

  test('produces bytes that look like a real PDF (magic header + trailer)', () async {
    final bytes =
        await exporter.buildBytes(project, ManuscriptStructure(), trimSize: KdpHardcoverTrimSize.in6x9);

    expect(ascii.decode(bytes.take(5).toList(), allowInvalid: true), '%PDF-');
    final tail = ascii.decode(
        bytes.skip((bytes.length - 32).clamp(0, bytes.length)).toList(), allowInvalid: true);
    expect(tail, contains('%%EOF'));
  });

  test('the actual PDF page size matches the requested hardcover trim size (distinct from any '
      'paperback trim size)', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

    final bytes = await exporter.buildBytes(project, structure, trimSize: KdpHardcoverTrimSize.in8_25x11);
    final boxes = mediaBoxesOf(bytes);

    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      expect(box.$1, closeTo(8.25 * 72, 0.5));
      expect(box.$2, closeTo(11.0 * 72, 0.5));
    }
  });

  test('bleed still adds 0.125" width / 0.25" height, same as paperback', () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

    final noBleedBytes = await exporter.buildBytes(project, structure,
        trimSize: KdpHardcoverTrimSize.in6x9, bleed: false);
    final bleedBytes = await exporter.buildBytes(project, structure,
        trimSize: KdpHardcoverTrimSize.in6x9, bleed: true);

    final noBleedBox = mediaBoxesOf(noBleedBytes).first;
    final bleedBox = mediaBoxesOf(bleedBytes).first;

    expect(bleedBox.$1 - noBleedBox.$1, closeTo(0.125 * 72, 0.5));
    expect(bleedBox.$2 - noBleedBox.$2, closeTo(0.25 * 72, 0.5));
  });

  test('a manuscript producing fewer pages than the hardcover minimum throws '
      'KdpPrintExportException', () async {
    final strictExporter = KdpHardcoverExporter(projectDir, minPageCount: 50, maxPageCount: 100);
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

    expect(
      () => strictExporter.buildBytes(project, structure, trimSize: KdpHardcoverTrimSize.in6x9),
      throwsA(isA<KdpPrintExportException>()),
    );
  });

  test('the auto-generated copyright page is present, same shared engine behavior as paperback',
      () async {
    final structure = ManuscriptStructure(
      nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter')],
    );
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'x', content: 'Short.'));

    final bytes = await exporter.buildBytes(project, structure, trimSize: KdpHardcoverTrimSize.in6x9);

    // Title (1) + copyright (1) + one body page (1) = 3 — same shape as the
    // equivalent paperback case.
    expect(pageCountOf(bytes), 3);
  });

  test('exportToFile writes a real file to disk', () async {
    final outputPath = p.join(projectDir.path, 'out', 'novel-hardcover.pdf');
    final file = await exporter.exportToFile(
      project,
      ManuscriptStructure(),
      outputPath,
      trimSize: KdpHardcoverTrimSize.in6x9,
    );

    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(0));
  });
}
