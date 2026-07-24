import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/project.dart';

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
      if (p.basename(entity.path).startsWith('_')) continue; // reserved (e.g. _GlobalIdeas)

      final projectFile = File(p.join(entity.path, 'project.json'));
      if (!await projectFile.exists()) continue;

      try {
        final json = jsonDecode(await projectFile.readAsString()) as Map<String, dynamic>;
        projects.add(Project.fromJson(json, folderName: p.basename(entity.path)));
      } catch (_) {
        // Skip unreadable/corrupt project.json rather than crashing the library view.
        continue;
      }
    }

    projects.sort((a, b) => b.modified.compareTo(a.modified));
    return projects;
  }

  Future<Project> createProject({required String title, String? author}) async {
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
    );

    await _writeProjectJson(projectDir, project);
    await File(p.join(projectDir.path, 'todos', 'todos.json'))
        .writeAsString(jsonEncode({'todos': []}));

    return project;
  }

  Future<void> saveProject(Project project) async {
    final root = await libraryRoot();
    final projectDir = Directory(p.join(root.path, project.folderName));
    await _writeProjectJson(projectDir, project);
  }

  Future<void> _writeProjectJson(Directory projectDir, Project project) async {
    final file = File(p.join(projectDir.path, 'project.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(project.toJson()));
  }

  String _uniqueFolderName(Directory root, String title) {
    final base = title.trim().isEmpty
        ? 'Untitled'
        : title.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
    var candidate = base;
    var suffix = 1;
    while (Directory(p.join(root.path, candidate)).existsSync()) {
      suffix++;
      candidate = '$base ($suffix)';
    }
    return candidate;
  }
}
