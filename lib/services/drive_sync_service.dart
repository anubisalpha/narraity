import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/sync_manifest.dart';
import 'drive_remote_store.dart';
import 'drive_sync_planner.dart';
import 'sync_manifest_service.dart';

/// One project's sync run: what got pushed/pulled, and any conflicts left
/// for the user to resolve via the dedicated conflict screen.
class SyncResult {
  const SyncResult({
    required this.uploaded,
    required this.downloaded,
    required this.deletedLocal,
    required this.deletedRemote,
    required this.conflicts,
  });

  final List<String> uploaded;
  final List<String> downloaded;
  final List<String> deletedLocal;
  final List<String> deletedRemote;
  final List<SyncConflict> conflicts;
}

/// Runs one project's PLAN.md-described sync cycle: diff local vs. Drive
/// against the last-known-synced manifest, then apply the resulting plan.
/// Offline-first — every scene save is already local and immediate; this is
/// only ever invoked for the best-effort "Sync now" action or an
/// on-foreground background check, never on the write path itself.
class DriveSyncService {
  DriveSyncService({
    required DriveRemoteStore remoteStore,
    SyncManifestService? manifestService,
    String? deviceName,
  })  : _remote = remoteStore,
        _manifests = manifestService ?? SyncManifestService(),
        _deviceName = deviceName ?? Platform.localHostname;

  final DriveRemoteStore _remote;
  final SyncManifestService _manifests;
  final String _deviceName;

  /// Runs a full sync cycle for one project. [projectDir] is the local
  /// project folder; [projectFolderName] identifies its mirror on Drive
  /// (same folder name, per PLAN.md — Drive has no separate id concept for
  /// this app to track beyond that).
  Future<SyncResult> sync(Directory projectDir, String projectFolderName) async {
    final manifest = await _manifests.read(projectDir);
    final localHashes = await _manifests.hashLocalFiles(projectDir);
    final remoteFiles = await _remote.listFiles(projectFolderName);

    final plan = DriveSyncPlanner.plan(
      localHashes: localHashes,
      remoteFiles: remoteFiles,
      manifest: manifest,
    );

    final updatedFiles = await _applyPlan(
      projectDir: projectDir,
      projectFolderName: projectFolderName,
      plan: plan,
      remoteFiles: remoteFiles,
      baseFiles: manifest.files,
    );

    await _manifests.write(
      projectDir,
      manifest.copyWith(files: updatedFiles, lastSyncTime: DateTime.now()),
    );

    return SyncResult(
      uploaded: plan.uploads,
      downloaded: plan.downloads,
      deletedLocal: plan.deleteLocal,
      deletedRemote: plan.deleteRemote,
      conflicts: plan.conflicts,
    );
  }

  /// Syncs just one file — the whole point of an "immediately after saving"
  /// trigger: a project with thousands of files shouldn't need a full
  /// listing/hashing pass every time a single scene autosaves. Diffs
  /// [relativePath] alone against a manifest scoped down to that one entry
  /// (so the shared [DriveSyncPlanner] logic sees only this path, not every
  /// other tracked file — feeding it the *whole* manifest here would make
  /// every other file look deleted-on-both-sides), then merges whatever
  /// changed back into the real manifest.
  Future<SyncResult> syncSingleFile(
    Directory projectDir,
    String projectFolderName,
    String relativePath,
  ) async {
    final manifest = await _manifests.read(projectDir);

    final file = File(p.joinAll([projectDir.path, ...p.posix.split(relativePath)]));
    final localHashes = <String, String>{};
    if (await file.exists()) {
      localHashes[relativePath] = md5.convert(await file.readAsBytes()).toString();
    }

    final remote = await _remote.findFile(
      projectFolderName: projectFolderName,
      relativePath: relativePath,
    );
    final remoteFiles = <String, DriveRemoteFile>{if (remote != null) relativePath: remote};

    final existingEntry = manifest.files[relativePath];
    final scopedFiles = <String, SyncFileEntry>{if (existingEntry != null) relativePath: existingEntry};
    final scopedManifest = SyncManifest(files: scopedFiles);

    final plan = DriveSyncPlanner.plan(
      localHashes: localHashes,
      remoteFiles: remoteFiles,
      manifest: scopedManifest,
    );

    final updatedScoped = await _applyPlan(
      projectDir: projectDir,
      projectFolderName: projectFolderName,
      plan: plan,
      remoteFiles: remoteFiles,
      baseFiles: scopedFiles,
    );

    final mergedFiles = Map<String, SyncFileEntry>.from(manifest.files);
    final updatedEntry = updatedScoped[relativePath];
    if (updatedEntry != null) {
      mergedFiles[relativePath] = updatedEntry;
    } else {
      mergedFiles.remove(relativePath);
    }

    await _manifests.write(
      projectDir,
      manifest.copyWith(files: mergedFiles, lastSyncTime: DateTime.now()),
    );

    return SyncResult(
      uploaded: plan.uploads,
      downloaded: plan.downloads,
      deletedLocal: plan.deleteLocal,
      deletedRemote: plan.deleteRemote,
      conflicts: plan.conflicts,
    );
  }

