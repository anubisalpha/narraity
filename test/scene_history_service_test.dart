import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/scene_snapshot.dart';
import 'package:narraity/services/history_signing_key_manager.dart';
import 'package:narraity/services/scene_history_service.dart';

void main() {
  late Directory tempDir;
  late SceneHistoryService service;
  late HistorySigningKeyManager keyManager;
  const sceneId = 'scene-test-1';

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('narraity_history_test_');
    keyManager = HistorySigningKeyManager(
      saltFile: File('${tempDir.path}/_vault/salt'),
      verifierFile: File('${tempDir.path}/_vault/verifier'),
    );
    await keyManager.setup('test password');
    service = SceneHistoryService(tempDir, keyManager: keyManager);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a scene with no history has no snapshots', () async {
    expect(await service.listSnapshots(sceneId), isEmpty);
    expect(await service.reconstructContent(sceneId), '');
  });

  test('recordAutoSnapshot creates a snapshot and updates the latest cache', () async {
    await service.recordAutoSnapshot(sceneId, 'The story begins.');

    final snapshots = await service.listSnapshots(sceneId);
    expect(snapshots, hasLength(1));
    expect(snapshots.single.type, SnapshotType.auto);
    expect(snapshots.single.wordCount, 3);
    expect(await service.reconstructContent(sceneId), 'The story begins.');
  });

  test('recordAutoSnapshot is a no-op when content is unchanged', () async {
    await service.recordAutoSnapshot(sceneId, 'Same content.');
    await service.recordAutoSnapshot(sceneId, 'Same content.');

    expect(await service.listSnapshots(sceneId), hasLength(1));
  });

  test('successive auto snapshots chain correctly via patches', () async {
    await service.recordAutoSnapshot(sceneId, 'One.');
    await service.recordAutoSnapshot(sceneId, 'One. Two.');
    await service.recordAutoSnapshot(sceneId, 'One. Two. Three.');

    expect(await service.reconstructContent(sceneId), 'One. Two. Three.');
    expect(await service.listSnapshots(sceneId), hasLength(3));
  });

  test('recordCheckpoint stores a label and is retrievable', () async {
    await service.recordAutoSnapshot(sceneId, 'Draft one.');
    final checkpoint =
        await service.recordCheckpoint(sceneId, 'Draft one, finished.', 'First draft complete');

    final snapshots = await service.listSnapshots(sceneId);
    final saved = snapshots.firstWhere((s) => s.id == checkpoint.id);
    expect(saved.type, SnapshotType.checkpoint);
    expect(saved.label, 'First draft complete');
    expect(await service.reconstructContent(sceneId), 'Draft one, finished.');
  });

  test('reconstructContent(upToId) stops at that snapshot, not the latest', () async {
    await service.recordAutoSnapshot(sceneId, 'Version A');
    final middle = (await service.listSnapshots(sceneId)).single;
    await service.recordAutoSnapshot(sceneId, 'Version B');
    await service.recordAutoSnapshot(sceneId, 'Version C');

    expect(
      await service.reconstructContent(sceneId, upToId: middle.id),
      'Version A',
    );
  });

  test('restore returns old content and logs the restore as a new snapshot', () async {
    await service.recordAutoSnapshot(sceneId, 'Original text.');
    final original = (await service.listSnapshots(sceneId)).single;
    await service.recordAutoSnapshot(sceneId, 'Overwritten text.');

    final restored = await service.restore(sceneId, original.id);
    expect(restored, 'Original text.');

    // History now has 3 entries: original, overwrite, and the restore itself.
    final snapshots = await service.listSnapshots(sceneId);
    expect(snapshots, hasLength(3));
    expect(await service.reconstructContent(sceneId), 'Original text.');
    // Nothing was destroyed — the overwritten version is still reachable.
    final overwriteSnapshot = snapshots[1];
    expect(
      await service.reconstructContent(sceneId, upToId: overwriteSnapshot.id),
      'Overwritten text.',
    );
  });

  test('pruneAutoSnapshots removes old entries but reconstruction still works', () async {
    // Simulate history spanning weeks by writing snapshot files directly
    // with backdated timestamps (recordAutoSnapshot always uses "now").
    final now = DateTime.now();
    final texts = ['Alpha', 'Alpha Beta', 'Alpha Beta Gamma', 'Alpha Beta Gamma Delta'];
    var previous = '';
    for (var i = 0; i < texts.length; i++) {
      await service.recordAutoSnapshot(sceneId, texts[i]);
      previous = texts[i];
    }
    expect(previous, texts.last);

    // Backdate all snapshots to 40 days ago (same day) so pruning thins them
    // to "one per week" — but keep them on the same day so at most one
    // survives, proving the recompacted chain still reconstructs correctly.
    final snapshots = await service.listSnapshots(sceneId);
    final oldDate = now.subtract(const Duration(days: 40));
    final historyDir = '${tempDir.path}/manuscript/scenes/$sceneId.history';
    for (var i = 0; i < snapshots.length; i++) {
      final backdated = DateTime(oldDate.year, oldDate.month, oldDate.day, i);
      final rewritten = SceneSnapshot(
        timestamp: backdated,
        type: snapshots[i].type,
        label: snapshots[i].label,
        patchText: snapshots[i].patchText,
        wordCount: snapshots[i].wordCount,
      );
      // The id is derived from the timestamp, so backdating changes the
      // filename too — delete the old file and write under the new name.
      await File('$historyDir/${snapshots[i].id}.json').delete();
      await File('$historyDir/${rewritten.id}.json')
          .writeAsString(jsonEncode(rewritten.toJson()));
    }

    await service.pruneAutoSnapshots(sceneId);

    final afterPrune = await service.listSnapshots(sceneId);
    expect(afterPrune.length, lessThan(snapshots.length));
    // The critical invariant: even after pruning, the latest content is
    // still exactly reconstructable from the (recompacted) remaining chain.
    expect(await service.reconstructContent(sceneId), 'Alpha Beta Gamma Delta');
  });

  group('resignAll (password change)', () {
    String historyDirFor(String id) => '${tempDir.path}/manuscript/scenes/$id.history';

    Future<List<SnapshotVerification>> statusesFor(String id) async =>
        (await service.listWithStatus(id)).map((v) => v.status).toList();

    test('history verifies under the new key after re-signing', () async {
      await service.recordAutoSnapshot(sceneId, 'One.');
      await service.recordAutoSnapshot(sceneId, 'One. Two.');
      await service.recordCheckpoint(sceneId, 'One. Two. Three.', 'Milestone');

      final oldKey = await keyManager.deriveKeyFor('test password');
      final newKey = await keyManager.deriveKeyFor('a new password');
      await service.resignAll(oldKey: oldKey, newKey: newKey);
      await keyManager.rekey('a new password');

      expect(await statusesFor(sceneId), everyElement(SnapshotVerification.valid));
      expect(await service.reconstructContent(sceneId), 'One. Two. Three.');
    });

    test('the latest-signature cache is updated, so later snapshots still chain', () async {
      await service.recordAutoSnapshot(sceneId, 'Before.');

      final oldKey = await keyManager.deriveKeyFor('test password');
      final newKey = await keyManager.deriveKeyFor('a new password');
      await service.resignAll(oldKey: oldKey, newKey: newKey);
      await keyManager.rekey('a new password');

      await service.recordAutoSnapshot(sceneId, 'Before. After.');

      expect(await statusesFor(sceneId), everyElement(SnapshotVerification.valid));
      expect(await service.reconstructContent(sceneId), 'Before. After.');
    });

    test('every scene in the project is re-signed, not just one', () async {
      const otherScene = 'scene-test-2';
      await service.recordAutoSnapshot(sceneId, 'Scene one text.');
      await service.recordAutoSnapshot(otherScene, 'Scene two text.');

      final oldKey = await keyManager.deriveKeyFor('test password');
      final newKey = await keyManager.deriveKeyFor('a new password');
      await service.resignAll(oldKey: oldKey, newKey: newKey);
      await keyManager.rekey('a new password');

      expect(await service.scenesWithHistory(), containsAll([sceneId, otherScene]));
      expect(await statusesFor(sceneId), everyElement(SnapshotVerification.valid));
      expect(await statusesFor(otherScene), everyElement(SnapshotVerification.valid));
    });

    test('legacy unsigned entries are upgraded to signed', () async {
      // A service with no key manager writes unsigned history, exactly as the
      // app does when the vault has never been set up.
      final unsignedService = SceneHistoryService(tempDir);
      await unsignedService.recordAutoSnapshot(sceneId, 'Written before signing existed.');
      expect(await statusesFor(sceneId), [SnapshotVerification.legacyUnsigned]);

      final oldKey = await keyManager.deriveKeyFor('test password');
      final newKey = await keyManager.deriveKeyFor('a new password');
      await service.resignAll(oldKey: oldKey, newKey: newKey);
      await keyManager.rekey('a new password');

      expect(await statusesFor(sceneId), [SnapshotVerification.valid]);
      expect(await service.reconstructContent(sceneId), 'Written before signing existed.');
    });

    test('a tampered entry aborts the whole re-sign without writing anything', () async {
      await service.recordAutoSnapshot(sceneId, 'Genuine text.');
      await service.recordAutoSnapshot(sceneId, 'Genuine text, extended.');

      final snapshots = await service.listSnapshots(sceneId);
      final victim = File('${historyDirFor(sceneId)}/${snapshots.last.id}.json');
      final json = jsonDecode(await victim.readAsString()) as Map<String, dynamic>;
      json['wordCount'] = 9999; // signed field changed, signature left alone
      await victim.writeAsString(jsonEncode(json));

      final untouched = File('${historyDirFor(sceneId)}/${snapshots.first.id}.json');
      final before = await untouched.readAsString();

      final oldKey = await keyManager.deriveKeyFor('test password');
      final newKey = await keyManager.deriveKeyFor('a new password');

      await expectLater(
        service.resignAll(oldKey: oldKey, newKey: newKey),
        throwsA(isA<HistoryResignException>()),
      );
      expect(await untouched.readAsString(), before,
          reason: 'aborting must leave every entry exactly as it was');
    });

    test('verifyAllSignatures rejects a wrong key without touching disk', () async {
      await service.recordAutoSnapshot(sceneId, 'Genuine text.');
      final wrongKey = await keyManager.deriveKeyFor('not the real password');

      await expectLater(
        service.verifyAllSignatures(wrongKey),
        throwsA(isA<HistoryResignException>()),
      );
      expect(await statusesFor(sceneId), [SnapshotVerification.valid]);
    });
  });

  test('pruneAutoSnapshots never removes checkpoints', () async {
    await service.recordAutoSnapshot(sceneId, 'v1');
    final checkpoint = await service.recordCheckpoint(sceneId, 'v1 checkpoint', 'Milestone');

    final oldDate = DateTime.now().subtract(const Duration(days: 100));
    final snapshots = await service.listSnapshots(sceneId);
    final historyDir = '${tempDir.path}/manuscript/scenes/$sceneId.history';
    for (var i = 0; i < snapshots.length; i++) {
      final rewritten = SceneSnapshot(
        timestamp: oldDate.add(Duration(hours: i)), // distinct, still all old
        type: snapshots[i].type,
        label: snapshots[i].label,
        patchText: snapshots[i].patchText,
        wordCount: snapshots[i].wordCount,
      );
      await File('$historyDir/${snapshots[i].id}.json').delete();
      await File('$historyDir/${rewritten.id}.json')
          .writeAsString(jsonEncode(rewritten.toJson()));
    }

    await service.pruneAutoSnapshots(sceneId);

    final afterPrune = await service.listSnapshots(sceneId);
    expect(afterPrune.any((s) => s.label == checkpoint.label), isTrue);
  });
}
