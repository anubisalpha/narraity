import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
}
