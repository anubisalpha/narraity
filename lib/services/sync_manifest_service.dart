import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/sync_manifest.dart';

/// Reads/writes a project's `.sync/manifest.json` (per PLAN.md's data
/// model) and computes the local side of a sync diff: every ordinary file
/// under the project folder, hashed and keyed by its posix-style relative
/// path.
class SyncManifestService {
  File _manifestFile(Directory projectDir) =>
      File(p.join(projectDir.path, '.sync', 'manifest.json'));

  Future<SyncManifest> read(Directory projectDir) async {
    final file = _manifestFile(projectDir);
    if (!await file.exists()) return SyncManifest.empty;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SyncManifest.fromJson(json);
    } catch (_) {
      // Corrupt/unreadable manifest — treat as "never synced" rather than
      // crashing; the next sync just re-diffs everything from scratch,
      // which at worst re-detects a few already-consistent files as new.
      return SyncManifest.empty;
    }
  }

  Future<void> write(Directory projectDir, SyncManifest manifest) async {
    final file = _manifestFile(projectDir);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
  }

  /// Every ordinary file under [projectDir], excluding `.sync/` itself (the
  /// manifest isn't a file the manifest tracks) and `.history_backup/`
  /// mirrors (Version History's own redundancy copy — syncing it too would
  /// double Drive's storage use for no benefit, since the primary
  /// `.history` files already sync and the mirror is purely local-corruption
  /// insurance). Keyed by posix-style path relative to [projectDir], hashed
  /// with md5 to match what Drive itself reports for each file
  /// (`md5Checksum`), so local and remote hashes are directly comparable.
  Future<Map<String, String>> hashLocalFiles(Directory projectDir) async {
    final result = <String, String>{};
    if (!await projectDir.exists()) return result;

    await for (final entity in projectDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: projectDir.path);
      final segments = p.split(relative);
      if (segments.first == '.sync') continue;
      if (segments.contains('.history_backup')) continue;

      final bytes = await entity.readAsBytes();
      final posixPath = segments.join('/');
      result[posixPath] = md5.convert(bytes).toString();
    }
    return result;
  }
}
