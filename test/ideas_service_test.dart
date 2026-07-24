import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/idea.dart';
import 'package:narraity/services/ideas_service.dart';
import 'package:narraity/services/library_service.dart';

void main() {
  late Directory tempDir;
  late LibraryService library;
  late IdeasService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_ideas_test_');
    library = LibraryService(rootOverride: tempDir);
    service = IdeasService(library);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('captureIdea writes to _GlobalIdeas and listIdeas finds it', () async {
    final idea = await service.captureIdea(
      title: 'A heist on a generation ship',
      body: 'The vault is the seed bank.',
      tags: ['plot', 'sci-fi'],
    );

    final file = File('${tempDir.path}/_GlobalIdeas/idea-${idea.id}.json');
    expect(await file.exists(), isTrue);

    final listed = await service.listIdeas();
    expect(listed.single.title, 'A heist on a generation ship');
    expect(listed.single.tags, ['plot', 'sci-fi']);
    expect(listed.single.status, IdeaStatus.active);
  });

  test('_GlobalIdeas is not treated as a project by the library', () async {
    await service.captureIdea(title: 'Stray idea');
    expect(await library.listProjects(), isEmpty);
  });

  test('promoteToNewProject creates the project, seeds a note, marks idea used', () async {
    final idea = await service.captureIdea(
      title: 'The Lighthouse Keeper',
      body: 'She keeps the light for ships that sank decades ago.',
    );

    final project = await service.promoteToNewProject(idea);

    expect(project.title, 'The Lighthouse Keeper');
    final notesDir = Directory('${tempDir.path}/${project.folderName}/notes');
    final noteFiles = notesDir.listSync().whereType<File>().toList();
    expect(noteFiles, hasLength(1));
    final note = jsonDecode(noteFiles.single.readAsStringSync()) as Map<String, dynamic>;
    expect(note['source'], 'globalIdea');
    expect(note['body'], contains('ships that sank'));

    final after = (await service.listIdeas()).single;
    expect(after.status, IdeaStatus.used);
    expect(after.linkedProjectId, project.id);
  });

  test('attachToProject seeds a note into an existing project and marks idea used', () async {
    final project = await library.createProject(title: 'Existing Novel');
    final idea = await service.captureIdea(title: 'Twist', body: 'The narrator is the villain.');

    await service.attachToProject(idea, project);

    final notesDir = Directory('${tempDir.path}/${project.folderName}/notes');
    expect(notesDir.listSync().whereType<File>(), hasLength(1));

    final after = (await service.listIdeas()).single;
    expect(after.status, IdeaStatus.used);
    expect(after.linkedProjectId, project.id);
  });

  test('deleteIdea removes the file', () async {
    final idea = await service.captureIdea(title: 'Disposable');
    await service.deleteIdea(idea);
    expect(await service.listIdeas(), isEmpty);
  });
}
