import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/story_note.dart';

const _uuid = Uuid();

/// Reads/writes a project's `notes/` folder: story notes at the root, plus one
/// level of author-created folders as real subdirectories.
///
/// Folders are directories rather than a field in the JSON so the structure is
/// visible and rearrangeable outside the app — the whole point of local-first,
/// human-readable storage. One level only: deeper nesting is a filing system,
/// and the search below is the actual answer to "where did I put that note."
///
/// Search uses a lazily built in-memory index (id → lowercased searchable
/// text), dropped whenever anything is written. Notes are small JSON files
/// that have to be read anyway to list them, so an on-disk index would buy no
/// measurable speed at realistic sizes while adding a way for search results
/// to go stale — the failure mode being "the note you know you wrote can't be
/// found," which is much worse than a few milliseconds.
class StoryNotesService {
  StoryNotesService(this.projectDir);

  final Directory projectDir;

  Directory get _root => Directory(p.join(projectDir.path, 'notes'));

  List<_IndexedNote>? _index;

  /// Every note in the project, newest-modified first, each carrying the
  /// folder it was found in.
  Future<List<StoryNote>> listAll() async {
    final indexed = await _ensureIndex();
    return indexed.map((entry) => entry.note).toList();
  }

  /// Author-created folder names, sorted case-insensitively.
  Future<List<String>> folders() async {
    if (!await _root.exists()) return [];

    final names = <String>[];
    await for (final entity in _root.list()) {
      if (entity is Directory) names.add(p.basename(entity.path));
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Future<StoryNote> createNote({
    String title = 'Untitled note',
    String body = '',
    List<String> tags = const [],
    String? folder,
  }) async {
    final now = DateTime.now();
    final note = StoryNote(
      id: 'note-${_uuid.v4()}',
      title: title,
      body: body,
      tags: tags,
      folder: folder,
      created: now,
      modified: now,
    );
    await save(note);
    return note;
  }

  Future<void> save(StoryNote note) async {
    final dir = _dirFor(note.folder);
    await dir.create(recursive: true);
    await File(p.join(dir.path, '${note.id}.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(note.toJson()));
    _invalidate();
  }

  Future<void> delete(StoryNote note) async {
    final file = File(p.join(_dirFor(note.folder).path, '${note.id}.json'));
    if (await file.exists()) await file.delete();
    _invalidate();
  }

  /// Moves [note] into [folder] (null = the notes root) and returns the
  /// updated note. This is a file move, since the folder isn't stored in the
  /// JSON.
  Future<StoryNote> moveToFolder(StoryNote note, String? folder) async {
    final source = File(p.join(_dirFor(note.folder).path, '${note.id}.json'));
    final target = _dirFor(folder);
    await target.create(recursive: true);

    final moved = folder == null
        ? note.copyWith(clearFolder: true)
        : note.copyWith(folder: folder);

    if (await source.exists()) await source.delete();
    await File(p.join(target.path, '${moved.id}.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(moved.toJson()));
    _invalidate();
    return moved;
  }

  Future<void> createFolder(String name) async {
    final safe = _safeFolderName(name);
    if (safe.isEmpty) return;
    await Directory(p.join(_root.path, safe)).create(recursive: true);
    _invalidate();
  }

  Future<void> renameFolder(String from, String to) async {
    final safe = _safeFolderName(to);
    if (safe.isEmpty || safe == from) return;
    final source = Directory(p.join(_root.path, from));
    if (!await source.exists()) return;
    await source.rename(p.join(_root.path, safe));
    _invalidate();
  }

  /// Deletes a folder, moving any notes inside it back to the notes root
  /// rather than deleting them. Removing a container should never destroy
  /// writing that happens to be filed in it.
  Future<void> deleteFolder(String name) async {
    final dir = Directory(p.join(_root.path, name));
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      await entity.rename(p.join(_root.path, p.basename(entity.path)));
    }
    await dir.delete(recursive: true);
    _invalidate();
  }

  /// Notes matching every whitespace-separated term in [query], best match
  /// first. Terms are ANDed because adding a word should narrow a search, and
  /// a title or tag hit outranks a body hit — searching "elena" should surface
  /// the note *about* Elena above one that mentions her in passing.
  Future<List<StoryNote>> search(String query) async {
    final terms = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (terms.isEmpty) return [];

    final indexed = await _ensureIndex();
    final scored = <(double score, StoryNote note)>[];

    for (final entry in indexed) {
      var score = 0.0;
      var matchedAll = true;
      for (final term in terms) {
        if (entry.title.contains(term)) {
          score += 3;
        } else if (entry.tags.any((tag) => tag.contains(term))) {
          score += 2;
        } else if (entry.body.contains(term)) {
          score += 1;
        } else {
          matchedAll = false;
          break;
        }
      }
      if (matchedAll) scored.add((score, entry.note));
    }

    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      return byScore != 0 ? byScore : b.$2.modified.compareTo(a.$2.modified);
    });
    return scored.map((entry) => entry.$2).toList();
  }

  Future<List<_IndexedNote>> _ensureIndex() async {
    final cached = _index;
    if (cached != null) return cached;

    final notes = <_IndexedNote>[];
    if (await _root.exists()) {
      await for (final entity in _root.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;

        // Anything one level down sits in a folder; deeper paths are treated
        // as belonging to their immediate parent folder rather than ignored,
        // so a hand-organized notes tree still shows up.
        final folder =
            p.equals(entity.parent.path, _root.path) ? null : p.basename(entity.parent.path);

        try {
          final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
          notes.add(_IndexedNote(StoryNote.fromJson(json, folder: folder)));
        } catch (_) {
          continue; // skip corrupt files rather than breaking the panel
        }
      }
    }

    notes.sort((a, b) => b.note.modified.compareTo(a.note.modified));
    _index = notes;
    return notes;
  }

  void _invalidate() => _index = null;

  Directory _dirFor(String? folder) =>
      folder == null ? _root : Directory(p.join(_root.path, folder));

  /// Folder names become real directory names, so strip anything Windows or
  /// POSIX would reject — including separators, which would otherwise let a
  /// name escape the notes folder entirely.
  String _safeFolderName(String name) =>
      name.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '').trim();
}

/// A note with its searchable text precomputed once, so a search doesn't
/// lowercase every body on every keystroke.
class _IndexedNote {
  _IndexedNote(this.note)
      : title = note.title.toLowerCase(),
        body = note.body.toLowerCase(),
        tags = note.tags.map((t) => t.toLowerCase()).toList();

  final StoryNote note;
  final String title;
  final String body;
  final List<String> tags;
}
