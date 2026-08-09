import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/drive_restore_service.dart';
import 'package:narraity/services/drive_sync_service.dart';
import 'package:narraity/services/library_service.dart';
import 'package:path/path.dart' as p;

import 'fake_drive_remote_store.dart';

void main() {
  late Directory libraryRoot;
  late LibraryService library;
  late FakeDriveRemoteStore remote;
  late DriveSyncService syncService;

  setUp(() {
    libraryRoot = Directory.systemTemp.createTempSync('narraity_drive_restore_test_');
    library = LibraryService(rootOverride: libraryRoot);
    remote = FakeDriveRemoteStore();
    syncService = DriveSyncService(remoteStore: remote, deviceName: 'test-device');
  });

  tearDown(() {
    libraryRoot.deleteSync(recursive: true);
  });

  void seedRemoteProject(String folderName, {String title = 'Untitled'}) {
    remote.seed(
      folderName,
      'project.json',
      utf8.encode(
        jsonEncode({
          'id': 'fake-id-$folderName',
          'title': title,
          'created': DateTime(2026).toIso8601String(),
          'modified': DateTime(2026).toIso8601String(),
        }),
      ),
    );
    remote.seed(folderName, 'manuscript/scenes/scene-1.json', utf8.encode('{"text":"hi"}'));
  }

  group('findRestorableProjects', () {
    test('finds a Drive project folder with no local counterpart', () async {
      seedRemoteProject('Wandering Stars', title: 'Wandering Stars');

      final restorable = await findRestorableProjects(remote: remote, library: library);

      expect(restorable, hasLength(1));
      expect(restorable.single.folderName, 'Wandering Stars');
      expect(restorable.single.title, 'Wandering Stars');
    });

    test('shows the current title, not the stale creation-time folder name', () async {
      // Renamed after its first sync: LibraryService.renameProject never
      // touches the on-disk (and therefore Drive) folder name, only the
      // title inside project.json — see that method's own doc comment.
      seedRemoteProject('Untitled Project', title: 'Wisdom of the Elders');

      final restorable = await findRestorableProjects(remote: remote, library: library);

      expect(restorable.single.folderName, 'Untitled Project');
      expect(restorable.single.title, 'Wisdom of the Elders');
    });

    test('falls back to the folder name if project.json is missing', () async {
      remote.seed('No Project Json', 'stray-file.txt', utf8.encode('oops'));

      final restorable = await findRestorableProjects(remote: remote, library: library);

      expect(restorable.single.folderName, 'No Project Json');
      expect(restorable.single.title, 'No Project Json');
    });

    test('excludes a project already present locally', () async {
      seedRemoteProject('Already Local', title: 'Already Local');
      await library.createProject(title: 'Already Local');

      final restorable = await findRestorableProjects(remote: remote, library: library);

      expect(restorable, isEmpty);
    });

    test('excludes reserved underscore-prefixed folders like _Vault', () async {
      remote.seed('_Vault', 'backup.zip', utf8.encode('data'));

      final restorable = await findRestorableProjects(remote: remote, library: library);

      expect(restorable, isEmpty);
    });
  });

  group('restoreProjectFromDrive', () {
    test('pulls every remote file down into a new local project folder', () async {
      seedRemoteProject('Nightfall', title: 'Nightfall');

      final project = await restoreProjectFromDrive(
        folderName: 'Nightfall',
        library: library,
        syncService: syncService,
      );

      expect(project.title, 'Nightfall');
      expect(project.folderName, 'Nightfall');
      final sceneFile = File(
        p.join(libraryRoot.path, 'Nightfall', 'manuscript', 'scenes', 'scene-1.json'),
      );
      expect(await sceneFile.exists(), isTrue);

      final restored = await library.listProjects();
      expect(restored.map((p) => p.title), contains('Nightfall'));
    });

    test('cleans up and throws if the remote folder has no project.json', () async {
      remote.seed('Empty Folder', 'stray-file.txt', utf8.encode('oops'));

      expect(
        () => restoreProjectFromDrive(
          folderName: 'Empty Folder',
          library: library,
          syncService: syncService,
        ),
        throwsStateError,
      );

      final leftBehind = Directory(p.join(libraryRoot.path, 'Empty Folder'));
      expect(await leftBehind.exists(), isFalse);
    });
  });
}
