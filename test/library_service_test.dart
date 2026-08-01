import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/library_service.dart';
import 'package:path/path.dart' as p;

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

  test('createProject accepts a seriesId, and it round-trips through project.json', () async {
    final project = await service.createProject(title: 'Book One', seriesId: 'series-1');

    expect(project.seriesId, 'series-1');
    final reloaded = await service.listProjects();
    expect(reloaded.single.seriesId, 'series-1');
  });

  test('Project.copyWith(clearSeriesId: true) removes it, and that persists', () async {
    final project = await service.createProject(title: 'Book One', seriesId: 'series-1');
    await service.saveProject(project.copyWith(clearSeriesId: true));

    final reloaded = await service.listProjects();
    expect(reloaded.single.seriesId, isNull);
  });

  test('createProject defaults to ProjectKind.novel when no kind is given', () async {
    final project = await service.createProject(title: 'Untyped Book');

    expect(project.kind, ProjectKind.novel);
    final reloaded = await service.listProjects();
    expect(reloaded.single.kind, ProjectKind.novel);
  });

  test('createProject accepts a ProjectKind, and it round-trips through project.json', () async {
    final project =
        await service.createProject(title: 'A Comic', kind: ProjectKind.comic);

    expect(project.kind, ProjectKind.comic);
    final reloaded = await service.listProjects();
    expect(reloaded.single.kind, ProjectKind.comic);
  });

  test('Project.copyWith can change kind, and that persists', () async {
    final project = await service.createProject(title: 'Genre Switch');
    await service.saveProject(project.copyWith(kind: ProjectKind.script));

    final reloaded = await service.listProjects();
    expect(reloaded.single.kind, ProjectKind.script);
  });

  test('a project.json written before ProjectKind existed still loads, defaulting to novel',
      () async {
    final project = await service.createProject(title: 'Legacy Project');
    final projectFile = File(p.join(tempDir.path, project.folderName, 'project.json'));
    final json = jsonDecode(await projectFile.readAsString()) as Map<String, dynamic>;
    json.remove('kind'); // simulate a project.json from before this field existed
    await projectFile.writeAsString(jsonEncode(json));

    final reloaded = await service.listProjects();
    expect(reloaded.single.kind, ProjectKind.novel);
  });

  test('setCoverImage copies the file into assets/covers/ and persists coverImagePath',
      () async {
    final project = await service.createProject(title: 'Cover Test');
    final sourceImage = File('${tempDir.path}/source.jpg')..writeAsBytesSync([1, 2, 3, 4]);

    final updated = await service.setCoverImage(project, sourceImage);

    expect(updated.coverImagePath, p.join('assets', 'covers', 'cover.jpg'));
    final absolute = await service.coverImageAbsolutePath(updated);
    expect(await File(absolute!).exists(), isTrue);
    expect(await File(absolute).readAsBytes(), [1, 2, 3, 4]);

    final reloaded = await service.listProjects();
    expect(reloaded.single.coverImagePath, p.join('assets', 'covers', 'cover.jpg'));
  });

  test('setCoverImage replacing an existing cover with a different extension removes the old file',
      () async {
    final project = await service.createProject(title: 'Cover Test');
    final firstImage = File('${tempDir.path}/first.jpg')..writeAsBytesSync([1]);
    final secondImage = File('${tempDir.path}/second.png')..writeAsBytesSync([2]);

    final afterFirst = await service.setCoverImage(project, firstImage);
    final afterSecond = await service.setCoverImage(afterFirst, secondImage);

    expect(afterSecond.coverImagePath, p.join('assets', 'covers', 'cover.png'));
    final coversDir = Directory('${tempDir.path}/${project.folderName}/assets/covers');
    final remaining = await coversDir.list().map((e) => e.path.split(Platform.pathSeparator).last).toList();
    expect(remaining, ['cover.png']);
  });

  test('removeCoverImage deletes the file and clears coverImagePath', () async {
    final project = await service.createProject(title: 'Cover Test');
    final sourceImage = File('${tempDir.path}/source.jpg')..writeAsBytesSync([1]);
    final withCover = await service.setCoverImage(project, sourceImage);
    final absolute = (await service.coverImageAbsolutePath(withCover))!;

    final updated = await service.removeCoverImage(withCover);

    expect(updated.coverImagePath, isNull);
    expect(await File(absolute).exists(), isFalse);
    final reloaded = await service.listProjects();
    expect(reloaded.single.coverImagePath, isNull);
  });

  test('sortOrder round-trips through project.json, including 0 (a valid position, not "unset")',
      () async {
    final project = await service.createProject(title: 'Ordered');
    expect(project.sortOrder, isNull);

    await service.saveProject(project.copyWith(sortOrder: 0));
    final reloaded = await service.listProjects();
    expect(reloaded.single.sortOrder, 0);
  });

  group('archive/delete/restore', () {
    test('archiveProject removes the live project and lists it under Archived', () async {
      final project = await service.createProject(title: 'To Archive', author: 'Marc');
      await service.archiveProject(project);

      expect(await service.listProjects(), isEmpty);
      final archived = await service.listArchived();
      expect(archived, hasLength(1));
      expect(archived.single.title, 'To Archive');
      expect(archived.single.author, 'Marc');
    });

    test('deleteProject removes the live project and lists it under Deleted, not Archived',
        () async {
      final project = await service.createProject(title: 'To Delete');
      await service.deleteProject(project);

      expect(await service.listProjects(), isEmpty);
      expect(await service.listArchived(), isEmpty);
      final deleted = await service.listDeleted();
      expect(deleted, hasLength(1));
      expect(deleted.single.title, 'To Delete');
    });

    test('restoreArchived brings the project back with its original content intact', () async {
      final project = await service.createProject(title: 'Round Trip', author: 'Marc');
      await service.archiveProject(project);

      final archived = await service.listArchived();
      final restored = await service.restoreArchived(archived.single);

      expect(restored.id, project.id);
      expect(restored.title, 'Round Trip');
      expect(restored.author, 'Marc');
      expect(await service.listArchived(), isEmpty);
      final projects = await service.listProjects();
      expect(projects, hasLength(1));
      expect(projects.single.id, project.id);
    });

    test('restoreDeleted works the same way as restoreArchived', () async {
      final project = await service.createProject(title: 'Deleted Round Trip');
      await service.deleteProject(project);

      final deleted = await service.listDeleted();
      final restored = await service.restoreDeleted(deleted.single);

      expect(restored.title, 'Deleted Round Trip');
      expect(await service.listDeleted(), isEmpty);
      expect(await service.listProjects(), hasLength(1));
    });

    test('restoring a project whose original folder name is now taken gets a disambiguated name',
        () async {
      final project = await service.createProject(title: 'Name Clash');
      await service.archiveProject(project);
      await service.createProject(title: 'Name Clash'); // occupies the original folder name

      final archived = await service.listArchived();
      final restored = await service.restoreArchived(archived.single);

      expect(await service.listProjects(), hasLength(2));
      expect(restored.folderName, isNot('Name Clash'));
    });

    test('archived/deleted zips never appear in listProjects', () async {
      final project = await service.createProject(title: 'Hidden From Library');
      await service.archiveProject(project);
      expect(await service.listProjects(), isEmpty);
    });
  });
}
