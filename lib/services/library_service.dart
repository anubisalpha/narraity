import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:win32/win32.dart';

import '../models/archived_project.dart';
import '../models/project.dart';
import 'filename_sanitizer.dart';

const _uuid = Uuid();

/// Reads/writes the local, file-based project library.
///
/// Library root defaults to `Documents/Narraity/` and mirrors the structure
/// documented in PLAN.md's "Data model" section. Phase 0 only needs
/// standalone projects (no series/global-ideas yet — those land in their own
/// phases), so this scans one level deep for folders containing a
/// `project.json`.
class LibraryService {
  /// Pass [rootOverride] to point the library at a specific directory
  /// (used by tests) instead of resolving the platform documents folder.
  LibraryService({Directory? rootOverride}) : _root = rootOverride;

  Directory? _root;

  Future<Directory> libraryRoot() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'Narraity'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    _root = root;
    return root;
  }

  Future<List<Project>> listProjects() async {
    final root = await libraryRoot();
    final projects = <Project>[];

    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      if (p.basename(entity.path).startsWith('_')) {
        continue; // reserved (e.g. _GlobalIdeas)
      }

      final projectFile = File(p.join(entity.path, 'project.json'));
      if (!await projectFile.exists()) continue;

      try {
        final json =
            jsonDecode(await projectFile.readAsString())
                as Map<String, dynamic>;
        projects.add(
          Project.fromJson(json, folderName: p.basename(entity.path)),
        );
      } catch (_) {
        // Skip unreadable/corrupt project.json rather than crashing the library view.
        continue;
      }
    }

    projects.sort((a, b) => b.modified.compareTo(a.modified));
    return projects;
  }

  Future<Project> createProject({
    required String title,
    String? author,
    String? seriesId,
    ProjectKind kind = ProjectKind.novel,
  }) async {
    final root = await libraryRoot();
    final folderName = _uniqueFolderName(root, title);
    final projectDir = Directory(p.join(root.path, folderName));
    await projectDir.create(recursive: true);

    // Skeleton matching PLAN.md's data model, so later phases don't need migrations.
    for (final sub in [
      'manuscript',
      'plot-grid',
      'characters',
      'worldbuilding',
      'notes',
      'timelines',
      'relationships',
      'goals',
      'assets/covers',
      'assets/images',
      'todos',
      '.sync',
    ]) {
      await Directory(p.join(projectDir.path, sub)).create(recursive: true);
    }

    final now = DateTime.now();
    final project = Project(
      id: _uuid.v4(),
      folderName: folderName,
      title: title,
      author: author,
      created: now,
      modified: now,
      seriesId: seriesId,
      kind: kind,
    );

    await _writeProjectJson(projectDir, project);
    await File(
      p.join(projectDir.path, 'todos', 'todos.json'),
    ).writeAsString(jsonEncode({'todos': []}));

    return project;
  }

  Future<void> saveProject(Project project) async {
    final root = await libraryRoot();
    final projectDir = Directory(p.join(root.path, project.folderName));
    await _writeProjectJson(projectDir, project);
  }

  /// Copies [sourceImage] into this project's `assets/covers/` folder as
  /// `cover.<ext>`, replacing any previous cover file (which may have had a
  /// different extension — a plain overwrite-by-name wouldn't clean that up),
  /// and persists the new `coverImagePath`. Returns the updated [Project].
  Future<Project> setCoverImage(Project project, File sourceImage) async {
    final root = await libraryRoot();
    final projectDir = Directory(p.join(root.path, project.folderName));
    final coversDir = Directory(p.join(projectDir.path, 'assets', 'covers'));
    await coversDir.create(recursive: true);

    await for (final entity in coversDir.list()) {
      if (entity is File &&
          p.basenameWithoutExtension(entity.path) == 'cover') {
        await entity.delete();
      }
    }

    final ext = p.extension(sourceImage.path);
    final destPath = p.join(coversDir.path, 'cover$ext');
    await sourceImage.copy(destPath);

    final updated = project.copyWith(
      coverImagePath: p.join('assets', 'covers', 'cover$ext'),
      modified: DateTime.now(),
    );
    await saveProject(updated);
    return updated;
  }

  /// Deletes the current cover file (if any) and clears `coverImagePath`.
  Future<Project> removeCoverImage(Project project) async {
    if (project.coverImagePath != null) {
      final root = await libraryRoot();
      final file = File(
        p.join(root.path, project.folderName, project.coverImagePath!),
      );
      if (await file.exists()) {
        await file.delete();
      }
    }
    final updated = project.copyWith(
      clearCoverImagePath: true,
      modified: DateTime.now(),
    );
    await saveProject(updated);
    return updated;
  }

  /// Absolute path to [project]'s cover image file, or null if it has none.
  Future<String?> coverImageAbsolutePath(Project project) async {
    if (project.coverImagePath == null) return null;
    final root = await libraryRoot();
    return p.join(root.path, project.folderName, project.coverImagePath!);
  }

  Future<void> _writeProjectJson(Directory projectDir, Project project) async {
    final file = File(p.join(projectDir.path, 'project.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(project.toJson()),
    );
  }

  String _uniqueFolderName(Directory root, String title) {
    final base = sanitizeFileName(title);
    var candidate = base;
    var suffix = 1;
    while (Directory(p.join(root.path, candidate)).existsSync()) {
      suffix++;
      candidate = '$base ($suffix)';
    }
    return candidate;
  }

  /// `_Archived`/`_Deleted` are reserved folders alongside project folders,
  /// same convention as `_GlobalIdeas` — [listProjects] already skips any
  /// folder starting with `_`, so nothing extra is needed to keep these out
  /// of the normal library view.
  Future<Directory> _reservedDir(String name) async {
    final root = await libraryRoot();
    final dir = Directory(p.join(root.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _uniqueZipName(Directory dir, String title) {
    final base = sanitizeFileName(title);
    var candidate = '$base.zip';
    var suffix = 1;
    while (File(p.join(dir.path, candidate)).existsSync()) {
      suffix++;
      candidate = '$base ($suffix).zip';
    }
    return candidate;
  }

  /// Compresses [project]'s whole folder tree into a single `.zip` under
  /// [reservedDirName] (`_Archived` or `_Deleted`) and removes the live
  /// folder — this is a soft removal, never a permanent one: the zip stays
  /// on disk indefinitely until restored, or the user deletes it themselves
  /// from the filesystem (see `ArchivedProject`'s doc comment for why this
  /// app never does that automatically). The zip's own filesystem
  /// modified-time doubles as the "archived at" timestamp shown in the UI,
  /// so nothing extra needs encoding into the filename.
  ///
  /// **Move first, then compress** (changed 2026-08-01, see BUILD_LOG.md):
  /// a *rename* out of the live library root happens before anything else,
  /// rather than compressing the live folder in place and deleting it
  /// afterward. This matters because a plain rename tolerates a concurrent
  /// reader (e.g. a background sync/backup/indexing client scanning the
  /// folder) far better than a delete does — deleting requires every handle
  /// on every file to be closed first, while renaming just repoints one
  /// directory entry. It also means the project disappears from
  /// [listProjects] immediately, rather than only after the (potentially
  /// slow) zip finishes — the same "why did the folder linger" gap this
  /// replaced. The staged copy's own eventual deletion (after zipping) is
  /// still best-effort/retried, but a failure there no longer breaks the
  /// user-visible promise: the project is already out of the live library
  /// and its zip already exists by that point.
  Future<void> _archiveTo(Project project, String reservedDirName) async {
    final root = await libraryRoot();
    final projectDir = Directory(p.join(root.path, project.folderName));
    final destDir = await _reservedDir(reservedDirName);

    final stagingName = _uniqueFolderName(destDir, '${project.folderName}.staged');
    final stagingDir = Directory(p.join(destDir.path, stagingName));
    await projectDir.rename(stagingDir.path);

    final zipName = _uniqueZipName(destDir, project.title);
    final zipPath = p.join(destDir.path, zipName);
    await ZipFileEncoder().zipDirectory(stagingDir, filename: zipPath);

    await _deleteWithRetry(stagingDir);
  }

  /// Removes [dir], retrying on `PathAccessException`/"Access is denied".
  ///
  /// By the time this runs, [dir] is only the already-zipped *staging*
  /// copy (see `_archiveTo`'s "move first, then compress" doc) — the live
  /// project is already out of the library and its zip already exists, so
  /// a failure here is a leftover-cleanup problem, not a broken archive/
  /// delete promise.
  ///
  /// Investigated (not guessed) why a plain `delete()` could fail here at
  /// all straight after zipping: ruled out Narraity's own Drive-sync file
  /// watcher (confirmed "Not connected" in Settings during testing) and the
  /// Vault backup-on-close hook (no-op with no vault password set).
  /// Google Drive File Stream (`GoogleDriveFS.exe`, a separate installed
  /// application, not part of Narraity) was running throughout testing and
  /// is the most likely remaining explanation — a background sync client
  /// scanning a just-written folder is a well-known source of exactly this
  /// kind of transient Windows lock. The "move first" step above already
  /// mitigates most of the risk (a rename tolerates a concurrent reader far
  /// better than a delete, which needs every handle closed), and this
  /// method's job is only the second-order cleanup of the now-isolated
  /// staging copy — no longer the user-visible bottleneck it was before.
  ///
  /// On Windows, "delete" here actually means the Recycle Bin
  /// (`_recycleBin`), not a permanent delete — one more recovery path
  /// beyond the zip itself if anything about this ever misbehaves.
  Future<void> _deleteWithRetry(
    Directory dir, {
    int attempts = 30,
    Duration delay = const Duration(seconds: 1),
  }) async {
    for (var i = 0; i < attempts; i++) {
      try {
        if (Platform.isWindows) {
          _recycleBin(dir);
        } else {
          await dir.delete(recursive: true);
        }
        return;
      } on FileSystemException {
        if (i == attempts - 1) rethrow;
        await Future<void>.delayed(delay);
      }
    }
  }

  /// Sends [dir] to the Windows Recycle Bin via the shell's
  /// `SHFileOperationW` API (`FO_DELETE` + `FOF_ALLOWUNDO`) instead of
  /// permanently deleting it. `pFrom` must be a *double* null-terminated
  /// string per that API's own contract — appending one `'\x00'` before
  /// `toNativeUtf16()` (which appends its own terminator) produces exactly
  /// that.
  void _recycleBin(Directory dir) {
    final pathPtr = '${dir.path}\x00'.toNativeUtf16();
    final fileOp = calloc<SHFILEOPSTRUCT>();
    try {
      fileOp.ref
        ..hwnd = 0
        ..wFunc = FO_DELETE
        ..pFrom = pathPtr
        ..pTo = nullptr
        ..fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;
      final result = SHFileOperation(fileOp);
      if (result != 0) {
        throw FileSystemException(
          'SHFileOperation (recycle) failed with code $result',
          dir.path,
        );
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(fileOp);
    }
  }

  Future<void> archiveProject(Project project) => _archiveTo(project, '_Archived');
  Future<void> deleteProject(Project project) => _archiveTo(project, '_Deleted');

  /// Lists the `.zip` records under [reservedDirName], reading just enough
  /// of each (via a streamed read, not a full in-memory decode) to pull
  /// title/author out of the embedded `project.json` for display.
  Future<List<ArchivedProject>> _listReserved(String reservedDirName) async {
    final dir = await _reservedDir(reservedDirName);
    final records = <ArchivedProject>[];

    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.zip')) continue;

      try {
        final input = InputFileStream(entity.path);
        final archive = ZipDecoder().decodeStream(input);
        final projectJsonFile = archive.findFile('project.json');
        if (projectJsonFile == null) continue;

        final json =
            jsonDecode(utf8.decode(projectJsonFile.content)) as Map<String, dynamic>;
        records.add(
          ArchivedProject(
            fileName: p.basename(entity.path),
            title: json['title'] as String? ?? p.basenameWithoutExtension(entity.path),
            author: json['author'] as String?,
            archivedAt: (await entity.stat()).modified,
          ),
        );
        await input.close();
      } catch (_) {
        // Skip an unreadable/corrupt zip rather than crashing the whole list.
        continue;
      }
    }

    records.sort((a, b) => b.archivedAt.compareTo(a.archivedAt));
    return records;
  }

  Future<List<ArchivedProject>> listArchived() => _listReserved('_Archived');
  Future<List<ArchivedProject>> listDeleted() => _listReserved('_Deleted');

  /// Extracts [record]'s zip back into a fresh, live project folder (a new
  /// unique folder name, same collision-avoidance as [createProject] —
  /// never overwrites an existing project) and removes the zip. The
  /// restored project keeps its original id/title/history; only its
  /// on-disk folder name may differ from before if something now occupies
  /// its old name.
  Future<Project> _restoreFrom(ArchivedProject record, String reservedDirName) async {
    final root = await libraryRoot();
    final srcDir = await _reservedDir(reservedDirName);
    final zipPath = p.join(srcDir.path, record.fileName);

    final folderName = _uniqueFolderName(root, record.title);
    final destDir = Directory(p.join(root.path, folderName));
    await destDir.create(recursive: true);
    await extractFileToDisk(zipPath, destDir.path);
    await File(zipPath).delete();

    final projectFile = File(p.join(destDir.path, 'project.json'));
    final json = jsonDecode(await projectFile.readAsString()) as Map<String, dynamic>;
    return Project.fromJson(json, folderName: folderName);
  }

  Future<Project> restoreArchived(ArchivedProject record) => _restoreFrom(record, '_Archived');
  Future<Project> restoreDeleted(ArchivedProject record) => _restoreFrom(record, '_Deleted');
}
