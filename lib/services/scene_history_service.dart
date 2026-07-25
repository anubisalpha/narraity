import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:path/path.dart' as p;

import '../models/scene_snapshot.dart';
import 'history_signing_key_manager.dart';
import 'snapshot_pruner.dart';

/// Per-scene version history: auto snapshots on save, named checkpoints,
/// diff-based storage, pruning, and tamper-evidence (PLAN.md "Version
/// History").
///
/// Each snapshot stores a `diff_match_patch` patch from the *previous kept
/// snapshot's* content to its own content — not a full copy. Reconstructing
/// any point in history means replaying the chain of patches from the start.
/// A `_latest.txt` cache (the materialized text as of the most recent
/// snapshot) avoids replaying the whole chain on every autosave check; it's
/// a derived cache, not part of the persisted history itself.
///
/// Tamper-evidence: every snapshot is HMAC-signed, chained to the previous
/// snapshot's signature, with the key derived from the user's vault
/// password (see HistorySigningKeyManager) — never stored in this folder,
/// or anywhere on disk at all. On read, any entry whose signature doesn't
/// match — or whose claimed link to the previous entry is wrong — is
/// treated as tampered: it's excluded from what callers see and
/// reconstruction, and quarantined on disk (renamed `.tampered`) rather than
/// silently trusted or deleted. Snapshots written before signing existed,
/// or written while no vault password was unlocked, have no `signature`
/// field and are treated as legacy-unsigned, not tampered.
///
/// Corruption resilience: the same signature check also catches ordinary
/// corruption (a truncated write, a bad sync merge, disk bit-rot) — any of
/// those flip bytes just as surely as a deliberate edit would. Every
/// snapshot (and the `_latest.txt`/`_latest.sig` caches) is mirrored to an
/// independent `.history_backup/` folder at write time. When a verification
/// failure is found on read, the mirror is checked before giving up: if the
/// backup copy verifies cleanly, the primary is repaired from it in place
/// and the entry is trusted normally; only if the backup is *also* bad does
/// the entry get quarantined and flagged. This doesn't survive the whole
/// project folder being destroyed at once, but it recovers from the much
/// more common case of a single damaged file.
class SceneHistoryService {
  /// [keyManager] is optional — with none supplied, or with one that hasn't
  /// had [HistorySigningKeyManager.unlock] called, every snapshot is written
  /// and read as legacy-unsigned (trusted, unverifiable), same as before
  /// tamper-evidence existed.
  SceneHistoryService(this.projectDir, {HistorySigningKeyManager? keyManager})
      : _keyManager = keyManager;

  final Directory projectDir;
  final HistorySigningKeyManager? _keyManager;
  final _dmp = DiffMatchPatch();

  /// Ids quarantined on the most recent [listSnapshots]/[listWithStatus]
  /// call for each scene, so UI can show a "these were tampered" banner
  /// without a second scan.
  final _lastTamperedByScene = <String, List<String>>{};

  Directory _historyDir(String sceneId) =>
      Directory(p.join(projectDir.path, 'manuscript', 'scenes', '$sceneId.history'));

  /// Independent mirror of every file in [_historyDir] — a different folder
  /// so a single bad write (truncated save, botched sync merge) touching
  /// one location has no mechanical reason to also touch the other.
  Directory _backupDir(String sceneId) => Directory(
        p.join(projectDir.path, 'manuscript', 'scenes', '.history_backup', sceneId),
      );

  File _latestFile(String sceneId) => File(p.join(_historyDir(sceneId).path, '_latest.txt'));

  File _latestSignatureFile(String sceneId) =>
      File(p.join(_historyDir(sceneId).path, '_latest.sig'));

  File _backupSnapshotFile(String sceneId, String id) =>
      File(p.join(_backupDir(sceneId).path, '$id.json'));

  File _backupLatestFile(String sceneId) => File(p.join(_backupDir(sceneId).path, '_latest.txt'));

  File _backupLatestSignatureFile(String sceneId) =>
      File(p.join(_backupDir(sceneId).path, '_latest.sig'));

