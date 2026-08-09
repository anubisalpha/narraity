import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:narraity/services/drive_remote_store.dart';
import 'package:narraity/services/drive_sync_planner.dart';

/// In-memory [DriveRemoteStore] for tests — no network, no real Drive
/// project/credentials needed. Keyed by project folder name, then by
/// posix-style relative path, mirroring how [GoogleDriveRemoteStore] behaves
/// from a caller's point of view (ids assigned on create, md5 tracked per
/// file) without any of the real Drive folder-tree plumbing.
class FakeDriveRemoteStore implements DriveRemoteStore {
  final Map<String, Map<String, _FakeFile>> _projects = {};
  int _nextId = 1;

  /// Test helper: seeds a file directly, as if it already existed on Drive
  /// before the sync under test began. [modifiedTime] defaults to now, same
  /// as a real Drive upload would stamp.
  void seed(
    String projectFolderName,
    String relativePath,
    List<int> bytes, {
    DateTime? modifiedTime,
  }) {
    final project = _projects.putIfAbsent(projectFolderName, () => {});
    final id = 'fake-${_nextId++}';
    project[relativePath] = _FakeFile(
      id: id,
      bytes: Uint8List.fromList(bytes),
      modifiedTime: modifiedTime ?? DateTime.now(),
    );
  }

  @override
  Future<List<String>> listProjectFolderNames() async {
    return _projects.keys.where((name) => !name.startsWith('_')).toList();
  }

  @override
  Future<Map<String, DriveRemoteFile>> listFiles(String projectFolderName) async {
    final project = _projects[projectFolderName] ?? {};
    return {
      for (final entry in project.entries)
        entry.key: DriveRemoteFile(
          id: entry.value.id,
          md5: entry.value.md5,
          modifiedTime: entry.value.modifiedTime,
        ),
    };
  }

  @override
  Future<DriveRemoteFile?> findFile({
    required String projectFolderName,
    required String relativePath,
  }) async {
    final file = _projects[projectFolderName]?[relativePath];
    if (file == null) return null;
    return DriveRemoteFile(id: file.id, md5: file.md5, modifiedTime: file.modifiedTime);
  }

  @override
  Future<DriveRemoteFile> upload({
    required String projectFolderName,
    required String relativePath,
    required Uint8List bytes,
    String? existingFileId,
  }) async {
    final project = _projects.putIfAbsent(projectFolderName, () => {});
    final id = existingFileId ?? 'fake-${_nextId++}';
    final file = _FakeFile(id: id, bytes: bytes, modifiedTime: DateTime.now());
    project[relativePath] = file;
    return DriveRemoteFile(id: file.id, md5: file.md5, modifiedTime: file.modifiedTime);
  }

  @override
  Future<Uint8List> download(String fileId) async {
    for (final project in _projects.values) {
      for (final file in project.values) {
        if (file.id == fileId) return file.bytes;
      }
    }
    throw StateError('No fake file with id $fileId');
  }

  @override
  Future<void> delete(String fileId) async {
    for (final project in _projects.values) {
      project.removeWhere((_, file) => file.id == fileId);
    }
  }
}

class _FakeFile {
  _FakeFile({required this.id, required this.bytes, required this.modifiedTime});
  final String id;
  final Uint8List bytes;
  final DateTime modifiedTime;
  String get md5 => crypto.md5.convert(bytes).toString();
}
