/// What caused a sync run — shown in the log so "why did this just sync"
/// has an answer.
enum SyncTrigger { manual, immediate, periodic }

/// One completed sync attempt (a project, the Vault, or App Settings),
/// recorded by [DriveSyncLogService] so the user has something to check
/// besides "did anything happen" — visible proof a background sync ran, and
/// what it actually did.
class SyncLogEntry {
  const SyncLogEntry({
    required this.timestamp,
    required this.targetTitle,
    required this.trigger,
    this.uploaded = 0,
    this.downloaded = 0,
    this.deletedLocal = 0,
    this.deletedRemote = 0,
    this.conflicts = 0,
    this.error,
  });

  final DateTime timestamp;
  final String targetTitle;
  final SyncTrigger trigger;
  final int uploaded;
  final int downloaded;
  final int deletedLocal;
  final int deletedRemote;
  final int conflicts;

  /// Null for a successful run — set when the sync attempt itself threw.
  final String? error;

  bool get hadAnyChange =>
      uploaded > 0 || downloaded > 0 || deletedLocal > 0 || deletedRemote > 0 || conflicts > 0;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'targetTitle': targetTitle,
        'trigger': trigger.name,
        'uploaded': uploaded,
        'downloaded': downloaded,
        'deletedLocal': deletedLocal,
        'deletedRemote': deletedRemote,
        'conflicts': conflicts,
        if (error != null) 'error': error,
      };

  factory SyncLogEntry.fromJson(Map<String, dynamic> json) => SyncLogEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        targetTitle: json['targetTitle'] as String,
        trigger: SyncTrigger.values.firstWhere(
          (t) => t.name == json['trigger'],
          orElse: () => SyncTrigger.manual,
        ),
        uploaded: json['uploaded'] as int? ?? 0,
        downloaded: json['downloaded'] as int? ?? 0,
        deletedLocal: json['deletedLocal'] as int? ?? 0,
        deletedRemote: json['deletedRemote'] as int? ?? 0,
        conflicts: json['conflicts'] as int? ?? 0,
        error: json['error'] as String?,
      );
}