  /// Writes [contents] to [primary], mirroring the same bytes to [backup].
  /// The mirror write happens after the primary succeeds so a failure
  /// mid-write never leaves the backup looking more "current" than reality.
  Future<void> _writeMirrored(File primary, File backup, String contents) async {
    await primary.parent.create(recursive: true);
    await primary.writeAsString(contents);
    await backup.parent.create(recursive: true);
    await backup.writeAsString(contents);
  }

  int _wordCount(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    return (words.length == 1 && words.first.isEmpty) ? 0 : words.length;
  }

  /// Signs [payload] with the current key, or returns null if no vault
  /// password is unlocked right now — callers treat null as "write/verify
  /// this as legacy-unsigned" rather than an error.
  String? _sign(String payload) {
    final key = _keyManager?.currentKey;
    if (key == null) return null;
    return Hmac(sha256, key).convert(utf8.encode(payload)).toString();
  }

  /// Ids quarantined the last time this scene's history was listed.
  List<String> tamperedIdsFor(String sceneId) => _lastTamperedByScene[sceneId] ?? const [];

  /// All snapshots that pass verification (valid or legacy-unsigned),
  /// oldest first. Tampered entries are silently excluded here — use
  /// [listWithStatus] or [tamperedIdsFor] if the caller needs to know about
  /// them.
  Future<List<SceneSnapshot>> listSnapshots(String sceneId) async {
    final verified = await listWithStatus(sceneId);
    return verified
        .where((v) => v.status != SnapshotVerification.tampered)
        .map((v) => v.snapshot)
        .toList();
  }

  /// Same as [listSnapshots] but with each entry's verification outcome
  /// attached, and tampered files quarantined (renamed `.tampered`) as a
  /// side effect so they stop being read as history on subsequent calls.
  Future<List<VerifiedSnapshot>> listWithStatus(String sceneId) async {
    final dir = _historyDir(sceneId);
    if (!await dir.exists()) {
      _lastTamperedByScene.remove(sceneId);
      return [];
    }

    final entries = <(File, SceneSnapshot)>[];
    final unrecoverableIds = <String>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;

      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        entries.add((entity, SceneSnapshot.fromJson(json)));
        continue;
      } catch (_) {
        // Primary is corrupted badly enough it isn't even valid JSON — try
        // the backup mirror before giving up on this entry entirely, so a
        // fully mangled file still gets a chance at recovery, not just a
        // "signature mismatch" one.
      }

