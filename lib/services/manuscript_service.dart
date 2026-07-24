import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/manuscript.dart';
import '../models/manuscript_seeds.dart';

const _uuid = Uuid();

/// File I/O for one project's manuscript.
///
/// Layout inside the project folder:
/// ```
/// manuscript/
///   structure.json          # ordered node tree (arbitrary depth/labels) + front/back matter
///   scenes/
///     <leaf-id>.md           # front-matter (title, pov) + markdown prose
///     section-<id>.md       # special sections (prologue, epilogue, ...)
/// ```
/// Ids are stable across reorders/renames so version history (Phase 1.7) and
/// comment anchors (Phase 4) stay attached.
class ManuscriptService {
  ManuscriptService(this.projectDir);

  final Directory projectDir;

  Directory get _manuscriptDir => Directory(p.join(projectDir.path, 'manuscript'));
  Directory get _scenesDir => Directory(p.join(_manuscriptDir.path, 'scenes'));
  File get _structureFile => File(p.join(_manuscriptDir.path, 'structure.json'));

  /// Loads the structure. If none exists yet, seeds one from [seed]
  /// (defaults to Act > Chapter > Scene) — call this only once, right after
  /// project creation; see LibraryService.createProject and the New Project
  /// dialog's structure picker. Later calls with no structure.json present
  /// (shouldn't normally happen) fall back to the same default rather than
  /// opening on nothing.
  Future<ManuscriptStructure> loadStructure({
    ManuscriptSeed seed = ManuscriptSeed.actChapterScene,
  }) async {
    if (await _structureFile.exists()) {
      try {
        final json = jsonDecode(await _structureFile.readAsString());
        return ManuscriptStructure.fromJson(json as Map<String, dynamic>);
      } catch (_) {
        // fall through to rebuild a fresh structure rather than crash
      }
    }

    final structure = ManuscriptStructure(nodes: seed.buildStarter());
    await saveStructure(structure);
    for (final id in structure.allContentIds) {
      await writeScene(SceneDoc(id: id, title: _findTitle(structure, id) ?? 'Untitled'));
    }
    return structure;
  }

  String? _findTitle(ManuscriptStructure structure, String id) {
    for (final section in [...structure.frontMatter, ...structure.backMatter]) {
      if (section.id == id) return section.title;
    }
    ManuscriptNode? search(List<ManuscriptNode> nodes) {
      for (final node in nodes) {
        if (node.id == id) return node;
        final found = search(node.children);
        if (found != null) return found;
      }
      return null;
    }

    return search(structure.nodes)?.title;
  }

  Future<void> saveStructure(ManuscriptStructure structure) async {
    await _manuscriptDir.create(recursive: true);
    await _structureFile
        .writeAsString(const JsonEncoder.withIndent('  ').convert(structure.toJson()));
  }

  // ---- scene content -------------------------------------------------------

  Future<SceneDoc> readScene(String id, {String fallbackTitle = 'Untitled'}) async {
    final file = File(p.join(_scenesDir.path, '$id.md'));
    if (!await file.exists()) {
      return SceneDoc(id: id, title: fallbackTitle);
    }
    return _parse(id, await file.readAsString(), fallbackTitle);
  }

  Future<void> writeScene(SceneDoc doc) async {
    await _scenesDir.create(recursive: true);
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('title: ${doc.title}');
    if (doc.pov != null && doc.pov!.isNotEmpty) {
      buffer.writeln('pov: ${doc.pov}');
    }
    buffer
      ..writeln('---')
      ..write(doc.content);
    await File(p.join(_scenesDir.path, '${doc.id}.md')).writeAsString(buffer.toString());
  }

  Future<void> deleteSceneFile(String id) async {
    final file = File(p.join(_scenesDir.path, '$id.md'));
    if (await file.exists()) await file.delete();
  }

