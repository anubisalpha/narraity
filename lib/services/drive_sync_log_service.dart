import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/sync_log_entry.dart';

/// Local, capped activity log for Drive sync — every manual, immediate, or
/// periodic sync attempt appends one entry, so the user has something
/// concrete to check ("is this actually syncing?") beyond a snackbar that's
/// already gone.
///
/// Deliberately stored under the app support directory (same location as
/// [DriveTokenStore]), *not* under `Documents/Narraity/` — putting it there
/// would mean the App Settings sync target picks it up and starts syncing
/// the sync log itself, which is per-device diagnostic information, not
/// something that belongs on Drive.
class DriveSyncLogService {
  /// Pass [rootOverride] to point storage at a specific directory (used by
  /// tests) instead of resolving the platform support folder.
  DriveSyncLogService({Directory? rootOverride}) : _root = rootOverride;

  Directory? _root;

  static const maxEntries = 200;

  Future<Directory> _logRoot() async {
    if (_root != null) return _root!;
    final support = await getApplicationSupportDirectory();
    return _root = Directory(p.join(support.path, 'drive_sync_log'));
  }

  Future<File> _logFile() async {
    final root = await _logRoot();
    return File(p.join(root.path, 'log.json'));
  }

  /// Most recent entries first.
  Future<List<SyncLogEntry>> readRecent() async {
    final file = await _logFile();
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString()) as List<dynamic>;
      return json
          .map((e) => SyncLogEntry.fromJson(e as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return []; // corrupt/unreadable log — not worth surfacing an error for
    }
  }

  /// Appends one entry, trimming to the last [maxEntries] so the log can't
  /// grow unbounded over the life of an install.
  Future<void> append(SyncLogEntry entry) async {
    final existing = (await readRecent()).reversed.toList(); // back to oldest-first
    existing.add(entry);
    final trimmed = existing.length > maxEntries
        ? existing.sublist(existing.length - maxEntries)
        : existing;

    final file = await _logFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() async {
    final file = await _logFile();
    if (await file.exists()) await file.delete();
  }
}