      final id = p.basenameWithoutExtension(entity.path);
      final backup = _backupSnapshotFile(sceneId, id);
      try {
        final json = jsonDecode(await backup.readAsString()) as Map<String, dynamic>;
        final recovered = SceneSnapshot.fromJson(json);
        await entity.writeAsString(await backup.readAsString());
        entries.add((entity, recovered));
      } catch (_) {
        unrecoverableIds.add(id); // both copies unreadable — genuinely lost
      }
    }
    entries.sort((a, b) => a.$2.timestamp.compareTo(b.$2.timestamp));

    final result = <VerifiedSnapshot>[];
    final tamperedIds = <String>[];
    var expectedPrev = '';

    for (final (file, snapshot) in entries) {
      if (snapshot.signature == null) {
        // Predates signing entirely — nothing to check, chain expectation
        // doesn't move (the next signed entry should still link to
        // whatever the last *signed* entry's signature was, or '' if none
        // yet).
        result.add(VerifiedSnapshot(snapshot, SnapshotVerification.legacyUnsigned));
        continue;
      }

      if (_keyManager?.currentKey == null) {
        // Genuinely signed, but nothing can check it without the vault
        // password unlocked this session — trust it rather than treat
        // "nobody's typed the password yet" as evidence of tampering.
        result.add(VerifiedSnapshot(snapshot, SnapshotVerification.locked));
        continue;
      }

      final expectedSignature = _sign(snapshot.canonicalPayload());
      final ok = snapshot.prevSignature == expectedPrev && snapshot.signature == expectedSignature;

      if (ok) {
        result.add(VerifiedSnapshot(snapshot, SnapshotVerification.valid));
        expectedPrev = snapshot.signature!;
        continue;
      }

      // Verification failed — this covers both deliberate tampering and
      // ordinary corruption (a flipped byte breaks the signature check
      // either way). Before giving up, check whether the independent backup
      // mirror still has a good copy of this exact entry.
      final repaired = await _tryRepairFromBackup(sceneId, file, snapshot.id, expectedPrev);
      if (repaired != null) {
        result.add(VerifiedSnapshot(repaired, SnapshotVerification.valid));
        expectedPrev = repaired.signature!;
        continue;
      }

      result.add(VerifiedSnapshot(snapshot, SnapshotVerification.tampered));
      tamperedIds.add(snapshot.id);
      await _quarantine(file);
      // Deliberately leave expectedPrev where it was: everything after a
      // broken link fails the same check for the same reason, and gets
      // quarantined too, rather than us guessing which side of a break is
      // the "real" one.
    }

    final allFlaggedIds = [...tamperedIds, ...unrecoverableIds];
    if (allFlaggedIds.isEmpty) {
      _lastTamperedByScene.remove(sceneId);
    } else {
      _lastTamperedByScene[sceneId] = allFlaggedIds;
    }
    return result;
  }

  /// If the backup mirror holds a copy of snapshot [id] that verifies
  /// cleanly against [expectedPrev], repairs the primary [corruptFile] in
  /// place from that copy and returns the restored, verified snapshot.
  /// Returns null if there's no usable backup (missing, unreadable, or it
  /// fails verification too) — in which case the caller quarantines as
  /// usual.
  Future<SceneSnapshot?> _tryRepairFromBackup(
    String sceneId,
    File corruptFile,
    String id,
    String expectedPrev,
  ) async {
    final backupFile = _backupSnapshotFile(sceneId, id);
    if (!await backupFile.exists()) return null;

    final SceneSnapshot backupSnapshot;
    try {
      final json = jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      backupSnapshot = SceneSnapshot.fromJson(json);
    } catch (_) {
      return null;
    }

    if (backupSnapshot.signature == null) return null; // nothing to verify against
    if (_keyManager?.currentKey == null) return null; // can't verify without the key either
    final expectedSignature = _sign(backupSnapshot.canonicalPayload());
    final ok = backupSnapshot.prevSignature == expectedPrev &&
        backupSnapshot.signature == expectedSignature;
    if (!ok) return null;

    try {
      await corruptFile.writeAsString(await backupFile.readAsString());
    } catch (_) {
      // Repair-in-place failed (e.g. permissions) — the backup is still
      // good, so trust it for this read even though the primary stays bad.
    }
    return backupSnapshot;
  }

  Future<void> _quarantine(File file) async {
    try {
      final quarantined = File('${file.path}.tampered');
      if (await quarantined.exists()) await quarantined.delete();
      await file.rename(quarantined.path);
    } catch (_) {
      // Best-effort — if the rename fails, verification still excludes it
      // from trusted results every time it's re-read.
    }
  }

  /// Replays the patch chain to reconstruct the scene's text as of
  /// [upToId] (inclusive), or the latest snapshot if null. Only trusted
  /// (non-tampered) snapshots are replayed.
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

  /// Reads [primary], falling back to [backup] if the primary is missing or
  /// unreadable (a truncated/corrupted cache file) — these caches aren't
  /// signed individually, so "unreadable" is the only corruption signal
  /// available for them; a readable-but-wrong primary can't be distinguished
  /// from a correct one this way. That's an acceptable gap for a cache that
  /// full history verification doesn't depend on for correctness, only for
  /// avoiding a full chain replay on every save.
  Future<String?> _readWithFallback(File primary, File backup) async {
    if (await primary.exists()) {
      try {
        return await primary.readAsString();
      } catch (_) {
        // fall through to backup
      }
    }
    if (await backup.exists()) {
      try {
        return await backup.readAsString();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<String> _latestKnownContent(String sceneId) async {
    final content =
        await _readWithFallback(_latestFile(sceneId), _backupLatestFile(sceneId));
    return content ?? '';
  }

  Future<String> _latestKnownSignature(String sceneId) async {
    final content = await _readWithFallback(
      _latestSignatureFile(sceneId),
      _backupLatestSignatureFile(sceneId),
    );
    return content?.trim() ?? '';
  }

  Future<void> _writeSnapshot(String sceneId, SceneSnapshot unsigned) async {
    final dir = _historyDir(sceneId);
    await dir.create(recursive: true);

    SceneSnapshot toWrite = unsigned;
    String? signature;
    if (_keyManager?.currentKey != null) {
      final prevSignature = await _latestKnownSignature(sceneId);
      final withPrev = unsigned.copyWith(prevSignature: prevSignature);
      signature = _sign(withPrev.canonicalPayload());
      toWrite = withPrev.copyWith(signature: signature);
    }
    // If no key is available, toWrite stays unsigned (signature: null,
    // prevSignature: '') — written and read back as legacy-unsigned.

    final jsonText = const JsonEncoder.withIndent('  ').convert(toWrite.toJson());
    await _writeMirrored(
      File(p.join(dir.path, '${toWrite.id}.json')),
      _backupSnapshotFile(sceneId, toWrite.id),
      jsonText,
    );
    if (signature != null) {
      await _writeMirrored(
        _latestSignatureFile(sceneId),
        _backupLatestSignatureFile(sceneId),
        signature,
      );
    }
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
    await _writeMirrored(_latestFile(sceneId), _backupLatestFile(sceneId), currentContent);
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
    await _writeMirrored(_latestFile(sceneId), _backupLatestFile(sceneId), currentContent);
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
  /// everything after it), kept snapshots' patches — and signatures — are
  /// recomputed against the new previous-kept-snapshot so the chain still
  /// reconstructs and verifies correctly with the pruned entries gone.
  /// Tampered entries are left untouched here; they're already quarantined
  /// out of the trusted chain by [listWithStatus].
  Future<void> pruneAutoSnapshots(String sceneId) async {
    final snapshots = await listSnapshots(sceneId);
    if (snapshots.isEmpty) return;

    if (snapshots.any((s) => s.signature != null) && _keyManager?.currentKey == null) {
      // At least one entry is genuinely signed, but there's no key to
      // recompute signatures with right now. Pruning has to rewrite every
      // kept entry's patch (and therefore its signature) against the new
      // previous-content baseline — doing that without the key would mean
      // silently downgrading real signed history to unsigned. Skip this
      // run entirely; it'll succeed next time the vault is unlocked.
      return;
    }

    final autoTimestamps =
        snapshots.where((s) => s.type == SnapshotType.auto).map((s) => s.timestamp).toList();
    final keepTimestamps = SnapshotPruner.selectToKeep(autoTimestamps, DateTime.now());

    // Reconstruct full text at every existing (trusted) snapshot in one pass.
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
    var previousSignature = '';
    for (final snapshot in kept) {
      final content = contentById[snapshot.id]!;
      final patches = _dmp.patch(previousContent, content);
      final unsigned = SceneSnapshot(
        timestamp: snapshot.timestamp,
        type: snapshot.type,
        label: snapshot.label,
        patchText: patchToText(patches),
        wordCount: snapshot.wordCount,
        prevSignature: previousSignature,
      );
      final signature = _sign(unsigned.canonicalPayload());
      final signed = signature == null ? unsigned : unsigned.copyWith(signature: signature);
      final jsonText = const JsonEncoder.withIndent('  ').convert(signed.toJson());

      await _writeMirrored(
        File(p.join(_historyDir(sceneId).path, '${signed.id}.json')),
        _backupSnapshotFile(sceneId, signed.id),
        jsonText,
      );

      previousContent = content;
      previousSignature = signature ?? '';
    }
    await _writeMirrored(
      _latestSignatureFile(sceneId),
      _backupLatestSignatureFile(sceneId),
      previousSignature,
    );

    final dir = _historyDir(sceneId);
    for (final snapshot in pruned) {
      final file = File(p.join(dir.path, '${snapshot.id}.json'));
      if (await file.exists()) await file.delete();
      final backup = _backupSnapshotFile(sceneId, snapshot.id);
      if (await backup.exists()) await backup.delete();
    }
  }
}