  SceneDoc _parse(String id, String raw, String fallbackTitle) {
    if (!raw.startsWith('---')) {
      return SceneDoc(id: id, title: fallbackTitle, content: raw);
    }
    final end = raw.indexOf('\n---', 3);
    if (end == -1) {
      return SceneDoc(id: id, title: fallbackTitle, content: raw);
    }
    final header = raw.substring(3, end);
    var content = raw.substring(end + 4);
    if (content.startsWith('\r\n')) {
      content = content.substring(2);
    } else if (content.startsWith('\n')) {
      content = content.substring(1);
    }

    String? title;
    String? pov;
    for (final line in header.split('\n')) {
      final idx = line.indexOf(':');
      if (idx == -1) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key == 'title') title = value;
      if (key == 'pov') pov = value;
    }
    return SceneDoc(id: id, title: title ?? fallbackTitle, content: content, pov: pov);
  }

  // ---- structure edits (generic, any depth) --------------------------------

  /// Adds a child to [parent], or to the structure's top level if [parent]
  /// is null. Every node gets its own scene file immediately — writing and
  /// adding further subsections underneath are never mutually exclusive.
  Future<ManuscriptNode> addNode(
    ManuscriptStructure structure, {
    required String typeLabel,
    ManuscriptNode? parent,
  }) async {
    final siblings = parent?.children ?? structure.nodes;
    final node = ManuscriptNode(
      id: '${typeLabel.toLowerCase().replaceAll(RegExp(r'\s+'), '-')}-${_uuid.v4()}',
      title: '$typeLabel ${siblings.length + 1}',
      typeLabel: typeLabel,
    );
    siblings.add(node);
    await saveStructure(structure);
    await writeScene(SceneDoc(id: node.id, title: node.title));
    return node;
  }

  Future<SpecialSection> addSpecialSection(
    ManuscriptStructure structure,
    SpecialSectionType type,
  ) async {
    final section = SpecialSection(id: 'section-${_uuid.v4()}', type: type);
    (type.isFrontMatter ? structure.frontMatter : structure.backMatter).add(section);
    await saveStructure(structure);
    await writeScene(SceneDoc(id: section.id, title: section.title));
    return section;
  }

  /// Deletes [node] from wherever it is in the tree (searches recursively
  /// for its parent). Deletes its own scene file and every descendant's too.
  Future<void> deleteNode(ManuscriptStructure structure, ManuscriptNode node) async {
    bool removeFrom(List<ManuscriptNode> siblings) {
      if (siblings.remove(node)) return true;
      for (final sibling in siblings) {
        if (removeFrom(sibling.children)) return true;
      }
      return false;
    }

    removeFrom(structure.nodes);
    await saveStructure(structure);
    for (final id in node.contentIds) {
      await deleteSceneFile(id);
    }
  }

  Future<void> deleteSpecialSection(
    ManuscriptStructure structure,
    SpecialSection section,
  ) async {
    structure.frontMatter.remove(section);
    structure.backMatter.remove(section);
    await saveStructure(structure);
    await deleteSceneFile(section.id);
  }

  /// Reorders a child within [parent]'s children (or the top level, if
  /// [parent] is null) — matches `ReorderableListView.onReorder`'s index
  /// convention (newIndex is post-removal).
  Future<void> reorderNode(
    ManuscriptStructure structure,
    ManuscriptNode? parent,
    int oldIndex,
    int newIndex,
  ) async {
    final siblings = parent?.children ?? structure.nodes;
    final node = siblings.removeAt(oldIndex);
    siblings.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, node);
    await saveStructure(structure);
  }

  /// Total word count across every leaf and special section.
  Future<int> totalWordCount(ManuscriptStructure structure) async {
    var total = 0;
    for (final id in structure.allContentIds) {
      total += (await readScene(id)).wordCount;
    }
    return total;
  }

  /// Word count for [node]'s own prose plus every descendant's — powers the
  /// "view everything under this section" rollup.
  Future<int> wordCountUnder(ManuscriptNode node) async {
    var total = 0;
    for (final id in node.contentIds) {
      total += (await readScene(id)).wordCount;
    }
    return total;
  }

  /// Concatenated prose of [node] and every descendant, in document order,
  /// each preceded by its title as a heading — the read-only "combined
  /// view" for a section.
  Future<String> combinedContentUnder(ManuscriptNode node) async {
    final buffer = StringBuffer();
    for (final id in node.contentIds) {
      final doc = await readScene(id);
      if (buffer.isNotEmpty) buffer.writeln('\n');
      buffer.writeln('# ${doc.title}\n');
      buffer.writeln(doc.content);
    }
    return buffer.toString();
  }
}
