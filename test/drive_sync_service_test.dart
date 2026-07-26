import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/drive_sync_service.dart';
import 'package:path/path.dart' as p;

import 'fake_drive_remote_store.dart';

void main() {
  late Directory projectDir;
  late FakeDriveRemoteStore remote;
  late DriveSyncService service;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_drive_sync_test_');
    remote = FakeDriveRemoteStore();
    service = DriveSyncService(remoteStore: remote, deviceName: 'test-device');
  });

  tearDown(() {
    projectDir.deleteSync(recursive: true);
  });

  Future<File> writeLocal(String relativePath, String content) async {
    final file = File(p.joinAll([projectDir.path, ...p.posix.split(relativePath)]));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  test('a new local file is uploaded to Drive', () async {
    await writeLocal('manuscript/scenes/scene-1.json', 'hello');

    final result = await service.sync(projectDir, 'MyNovel');

    expect(result.uploaded, ['manuscript/scenes/scene-1.json']);
    final remoteFiles = await remote.listFiles('MyNovel');
    expect(remoteFiles.keys, contains('manuscript/scenes/scene-1.json'));
  });

  test('a new remote-only file is downloaded to disk', () async {
    remote.seed('MyNovel', 'manuscript/scenes/scene-1.json', 'from drive'.codeUnits);

    final result = await service.sync(projectDir, 'MyNovel');

    expect(result.downloaded, ['manuscript/scenes/scene-1.json']);
    final file = File(p.join(projectDir.path, 'manuscript', 'scenes', 'scene-1.json'));
    expect(await file.readAsString(), 'from drive');
  });

  test('syncing twice with no changes is a no-op the second time', () async {
    await writeLocal('todos/todos.json', '{"todos":[]}');
    await service.sync(projectDir, 'MyNovel');

    final second = await service.sync(projectDir, 'MyNovel');

    expect(second.uploaded, isEmpty);
    expect(second.downloaded, isEmpty);
    expect(second.conflicts, isEmpty);
  });

  test('editing a local file after a first sync uploads the update, not a duplicate', () async {
    await writeLocal('todos/todos.json', 'v1');
    await service.sync(projectDir, 'MyNovel');

    await writeLocal('todos/todos.json', 'v2');
    final result = await service.sync(projectDir, 'MyNovel');

    expect(result.uploaded, ['todos/todos.json']);
    final remoteFiles = await remote.listFiles('MyNovel');
    expect(remoteFiles.length, 1); // updated in place, not a second file
    expect(await remote.download(remoteFiles['todos/todos.json']!.id), 'v2'.codeUnits);
  });

  test('deleting a local file after a first sync propagates the delete to Drive', () async {
    final file = await writeLocal('todos/todos.json', 'v1');
    await service.sync(projectDir, 'MyNovel');

    await file.delete();
    await service.sync(projectDir, 'MyNovel');

    final remoteFiles = await remote.listFiles('MyNovel');
    expect(remoteFiles, isEmpty);
  });

  test('a genuine conflict is reported and left untouched on both sides', () async {
    await writeLocal('todos/todos.json', 'v1');
    await service.sync(projectDir, 'MyNovel');

    await writeLocal('todos/todos.json', 'local-edit');
    remote.seed('MyNovel', 'todos/todos.json', 'remote-edit'.codeUnits);
    // Re-seeding overwrote the manifest's known remote entry's file id in
    // the fake, matching "someone else edited it on Drive" — but the local
    // file on disk also changed, so this is the both-sides-changed case.

    final result = await service.sync(projectDir, 'MyNovel');

    expect(result.conflicts, hasLength(1));
    expect(result.conflicts.first.path, 'todos/todos.json');
    // Neither side was overwritten by the sync itself.
    final file = File(p.join(projectDir.path, 'todos', 'todos.json'));
    expect(await file.readAsString(), 'local-edit');
  });

  test('saveConflictCopy preserves the local content under a .conflict- name', () async {
    await writeLocal('todos/todos.json', 'local-edit');

    final copy = await service.saveConflictCopy(projectDir, 'todos/todos.json');

    expect(p.basename(copy.path), startsWith('todos.conflict-test-device-'));
    expect(await copy.readAsString(), 'local-edit');
  });

  test('resolveKeepRemote overwrites the local file with Drive\'s content', () async {
    await writeLocal('todos/todos.json', 'local-edit');
    remote.seed('MyNovel', 'todos/todos.json', 'remote-edit'.codeUnits);

    await service.resolveKeepRemote(projectDir, 'MyNovel', 'todos/todos.json');

    final file = File(p.join(projectDir.path, 'todos', 'todos.json'));
    expect(await file.readAsString(), 'remote-edit');
  });

  test('resolveKeepLocal uploads the local file over Drive\'s diverging copy', () async {
    await writeLocal('todos/todos.json', 'local-edit');
    remote.seed('MyNovel', 'todos/todos.json', 'remote-edit'.codeUnits);

    await service.resolveKeepLocal(projectDir, 'MyNovel', 'todos/todos.json');

    final remoteFiles = await remote.listFiles('MyNovel');
    final bytes = await remote.download(remoteFiles['todos/todos.json']!.id);
    expect(String.fromCharCodes(bytes), 'local-edit');
  });

  group('syncSingleFile', () {
    test('uploads just the one changed file', () async {
      await writeLocal('manuscript/scenes/scene-1.json', 'hello');

      final result = await service.syncSingleFile(
        projectDir,
        'MyNovel',
        'manuscript/scenes/scene-1.json',
      );

      expect(result.uploaded, ['manuscript/scenes/scene-1.json']);
      final remoteFiles = await remote.listFiles('MyNovel');
      expect(remoteFiles.keys, contains('manuscript/scenes/scene-1.json'));
    });

    test('does not touch or remove unrelated manifest entries', () async {
      // A full sync establishes two tracked files first.
      await writeLocal('todos/todos.json', 'v1');
      await writeLocal('goals/goals.json', 'g1');
      await service.sync(projectDir, 'MyNovel');

      // Now only one of them changes, synced individually.
      await writeLocal('todos/todos.json', 'v2');
      final result = await service.syncSingleFile(projectDir, 'MyNovel', 'todos/todos.json');

      expect(result.uploaded, ['todos/todos.json']);
      // The untouched file must still be on Drive, not treated as deleted —
      // this is exactly the bug a naive "pass the whole manifest" approach
      // would cause (every other tracked path would look deleted on both
      // sides, since only one path's local hash/remote listing was fetched).
      final remoteFiles = await remote.listFiles('MyNovel');
      expect(remoteFiles.keys, containsAll(['todos/todos.json', 'goals/goals.json']));
    });

    test('a second syncSingleFile call for an unchanged file is a no-op', () async {
      await writeLocal('todos/todos.json', 'v1');
      await service.syncSingleFile(projectDir, 'MyNovel', 'todos/todos.json');

      final result = await service.syncSingleFile(projectDir, 'MyNovel', 'todos/todos.json');

      expect(result.uploaded, isEmpty);
      expect(result.downloaded, isEmpty);
    });

    test('downloads a Drive-only file when synced individually', () async {
      remote.seed('MyNovel', 'todos/todos.json', 'from drive'.codeUnits);

      final result = await service.syncSingleFile(projectDir, 'MyNovel', 'todos/todos.json');

      expect(result.downloaded, ['todos/todos.json']);
      final file = File(p.join(projectDir.path, 'todos', 'todos.json'));
      expect(await file.readAsString(), 'from drive');
    });

    test('a genuine conflict on the single file is reported, others untouched', () async {
      await writeLocal('todos/todos.json', 'v1');
      await writeLocal('goals/goals.json', 'g1');
      await service.sync(projectDir, 'MyNovel');

      await writeLocal('todos/todos.json', 'local-edit');
      remote.seed('MyNovel', 'todos/todos.json', 'remote-edit'.codeUnits);

      final result = await service.syncSingleFile(projectDir, 'MyNovel', 'todos/todos.json');

      expect(result.conflicts, hasLength(1));
      expect(result.conflicts.first.path, 'todos/todos.json');
      final remoteFiles = await remote.listFiles('MyNovel');
      expect(remoteFiles.keys, contains('goals/goals.json')); // unrelated file survives
    });
  });
}
