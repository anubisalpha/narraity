/// Everything the sync engine knew about one file as of the last successful
/// sync — the common ancestor state a three-way diff (local vs. remote vs.
/// last-known) is compared against.
class SyncFileEntry {
  const SyncFileEntry({
    required this.localHash,
    required this.driveFileId,
    required this.driveMd5,
  });

  /// md5 of the local file's content as of the last sync.
  final String localHash;
  final String driveFileId;
  final String driveMd5;

  Map<String, dynamic> toJson() => {
        'localHash': localHash,
        'driveFileId': driveFileId,
        'driveMd5': driveMd5,
      };

  factory SyncFileEntry.fromJson(Map<String, dynamic> json) => SyncFileEntry(
        localHash: json['localHash'] as String,
        driveFileId: json['driveFileId'] as String,
        driveMd5: json['driveMd5'] as String,
      );
}

/// One project's `.sync/manifest.json` — every file's last-known-synced
/// state, keyed by its path relative to the project folder (posix
/// separators, so the manifest is portable across Windows/Android).
class SyncManifest {
  const SyncManifest({required this.files, this.lastSyncTime});

  final Map<String, SyncFileEntry> files;
  final DateTime? lastSyncTime;

  static const empty = SyncManifest(files: {});

  SyncManifest copyWith({Map<String, SyncFileEntry>? files, DateTime? lastSyncTime}) =>
      SyncManifest(
        files: files ?? this.files,
        lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      );

  Map<String, dynamic> toJson() => {
        'files': files.map((path, entry) => MapEntry(path, entry.toJson())),
        if (lastSyncTime != null) 'lastSyncTime': lastSyncTime!.toIso8601String(),
      };

  factory SyncManifest.fromJson(Map<String, dynamic> json) => SyncManifest(
        files: (json['files'] as Map<String, dynamic>? ?? {}).map(
          (path, entry) => MapEntry(path, SyncFileEntry.fromJson(entry as Map<String, dynamic>)),
        ),
        lastSyncTime:
            json['lastSyncTime'] == null ? null : DateTime.parse(json['lastSyncTime'] as String),
      );
}