  /// Applies a computed [plan] to disk and Drive, returning the updated
  /// manifest-entry map (starting from [baseFiles]). Shared by [sync] (a
  /// full-project plan) and [syncSingleFile] (a plan scoped to one path).
  Future<Map<String, SyncFileEntry>> _applyPlan({
    required Directory projectDir,
    required String projectFolderName,
    required SyncPlan plan,
    required Map<String, DriveRemoteFile> remoteFiles,
    required Map<String, SyncFileEntry> baseFiles,
  }) async {
    final updatedFiles = Map<String, SyncFileEntry>.from(baseFiles);

    for (final path in plan.uploads) {
      final file = File(p.joinAll([projectDir.path, ...p.posix.split(path)]));
      final bytes = await file.readAsBytes();
      final existingFileId = remoteFiles[path]?.id;
      final uploaded = await _remote.upload(
        projectFolderName: projectFolderName,
        relativePath: path,
        bytes: bytes,
        existingFileId: existingFileId,
      );
      updatedFiles[path] = SyncFileEntry(
        localHash: md5.convert(bytes).toString(),
        driveFileId: uploaded.id,
        driveMd5: uploaded.md5,
      );
    }

    for (final path in plan.downloads) {
      final remote = remoteFiles[path]!;
      final bytes = await _remote.download(remote.id);
      final file = File(p.joinAll([projectDir.path, ...p.posix.split(path)]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      updatedFiles[path] = SyncFileEntry(
        localHash: md5.convert(bytes).toString(),
        driveFileId: remote.id,
        driveMd5: remote.md5,
      );
    }

    for (final path in plan.deleteRemote) {
      final entry = baseFiles[path];
      if (entry != null) await _remote.delete(entry.driveFileId);
      updatedFiles.remove(path);
    }

    for (final path in plan.deleteLocal) {
      final file = File(p.joinAll([projectDir.path, ...p.posix.split(path)]));
      if (await file.exists()) await file.delete();
      updatedFiles.remove(path);
    }

    for (final path in plan.manifestRemovals) {
      updatedFiles.remove(path);
    }

    // Conflicts are left entirely untouched on both sides — the dedicated
    // conflict screen is what writes a resolution, at which point that path
    // becomes an ordinary upload/download on the *next* sync. Recording
    // nothing in the manifest for these paths is deliberate: it keeps them
    // showing up as conflicts every run until actually resolved, rather
    // than this sync silently picking a side.

    return updatedFiles;
  }

  /// Saves the local copy of a conflicting file aside as
  /// `<name>.conflict-<device>-<timestamp><ext>` (PLAN.md's naming) before
  /// the caller pulls Drive's version into the canonical path — "keep both"
  /// rather than silently overwriting prose. The conflict copy is a plain
  /// local file with no manifest entry, so it syncs up as a new file of its
  /// own on a later run, same as any other untracked local file.
  Future<File> saveConflictCopy(Directory projectDir, String relativePath) async {
    final original = File(p.joinAll([projectDir.path, ...p.posix.split(relativePath)]));
    final ext = p.extension(relativePath);
    final base = relativePath.substring(0, relativePath.length - ext.length);
    final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-');
    final conflictPath = '$base.conflict-$_deviceName-$timestamp$ext';
    final conflictFile = File(p.joinAll([projectDir.path, ...p.posix.split(conflictPath)]));
    await conflictFile.parent.create(recursive: true);
    await conflictFile.writeAsBytes(await original.readAsBytes());
    return conflictFile;
  }

  /// Resolves one conflict by keeping Drive's version at the canonical
  /// path — call [saveConflictCopy] first if the local content should be
  /// preserved alongside it.
  Future<void> resolveKeepRemote(Directory projectDir, String projectFolderName, String path) async {
    final manifest = await _manifests.read(projectDir);
    final remoteFiles = await _remote.listFiles(projectFolderName);
    final remote = remoteFiles[path];
    if (remote == null) return;
    final bytes = await _remote.download(remote.id);
    final file = File(p.joinAll([projectDir.path, ...p.posix.split(path)]));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    final updated = Map<String, SyncFileEntry>.from(manifest.files);
    updated[path] = SyncFileEntry(
      localHash: md5.convert(bytes).toString(),
      driveFileId: remote.id,
      driveMd5: remote.md5,
    );
    await _manifests.write(projectDir, manifest.copyWith(files: updated));
  }

  /// Resolves one conflict by keeping the local version, uploading it to
  /// overwrite Drive's diverging copy.
  Future<void> resolveKeepLocal(Directory projectDir, String projectFolderName, String path) async {
    final manifest = await _manifests.read(projectDir);
    final file = File(p.joinAll([projectDir.path, ...p.posix.split(path)]));
    final bytes = await file.readAsBytes();
    final remoteFiles = await _remote.listFiles(projectFolderName);
    final uploaded = await _remote.upload(
      projectFolderName: projectFolderName,
      relativePath: path,
      bytes: bytes,
      existingFileId: remoteFiles[path]?.id,
    );
    final updated = Map<String, SyncFileEntry>.from(manifest.files);
    updated[path] = SyncFileEntry(
      localHash: md5.convert(bytes).toString(),
      driveFileId: uploaded.id,
      driveMd5: uploaded.md5,
    );
    await _manifests.write(projectDir, manifest.copyWith(files: updated));
  }
}
