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

    expect(structure.acts, hasLength(1));
    expect(structure.acts.first.title, 'Act 1');
    expect(structure.acts.first.chapters.single.scenes, hasLength(1));

    // The starter scene's file exists on disk too.
    final sceneId = structure.acts.first.chapters.single.scenes.single.id;
    expect(File('${tempDir.path}/manuscript/scenes/$sceneId.md').existsSync(), isTrue);

    // Reload gives the same structure back, not a new seed.
    final reloaded = await service.loadStructure();
    expect(reloaded.acts.single.chapters.single.scenes.single.id, sceneId);
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

  test('addScene/addChapter/addAct extend the structure and persist', () async {
    final structure = await service.loadStructure();
    final act = structure.acts.first;

    await service.addChapter(structure, act);
    final scene = await service.addScene(structure, act.chapters[1]);
    await service.addAct(structure);

    final reloaded = await service.loadStructure();
    expect(reloaded.acts, hasLength(2));
    expect(reloaded.acts.first.chapters, hasLength(2));
    expect(reloaded.acts.first.chapters[1].scenes.single.id, scene.id);
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

  test('reorderScene moves a scene within its chapter and persists', () async {
    final structure = await service.loadStructure();
    final chapter = structure.acts.first.chapters.first;
    final first = chapter.scenes.first;
    await service.addScene(structure, chapter);
    final second = chapter.scenes[1];

    await service.reorderScene(structure, chapter, 0, 2);

    final reloaded = await service.loadStructure();
    final scenes = reloaded.acts.first.chapters.first.scenes;
    expect(scenes.map((s) => s.id), [second.id, first.id]);
  });

  test('deleteScene removes both the ref and the file', () async {
    final structure = await service.loadStructure();
    final chapter = structure.acts.first.chapters.first;
    final scene = chapter.scenes.first;

    await service.deleteScene(structure, chapter, scene);

    final reloaded = await service.loadStructure();
    expect(reloaded.acts.first.chapters.first.scenes, isEmpty);
    expect(
      File('${tempDir.path}/manuscript/scenes/${scene.id}.md').existsSync(),
      isFalse,
    );
  });

  test('totalWordCount sums scenes and special sections', () async {
    final structure = await service.loadStructure();
    final sceneId = structure.acts.first.chapters.first.scenes.first.id;
    await service.writeScene(
        SceneDoc(id: sceneId, title: 'S1', content: 'one two three'));
    final prologue =
        await service.addSpecialSection(structure, SpecialSectionType.prologue);
    await service.writeScene(
        SceneDoc(id: prologue.id, title: 'Prologue', content: 'four five'));

    expect(await service.totalWordCount(structure), 5);
  });
}
