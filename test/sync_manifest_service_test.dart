import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/sync_manifest.dart';
import 'package:narraity/services/sync_manifest_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory projectDir;
  late SyncManifestService service;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_sync_manifest_test_');
    service = SyncManifestService();
  });

  tearDown(() {
    projectDir.deleteSync(recursive: true);
  });

  test('read returns an empty manifest when none exists yet', () async {
    final manifest = await service.read(projectDir);
    expect(manifest.files, isEmpty);
  });

  test('write then read round-trips file entries and lastSyncTime', () async {
    final manifest = SyncManifest(
      files: {
        'manuscript/scenes/scene-1.json':
            const SyncFileEntry(localHash: 'h1', driveFileId: 'f1', driveMd5: 'm1'),
      },
      lastSyncTime: DateTime.utc(2026, 1, 1),
    );
    await service.write(projectDir, manifest);

    final reread = await service.read(projectDir);
    expect(reread.files.keys, ['manuscript/scenes/scene-1.json']);
    expect(reread.files['manuscript/scenes/scene-1.json']!.driveFileId, 'f1');
    expect(reread.lastSyncTime, DateTime.utc(2026, 1, 1));
  });

  test('a corrupt manifest file is treated as never-synced rather than throwing', () async {
    final manifestFile = File(p.join(projectDir.path, '.sync', 'manifest.json'));
    await manifestFile.parent.create(recursive: true);
    await manifestFile.writeAsString('not valid json{{{');

    final manifest = await service.read(projectDir);
    expect(manifest.files, isEmpty);
  });

  test('hashLocalFiles hashes ordinary files keyed by posix relative path', () async {
    final sceneFile = File(p.join(projectDir.path, 'manuscript', 'scenes', 'scene-1.json'));
    await sceneFile.parent.create(recursive: true);
    await sceneFile.writeAsString('hello');

    final hashes = await service.hashLocalFiles(projectDir);
    expect(hashes.keys, ['manuscript/scenes/scene-1.json']);
    // md5("hello") — a known value, so this also catches an accidental
    // switch to a different hash algorithm down the line.
    expect(hashes['manuscript/scenes/scene-1.json'], '5d41402abc4b2a76b9719d911017c592');
  });

  test('hashLocalFiles excludes .sync and .history_backup', () async {
    await File(p.join(projectDir.path, '.sync', 'manifest.json'))
        .create(recursive: true)
        .then((f) => f.writeAsString('{}'));
    final backupFile = File(
      p.join(projectDir.path, 'manuscript', 'scenes', '.history_backup', 'x', 'entry.json'),
    );
    await backupFile.parent.create(recursive: true);
    await backupFile.writeAsString('backup');

    final hashes = await service.hashLocalFiles(projectDir);
    expect(hashes, isEmpty);
  });

  test('hashLocalFiles returns empty for a nonexistent project directory', () async {
    final missing = Directory(p.join(projectDir.path, 'does-not-exist'));
    expect(await service.hashLocalFiles(missing), isEmpty);
  });
}
