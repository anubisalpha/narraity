import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/export/txt_exporter.dart';
import 'package:narraity/services/manuscript_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory projectDir;
  late ManuscriptService manuscriptService;
  late TxtExporter exporter;
  late Project project;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_txt_export_test_');
    manuscriptService = ManuscriptService(projectDir);
    exporter = TxtExporter(projectDir);
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

  test('includes title, subtitle, and author at the top', () async {
    final structure = ManuscriptStructure();
    final content = await exporter.buildContent(project, structure);
    expect(content, contains('My Novel'));
    expect(content, contains('A Subtitle'));
    expect(content, contains('by Jane Author'));
  });

  test('strips bold/italic/strikethrough markers from scene content', () async {
    final node = ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter');
    final structure = ManuscriptStructure(nodes: [node]);
    await manuscriptService.writeScene(
      SceneDoc(id: 'ch-1', title: 'Chapter 1', content: 'Some **bold** and *italic* and ~~gone~~ text.'),
    );

    final content = await exporter.buildContent(project, structure);

    expect(content, contains('Some bold and italic and gone text.'));
    expect(content, isNot(contains('**')));
    expect(content, isNot(contains('~~')));
  });

  test('renders sections in reading order with their titles', () async {
    final structure = ManuscriptStructure(nodes: [
      ManuscriptNode(id: 'ch-1', title: 'Chapter One', typeLabel: 'Chapter'),
      ManuscriptNode(id: 'ch-2', title: 'Chapter Two', typeLabel: 'Chapter'),
    ]);
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'Chapter One', content: 'First.'));
    await manuscriptService.writeScene(SceneDoc(id: 'ch-2', title: 'Chapter Two', content: 'Second.'));

    final content = await exporter.buildContent(project, structure);

    expect(content.indexOf('Chapter One'), lessThan(content.indexOf('Chapter Two')));
    expect(content.indexOf('First.'), lessThan(content.indexOf('Second.')));
  });

  test('a scene break renders as a bare *** line', () async {
    final structure = ManuscriptStructure(nodes: [
      ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter'),
    ]);
    await manuscriptService.writeScene(
      SceneDoc(id: 'ch-1', title: 'Chapter 1', content: 'Before.\n\n***\n\nAfter.'),
    );

    final content = await exporter.buildContent(project, structure);
    expect(content, contains('***'));
  });

  test('showTitleInExport: false omits that section\'s title line', () async {
    final structure = ManuscriptStructure(nodes: [
      ManuscriptNode(id: 'ch-1', title: 'Chapter One', typeLabel: 'Chapter'),
      ManuscriptNode(
          id: 'sc-1', title: 'Hidden Scene', typeLabel: 'Scene', showTitleInExport: false),
    ]);
    await manuscriptService.writeScene(SceneDoc(id: 'ch-1', title: 'Chapter One', content: 'First.'));
    await manuscriptService.writeScene(SceneDoc(id: 'sc-1', title: 'Hidden Scene', content: 'Second.'));

    final content = await exporter.buildContent(project, structure);

    expect(content, contains('Chapter One'));
    expect(content, isNot(contains('Hidden Scene')));
    expect(content, contains('Second.'));
  });

  test('exportToFile writes the content to disk', () async {
    final structure = ManuscriptStructure();
    final outputPath = p.join(projectDir.path, 'out', 'novel.txt');

    final file = await exporter.exportToFile(project, structure, outputPath);

    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), contains('My Novel'));
  });
}
