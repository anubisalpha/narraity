import '../models/sync_manifest.dart';

/// One file's state on Drive, as seen by the current listing — not the
/// manifest's remembered state.
class DriveRemoteFile {
  const DriveRemoteFile({required this.id, required this.md5});
  final String id;
  final String md5;
}

/// What to do with one path, decided by comparing its local hash, its
/// current Drive state, and what the manifest last recorded about it — a
/// three-way diff against the last-known-synced state, same shape as any
/// offline-first sync (Dropbox, git). See [DriveSyncPlanner.plan] for the
/// full case breakdown; PLAN.md's "Google Drive Sync" section is the design
/// this implements.
enum SyncAction { upload, download, deleteLocal, deleteRemote }

/// A path whose content diverged on both sides since the last sync with no
/// clear winner — PLAN.md: "keep both files ... flagged in-app for manual
/// merge rather than silently overwriting prose." The dedicated conflict
/// screen resolves these; a deletion racing an edit is *not* a conflict of
/// this kind — see [DriveSyncPlanner.plan]'s doc comment for why.
class SyncConflict {
  const SyncConflict({required this.path, required this.driveFileId});
  final String path;
  final String driveFileId;

  @override
  bool operator ==(Object other) =>
      other is SyncConflict && other.path == path && other.driveFileId == driveFileId;

  @override
  int get hashCode => Object.hash(path, driveFileId);
}

class SyncPlan {
  const SyncPlan({
    required this.uploads,
    required this.downloads,
    required this.deleteLocal,
    required this.deleteRemote,
    required this.conflicts,
    required this.manifestRemovals,
  });

  final List<String> uploads;
  final List<String> downloads;
  final List<String> deleteLocal;
  final List<String> deleteRemote;
  final List<SyncConflict> conflicts;

  /// Paths with no remaining content on either side (both deleted since the
  /// last sync, consistently) — nothing to move, just drop from the
  /// manifest so it stops being tracked.
  final List<String> manifestRemovals;

  bool get isEmpty =>
      uploads.isEmpty &&
      downloads.isEmpty &&
      deleteLocal.isEmpty &&
      deleteRemote.isEmpty &&
      conflicts.isEmpty &&
      manifestRemovals.isEmpty;
}

/// Pure diff logic — no file I/O, no Drive API calls — so the actual
/// decision-making is unit-testable without a live Drive connection.
class DriveSyncPlanner {
  /// [localHashes] and [remoteFiles] are keyed by path relative to the
  /// project folder (posix separators). [manifest] is the last-known-synced
  /// state to three-way-diff against.
  static SyncPlan plan({
    required Map<String, String> localHashes,
    required Map<String, DriveRemoteFile> remoteFiles,
    required SyncManifest manifest,
  }) {
    final uploads = <String>[];
    final downloads = <String>[];
    final deleteLocal = <String>[];
    final deleteRemote = <String>[];
    final conflicts = <SyncConflict>[];
    final manifestRemovals = <String>[];

    final allPaths = {...localHashes.keys, ...remoteFiles.keys, ...manifest.files.keys};

    for (final path in allPaths) {
      final entry = manifest.files[path];
      final hasLocal = localHashes.containsKey(path);
      final hasRemote = remoteFiles.containsKey(path);

      if (entry == null) {
        // Never synced before — no common ancestor to diff against.
        if (hasLocal && !hasRemote) {
          uploads.add(path);
        } else if (!hasLocal && hasRemote) {
          downloads.add(path);
        } else if (hasLocal && hasRemote) {
          // Same path created independently on both sides with no shared
          // history — treat exactly like a content conflict rather than
          // guessing a winner.
          conflicts.add(SyncConflict(path: path, driveFileId: remoteFiles[path]!.id));
        }
        continue;
      }

      final localChanged = !hasLocal || localHashes[path] != entry.localHash;
      final remoteChanged = !hasRemote || remoteFiles[path]!.md5 != entry.driveMd5;

      if (!localChanged && !remoteChanged) continue; // nothing to do

      if (localChanged && !remoteChanged) {
        if (!hasLocal) {
          deleteRemote.add(path);
        } else {
          uploads.add(path);
        }
        continue;
      }

      if (!localChanged && remoteChanged) {
        if (!hasRemote) {
          deleteLocal.add(path);
        } else {
          downloads.add(path);
        }
        continue;
      }

      // Both sides changed since the last sync. A deletion racing an edit
      // has an unambiguous resolution — keep whichever side still has
      // content, since that's the only way to avoid silently discarding
      // prose — so only "both sides still have content, and it differs" is
      // a genuine conflict needing the user's judgment.
      if (!hasLocal && !hasRemote) {
        manifestRemovals.add(path); // deleted on both sides, consistently
      } else if (!hasLocal && hasRemote) {
        downloads.add(path); // local deleted it, but remote also has edits — restore locally
      } else if (hasLocal && !hasRemote) {
        uploads.add(path); // remote deleted it, but local also has edits — re-upload
      } else {
        conflicts.add(SyncConflict(path: path, driveFileId: remoteFiles[path]!.id));
      }
    }

    return SyncPlan(
      uploads: uploads,
      downloads: downloads,
      deleteLocal: deleteLocal,
      deleteRemote: deleteRemote,
      conflicts: conflicts,
      manifestRemovals: manifestRemovals,
    );
  }
}
