import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/library_service.dart';

void main() {
  late Directory tempDir;
  late LibraryService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_lib_test_');
    service = LibraryService(rootOverride: tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a new library starts empty', () async {
    expect(await service.listProjects(), isEmpty);
  });

  test('createProject writes project.json and the PLAN.md folder skeleton', () async {
    final project = await service.createProject(title: 'My First Novel', author: 'Marc');

    expect(project.title, 'My First Novel');
    expect(project.author, 'Marc');

    final projectDir = Directory('${tempDir.path}/${project.folderName}');
    expect(await File('${projectDir.path}/project.json').exists(), isTrue);
    for (final sub in ['manuscript', 'characters', 'worldbuilding', 'plot-grid', 'goals', '.sync']) {
      expect(await Directory('${projectDir.path}/$sub').exists(), isTrue, reason: sub);
    }
  });

  test('createProject with a duplicate title gets a disambiguated folder name', () async {
    final first = await service.createProject(title: 'Same Title');
    final second = await service.createProject(title: 'Same Title');

    expect(first.folderName, isNot(equals(second.folderName)));
  });

  test('listProjects finds created projects, newest-modified first', () async {
    final a = await service.createProject(title: 'Older');
    await Future.delayed(const Duration(milliseconds: 5));
    final b = await service.createProject(title: 'Newer');

    final projects = await service.listProjects();
    expect(projects.map((p) => p.id), [b.id, a.id]);
  });

  test('saveProject persists edits back to project.json', () async {
    final project = await service.createProject(title: 'Draft Title');
    final renamed = project.copyWith(title: 'Final Title', modified: DateTime.now());

    await service.saveProject(renamed);

    final reloaded = await service.listProjects();
    expect(reloaded.single.title, 'Final Title');
  });
}
