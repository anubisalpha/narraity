import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'drive_sync_planner.dart' show DriveRemoteFile;

const _folderMimeType = 'application/vnd.google-apps.folder';

/// Talks to the actual Google Drive API, behind the interface
/// [DriveSyncService] depends on so its orchestration logic can be tested
/// against a fake instead of a live Drive connection.
///
/// One dedicated root folder (`Narraity/`, per PLAN.md) holds one subfolder
/// per project, mirroring each project's local folder structure exactly —
/// nested Drive folders for nested local directories (`manuscript/scenes/`
/// becomes `manuscript` → `scenes` on Drive), since Drive itself has no
/// concept of a file "path," only parent-folder links.
abstract class DriveRemoteStore {
  Future<Map<String, DriveRemoteFile>> listFiles(String projectFolderName);

  Future<DriveRemoteFile> upload({
    required String projectFolderName,
    required String relativePath,
    required Uint8List bytes,
    String? existingFileId,
  });

  Future<Uint8List> download(String fileId);

  Future<void> delete(String fileId);
}

class GoogleDriveRemoteStore implements DriveRemoteStore {
  GoogleDriveRemoteStore(http.Client authenticatedClient)
      : _api = drive.DriveApi(authenticatedClient);

  final drive.DriveApi _api;

  /// Cache of resolved folder ids for this store's lifetime — `Narraity`
  /// itself; every project folder rarely changes, so no reason to
  /// re-query Drive for the same path within one sync run.
  final Map<String, String> _folderIdCache = {};

  Future<String> _rootFolderId() => _findOrCreateFolder('Narraity', parentId: null);

  Future<String> _projectFolderId(String projectFolderName) async {
    final root = await _rootFolderId();
    return _findOrCreateFolder(projectFolderName, parentId: root);
  }

  Future<String> _findOrCreateFolder(String name, {required String? parentId}) async {
    final cacheKey = '${parentId ?? 'root'}/$name';
    final cached = _folderIdCache[cacheKey];
    if (cached != null) return cached;

    final parentClause = parentId == null ? "'root' in parents" : "'$parentId' in parents";
    final escapedName = name.replaceAll("'", "\\'");
    final query = "name = '$escapedName' and mimeType = '$_folderMimeType' "
        'and $parentClause and trashed = false';

    final result = await _api.files.list(q: query, spaces: 'drive', $fields: 'files(id)');
    final existing = result.files;
    if (existing != null && existing.isNotEmpty) {
      final id = existing.first.id!;
      _folderIdCache[cacheKey] = id;
      return id;
    }

    final created = await _api.files.create(
      drive.File()
        ..name = name
        ..mimeType = _folderMimeType
        ..parents = parentId == null ? null : [parentId],
    );
    final id = created.id!;
    _folderIdCache[cacheKey] = id;
    return id;
  }

  @override
  Future<Map<String, DriveRemoteFile>> listFiles(String projectFolderName) async {
    final projectId = await _projectFolderId(projectFolderName);
    final result = <String, DriveRemoteFile>{};
    await _listInto(result, folderId: projectId, pathPrefix: '');
    return result;
  }

  Future<void> _listInto(
    Map<String, DriveRemoteFile> result, {
    required String folderId,
    required String pathPrefix,
  }) async {
    String? pageToken;
    do {
      final page = await _api.files.list(
        q: "'$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'nextPageToken, files(id, name, mimeType, md5Checksum)',
        pageToken: pageToken,
      );
      for (final file in page.files ?? const <drive.File>[]) {
        final name = file.name!;
        final path = pathPrefix.isEmpty ? name : '$pathPrefix/$name';
        if (file.mimeType == _folderMimeType) {
          _folderIdCache['$folderId/$name'] = file.id!;
          await _listInto(result, folderId: file.id!, pathPrefix: path);
        } else {
          result[path] = DriveRemoteFile(id: file.id!, md5: file.md5Checksum ?? '');
        }
      }
      pageToken = page.nextPageToken;
    } while (pageToken != null);
  }

  /// Resolves (creating as needed) the Drive folder id for [relativeDir]
  /// (posix-style, `''` for the project root itself) under [projectId].
  Future<String> _resolveDirId(String projectId, String relativeDir) async {
    if (relativeDir.isEmpty) return projectId;
    var currentId = projectId;
    for (final segment in relativeDir.split('/')) {
      currentId = await _findOrCreateFolder(segment, parentId: currentId);
    }
    return currentId;
  }

  @override
  Future<DriveRemoteFile> upload({
    required String projectFolderName,
    required String relativePath,
    required Uint8List bytes,
    String? existingFileId,
  }) async {
    final projectId = await _projectFolderId(projectFolderName);
    final slash = relativePath.lastIndexOf('/');
    final dir = slash == -1 ? '' : relativePath.substring(0, slash);
    final fileName = slash == -1 ? relativePath : relativePath.substring(slash + 1);
    final parentId = await _resolveDirId(projectId, dir);

    final media = drive.Media(Stream.value(bytes), bytes.length);
    final drive.File result;
    if (existingFileId != null) {
      result = await _api.files.update(
        drive.File(),
        existingFileId,
        uploadMedia: media,
        $fields: 'id, md5Checksum',
      );
    } else {
      result = await _api.files.create(
        drive.File()
          ..name = fileName
          ..parents = [parentId],
        uploadMedia: media,
        $fields: 'id, md5Checksum',
      );
    }
    return DriveRemoteFile(id: result.id!, md5: result.md5Checksum ?? '');
  }

  @override
  Future<Uint8List> download(String fileId) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = BytesBuilder();
    await for (final chunk in media.stream) {
      bytes.add(chunk);
    }
    return bytes.toBytes();
  }

  @override
  Future<void> delete(String fileId) => _api.files.delete(fileId);
}
