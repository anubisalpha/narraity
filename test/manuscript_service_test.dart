import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/services/manuscript_service.dart';

void main() {
  late Directory tempDir;
  late ManuscriptService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_ms_test_');
    service = ManuscriptService(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('loadStructure seeds Act 1 / Chapter 1 / Scene 1 on first open', () async {
    final structure = await service.loadStructure();

    expect(structure.nodes, hasLength(1));
    final act = structure.nodes.first;
    expect(act.title, 'Act 1');
    final chapter = act.children.single;
    expect(chapter.children, hasLength(1));

    // The starter scene's file exists on disk too.
    final sceneId = chapter.children.single.id;
    expect(File('${tempDir.path}/manuscript/scenes/$sceneId.md').existsSync(), isTrue);

    // Reload gives the same structure back, not a new seed.
    final reloaded = await service.loadStructure();
    expect(reloaded.nodes.single.children.single.children.single.id, sceneId);
  });

  test('scene content round-trips through front-matter markdown', () async {
    final doc = SceneDoc(
      id: 'scene-test',
      title: 'The Storm',
      content: 'Rain hammered the shutters.\n\nNobody slept.',
      pov: 'Elena',
    );
    await service.writeScene(doc);

    final read = await service.readScene('scene-test');
    expect(read.title, 'The Storm');
    expect(read.pov, 'Elena');
    expect(read.content, 'Rain hammered the shutters.\n\nNobody slept.');
    expect(read.wordCount, 6);
  });

  test('addNode extends the structure at any depth and persists', () async {
    final structure = await service.loadStructure();
    final act = structure.nodes.first;
    final chapter = act.children.first;

    final chapter2 = await service.addNode(structure, typeLabel: 'Chapter', parent: act);
    final scene =
        await service.addNode(structure, typeLabel: 'Scene', parent: chapter2);
    await service.addNode(structure, typeLabel: 'Act');

    final reloaded = await service.loadStructure();
    expect(reloaded.nodes, hasLength(2));
    expect(reloaded.nodes.first.children, hasLength(2));
    expect(reloaded.nodes.first.children[1].children.single.id, scene.id);
    expect(chapter.title, 'Chapter 1');
  });

  test('special sections land in the right matter list and get files', () async {
    final structure = await service.loadStructure();

    final prologue =
        await service.addSpecialSection(structure, SpecialSectionType.prologue);
    final epilogue =
        await service.addSpecialSection(structure, SpecialSectionType.epilogue);

    final reloaded = await service.loadStructure();
    expect(reloaded.frontMatter.single.id, prologue.id);
    expect(reloaded.backMatter.single.id, epilogue.id);
    expect(
      File('${tempDir.path}/manuscript/scenes/${prologue.id}.md').existsSync(),
      isTrue,
    );

    // Reading order: prologue first, epilogue last.
    expect(reloaded.allContentIds.first, prologue.id);
    expect(reloaded.allContentIds.last, epilogue.id);
  });

  test('reorderNode moves a child within its parent and persists', () async {
    final structure = await service.loadStructure();
    final chapter = structure.nodes.first.children.first;
    final first = chapter.children.first;
    await service.addNode(structure, typeLabel: 'Scene', parent: chapter);
    final second = chapter.children[1];

    await service.reorderNode(structure, chapter, 0, 2);

    final reloaded = await service.loadStructure();
    final scenes = reloaded.nodes.first.children.first.children;
    expect(scenes.map((s) => s.id), [second.id, first.id]);
  });

  test('deleteNode removes both the node and its file', () async {
    final structure = await service.loadStructure();
    final chapter = structure.nodes.first.children.first;
    final scene = chapter.children.first;

    await service.deleteNode(structure, scene);

    final reloaded = await service.loadStructure();
    expect(reloaded.nodes.first.children.first.children, isEmpty);
    expect(
      File('${tempDir.path}/manuscript/scenes/${scene.id}.md').existsSync(),
      isFalse,
    );
  });

  test('totalWordCount sums scenes and special sections', () async {
    final structure = await service.loadStructure();
    final sceneId = structure.nodes.first.children.first.children.first.id;
    await service.writeScene(
        SceneDoc(id: sceneId, title: 'S1', content: 'one two three'));
    final prologue =
        await service.addSpecialSection(structure, SpecialSectionType.prologue);
    await service.writeScene(
        SceneDoc(id: prologue.id, title: 'Prologue', content: 'four five'));

    expect(await service.totalWordCount(structure), 5);
  });
}
