import 'dart:convert';
import 'dart:io';

import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:path/path.dart' as p;

import '../models/scene_snapshot.dart';
import 'snapshot_pruner.dart';

/// Per-scene version history: auto snapshots on save, named checkpoints,
/// diff-based storage, and pruning (PLAN.md "Version History").
///
/// Each snapshot stores a `diff_match_patch` patch from the *previous kept
/// snapshot's* content to its own content — not a full copy. Reconstructing
/// any point in history means replaying the chain of patches from the start.
/// A `_latest.txt` cache (the materialized text as of the most recent
/// snapshot) avoids replaying the whole chain on every autosave check; it's
/// a derived cache, not part of the persisted history itself.
class SceneHistoryService {
  SceneHistoryService(this.projectDir);

  final Directory projectDir;
  final _dmp = DiffMatchPatch();

  Directory _historyDir(String sceneId) =>
      Directory(p.join(projectDir.path, 'manuscript', 'scenes', '$sceneId.history'));

  File _latestFile(String sceneId) =>
      File(p.join(_historyDir(sceneId).path, '_latest.txt'));

  int _wordCount(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    return (words.length == 1 && words.first.isEmpty) ? 0 : words.length;
  }

  Future<List<SceneSnapshot>> listSnapshots(String sceneId) async {
    final dir = _historyDir(sceneId);
    if (!await dir.exists()) return [];

    final snapshots = <SceneSnapshot>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        snapshots.add(SceneSnapshot.fromJson(json));
      } catch (_) {
        continue; // skip corrupt entries rather than breaking the whole list
      }
    }
    snapshots.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return snapshots;
  }

  /// Replays the patch chain to reconstruct the scene's text as of
  /// [upToId] (inclusive), or the latest snapshot if null.
  Future<String> reconstructContent(String sceneId, {String? upToId}) async {
    final snapshots = await listSnapshots(sceneId);
    var text = '';
    for (final snapshot in snapshots) {
      final patches = patchFromText(snapshot.patchText);
      final result = _dmp.patch_apply(patches, text);
      text = result[0] as String;
      if (upToId != null && snapshot.id == upToId) break;
    }
    return text;
  }

  Future<String> _latestKnownContent(String sceneId) async {
    final file = _latestFile(sceneId);
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  Future<void> _writeSnapshot(String sceneId, SceneSnapshot snapshot) async {
    final dir = _historyDir(sceneId);
    await dir.create(recursive: true);
    await File(p.join(dir.path, '${snapshot.id}.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(snapshot.toJson()));
  }

  /// Records an auto snapshot if [currentContent] differs from the last
  /// known content — a no-op otherwise, so idle saves don't create empty
  /// history entries. Call from the editor's save-debounce path (PLAN.md:
  /// "~30s of no typing, or ~300 words changed, whichever first").
  Future<void> recordAutoSnapshot(String sceneId, String currentContent) async {
    final latest = await _latestKnownContent(sceneId);
    if (latest == currentContent) return;

    final patches = _dmp.patch(latest, currentContent);
    final snapshot = SceneSnapshot(
      timestamp: DateTime.now(),
      type: SnapshotType.auto,
      patchText: patchToText(patches),
      wordCount: _wordCount(currentContent),
    );
    await _writeSnapshot(sceneId, snapshot);
    await _latestFile(sceneId).writeAsString(currentContent);
  }

  /// Manual "Save checkpoint" — always records, even if nothing changed
  /// since the last snapshot, since the point is marking a milestone.
  Future<SceneSnapshot> recordCheckpoint(
    String sceneId,
    String currentContent,
    String label,
  ) async {
    final latest = await _latestKnownContent(sceneId);
    final patches = _dmp.patch(latest, currentContent);
    final snapshot = SceneSnapshot(
      timestamp: DateTime.now(),
      type: SnapshotType.checkpoint,
      label: label,
      patchText: patchToText(patches),
      wordCount: _wordCount(currentContent),
    );
    await _writeSnapshot(sceneId, snapshot);
    await _latestFile(sceneId).writeAsString(currentContent);
    return snapshot;
  }

  /// Restores the scene to [snapshotId]'s content. Rather than overwriting
  /// history, this records the transition as a new snapshot (so the restore
  /// itself shows up in the timeline and is itself undoable — PLAN.md).
  /// Returns the restored text for the caller to load into the editor.
  Future<String> restore(String sceneId, String snapshotId) async {
    final targetContent = await reconstructContent(sceneId, upToId: snapshotId);
    await recordAutoSnapshot(sceneId, targetContent);
    return targetContent;
  }

  /// Thins old auto-snapshots per PLAN.md's pruning policy (see
  /// SnapshotPruner), preserving checkpoints and chain integrity: rather
  /// than deleting a snapshot outright (which would break replay for
  /// everything after it), kept snapshots' patches are recomputed against
  /// the *new* previous-kept-snapshot so the chain still reconstructs
  /// correctly with the pruned entries gone.
  Future<void> pruneAutoSnapshots(String sceneId) async {
    final snapshots = await listSnapshots(sceneId);
    if (snapshots.isEmpty) return;

    final autoTimestamps =
        snapshots.where((s) => s.type == SnapshotType.auto).map((s) => s.timestamp).toList();
    final keepTimestamps = SnapshotPruner.selectToKeep(autoTimestamps, DateTime.now());

    // Reconstruct full text at every existing snapshot in one pass.
    final contentById = <String, String>{};
    var replay = '';
    for (final snapshot in snapshots) {
      final patches = patchFromText(snapshot.patchText);
      replay = _dmp.patch_apply(patches, replay)[0] as String;
      contentById[snapshot.id] = replay;
    }

    final kept = snapshots
        .where((s) => s.type == SnapshotType.checkpoint || keepTimestamps.contains(s.timestamp))
        .toList();
    final pruned = snapshots.where((s) => !kept.contains(s)).toList();

    var previousContent = '';
    for (final snapshot in kept) {
      final content = contentById[snapshot.id]!;
      final patches = _dmp.patch(previousContent, content);
      final recomputed = SceneSnapshot(
        timestamp: snapshot.timestamp,
        type: snapshot.type,
        label: snapshot.label,
        patchText: patchToText(patches),
        wordCount: snapshot.wordCount,
      );
      await _writeSnapshot(sceneId, recomputed);
      previousContent = content;
    }

    final dir = _historyDir(sceneId);
    for (final snapshot in pruned) {
      final file = File(p.join(dir.path, '${snapshot.id}.json'));
      if (await file.exists()) await file.delete();
    }
  }
}
