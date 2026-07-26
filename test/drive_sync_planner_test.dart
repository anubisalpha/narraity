import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/sync_manifest.dart';
import 'package:narraity/services/drive_sync_planner.dart';

void main() {
  SyncManifest manifestWith(Map<String, (String local, String drive)> entries) => SyncManifest(
        files: entries.map(
          (path, hashes) => MapEntry(
            path,
            SyncFileEntry(localHash: hashes.$1, driveFileId: 'id-$path', driveMd5: hashes.$2),
          ),
        ),
      );

  test('new local-only file is uploaded', () {
    final plan = DriveSyncPlanner.plan(
      localHashes: {'scene.json': 'h1'},
      remoteFiles: {},
      manifest: SyncManifest.empty,
    );
    expect(plan.uploads, ['scene.json']);
    expect(plan.isEmpty, isFalse);
  });

  test('new remote-only file is downloaded', () {
    final plan = DriveSyncPlanner.plan(
      localHashes: {},
      remoteFiles: {'scene.json': const DriveRemoteFile(id: 'f1', md5: 'm1')},
      manifest: SyncManifest.empty,
    );
    expect(plan.downloads, ['scene.json']);
  });

  test('same path created independently on both sides (no manifest entry) is a conflict', () {
    final plan = DriveSyncPlanner.plan(
      localHashes: {'scene.json': 'h1'},
      remoteFiles: {'scene.json': const DriveRemoteFile(id: 'f1', md5: 'm1')},
      manifest: SyncManifest.empty,
    );
    expect(plan.conflicts, [const SyncConflict(path: 'scene.json', driveFileId: 'f1')]);
  });

  test('unchanged on both sides is a no-op', () {
    final manifest = manifestWith({'scene.json': ('h1', 'm1')});
    final plan = DriveSyncPlanner.plan(
      localHashes: {'scene.json': 'h1'},
      remoteFiles: {'scene.json': const DriveRemoteFile(id: 'f1', md5: 'm1')},
      manifest: manifest,
    );
    expect(plan.isEmpty, isTrue);
  });

  test('local edit, remote unchanged -> upload', () {
    final manifest = manifestWith({'scene.json': ('h1', 'm1')});
    final plan = DriveSyncPlanner.plan(
      localHashes: {'scene.json': 'h2'},
      remoteFiles: {'scene.json': const DriveRemoteFile(id: 'f1', md5: 'm1')},
      manifest: manifest,
    );
    expect(plan.uploads, ['scene.json']);
  });

  test('remote edit, local unchanged -> download', () {
    final manifest = manifestWith({'scene.json': ('h1', 'm1')});
    final plan = DriveSyncPlanner.plan(
      localHashes: {'scene.json': 'h1'},
      remoteFiles: {'scene.json': const DriveRemoteFile(id: 'f1', md5: 'm2')},
      manifest: manifest,
    );
    expect(plan.downloads, ['scene.json']);
  });

  test('local deleted, remote unchanged -> propagate delete to remote', () {
    final manifest = manifestWith({'scene.json': ('h1', 'm1')});
    final plan = DriveSyncPlanner.plan(
      localHashes: {},
      remoteFiles: {'scene.json': const DriveRemoteFile(id: 'f1', md5: 'm1')},
      manifest: manifest,
    );
    expect(plan.deleteRemote, ['scene.json']);
  });

  test('remote deleted, local unchanged -> propagate delete to local', () {
    final manifest = manifestWith({'scene.json': ('h1', 'm1')});
    final plan = DriveSyncPlanner.plan(
      localHashes: {'scene.json': 'h1'},
      remoteFiles: {},
      manifest: manifest,
    );
    expect(plan.deleteLocal, ['scene.json']);
  });

  test('both edited with diverging content -> conflict', () {
    final manifest = manifestWith({'scene.json': ('h1', 'm1')});
    final plan = DriveSyncPlanner.plan(
      localHashes: {'scene.json': 'h2'},
      remoteFiles: {'scene.json': const DriveRemoteFile(id: 'f1', md5: 'm2')},
      manifest: manifest,
    );
    expect(plan.conflicts, [const SyncConflict(path: 'scene.json', driveFileId: 'f1')]);
  });

  test('local deleted it, remote also edited -> restore locally (no ambiguity, not a conflict)', () {
    final manifest = manifestWith({'scene.json': ('h1', 'm1')});
    final plan = DriveSyncPlanner.plan(
      localHashes: {},
      remoteFiles: {'scene.json': const DriveRemoteFile(id: 'f1', md5: 'm2')},
      manifest: manifest,
    );
    expect(plan.downloads, ['scene.json']);
    expect(plan.conflicts, isEmpty);
  });

  test('remote deleted it, local also edited -> re-upload (no ambiguity, not a conflict)', () {
    final manifest = manifestWith({'scene.json': ('h1', 'm1')});
    final plan = DriveSyncPlanner.plan(
      localHashes: {'scene.json': 'h2'},
      remoteFiles: {},
      manifest: manifest,
    );
    expect(plan.uploads, ['scene.json']);
    expect(plan.conflicts, isEmpty);
  });

  test('deleted consistently on both sides -> just drops from the manifest', () {
    final manifest = manifestWith({'scene.json': ('h1', 'm1')});
    final plan = DriveSyncPlanner.plan(
      localHashes: {},
      remoteFiles: {},
      manifest: manifest,
    );
    expect(plan.manifestRemovals, ['scene.json']);
    expect(plan.uploads, isEmpty);
    expect(plan.downloads, isEmpty);
    expect(plan.deleteLocal, isEmpty);
    expect(plan.deleteRemote, isEmpty);
  });

  test('multiple independent files each get their own correct action', () {
    final manifest = manifestWith({
      'a.json': ('h1', 'm1'), // unchanged
      'b.json': ('h1', 'm1'), // local edited
      'c.json': ('h1', 'm1'), // remote edited
    });
    final plan = DriveSyncPlanner.plan(
      localHashes: {'a.json': 'h1', 'b.json': 'h2', 'c.json': 'h1', 'd.json': 'new'},
      remoteFiles: {
        'a.json': const DriveRemoteFile(id: 'a', md5: 'm1'),
        'b.json': const DriveRemoteFile(id: 'b', md5: 'm1'),
        'c.json': const DriveRemoteFile(id: 'c', md5: 'm2'),
      },
      manifest: manifest,
    );
    expect(plan.uploads, ['b.json', 'd.json']);
    expect(plan.downloads, ['c.json']);
  });
}
