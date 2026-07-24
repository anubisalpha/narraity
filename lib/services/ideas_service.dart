import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/idea.dart';
import '../models/project.dart';
import 'library_service.dart';

const _uuid = Uuid();

/// Reads/writes `_GlobalIdeas/` at the library root — one `idea-<id>.json`
/// per idea, alongside (not inside) project folders, so capture works
/// without any project open. See PLAN.md "Global Ideas".
class IdeasService {
  IdeasService(this._library);

  final LibraryService _library;

  Future<Directory> _ideasDir() async {
    final root = await _library.libraryRoot();
    final dir = Directory(p.join(root.path, '_GlobalIdeas'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Idea>> listIdeas() async {
    final dir = await _ideasDir();
    final ideas = <Idea>[];

    await for (final entity in dir.list()) {
      if (entity is! File || !p.basename(entity.path).endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        ideas.add(Idea.fromJson(json));
      } catch (_) {
        continue; // skip corrupt files rather than breaking the list view
      }
    }

    ideas.sort((a, b) => b.created.compareTo(a.created));
    return ideas;
  }

  Future<Idea> captureIdea({
    required String title,
    String body = '',
    List<String> tags = const [],
  }) async {
    final idea = Idea(
      id: _uuid.v4(),
      title: title,
      body: body,
      tags: tags,
      created: DateTime.now(),
    );
    await _write(idea);
    return idea;
  }

  Future<void> saveIdea(Idea idea) => _write(idea);

  Future<void> deleteIdea(Idea idea) async {
    final dir = await _ideasDir();
    final file = File(p.join(dir.path, 'idea-${idea.id}.json'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Promote an idea to a brand-new project. The idea's body seeds the
  /// project's first story note, and the idea is marked used (not deleted).
  Future<Project> promoteToNewProject(Idea idea) async {
    final project = await _library.createProject(title: idea.title);
    await _seedNote(project, idea);
    await _write(idea.copyWith(status: IdeaStatus.used, linkedProjectId: project.id));
    return project;
  }

  /// Attach an idea to an existing project as a story note, marking it used.
  Future<void> attachToProject(Idea idea, Project project) async {
    await _seedNote(project, idea);
    await _write(idea.copyWith(status: IdeaStatus.used, linkedProjectId: project.id));
  }

  Future<void> _seedNote(Project project, Idea idea) async {
    final root = await _library.libraryRoot();
    final notesDir = Directory(p.join(root.path, project.folderName, 'notes'));
    await notesDir.create(recursive: true);
    final note = {
      'id': 'note-${idea.id}',
      'title': idea.title,
      'body': idea.body,
      'tags': idea.tags,
      'source': 'globalIdea',
      'created': DateTime.now().toIso8601String(),
    };
    await File(p.join(notesDir.path, 'note-${idea.id}.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(note));
  }

  Future<void> _write(Idea idea) async {
    final dir = await _ideasDir();
    final file = File(p.join(dir.path, 'idea-${idea.id}.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(idea.toJson()));
  }
}
