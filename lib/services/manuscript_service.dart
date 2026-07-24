import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/manuscript.dart';

const _uuid = Uuid();

/// File I/O for one project's manuscript.
///
/// Layout inside the project folder:
/// ```
/// manuscript/
///   structure.json          # ordered act/chapter/scene tree + front/back matter
///   scenes/
///     scene-<id>.md         # front-matter (title, pov) + markdown prose
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

  /// Loads the structure, creating a starter Act 1 / Chapter 1 / Scene 1 for
  /// a brand-new manuscript so the editor never opens on nothing.
  Future<ManuscriptStructure> loadStructure() async {
    if (await _structureFile.exists()) {
      try {
        final json = jsonDecode(await _structureFile.readAsString());
        return ManuscriptStructure.fromJson(json as Map<String, dynamic>);
      } catch (_) {
        // fall through to rebuild a fresh structure rather than crash
      }
    }

    final structure = ManuscriptStructure(
      acts: [
        ActNode(id: 'act-${_uuid.v4()}', title: 'Act 1', chapters: [
          ChapterNode(id: 'ch-${_uuid.v4()}', title: 'Chapter 1', scenes: [
            SceneRef(id: 'scene-${_uuid.v4()}', title: 'Scene 1'),
          ]),
        ]),
      ],
    );
    await saveStructure(structure);
    await writeScene(SceneDoc(
      id: structure.acts.first.chapters.first.scenes.first.id,
      title: 'Scene 1',
    ));
    return structure;
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

  // ---- structure edits -----------------------------------------------------

  Future<SceneRef> addScene(ManuscriptStructure structure, ChapterNode chapter) async {
    final scene = SceneRef(
      id: 'scene-${_uuid.v4()}',
      title: 'Scene ${chapter.scenes.length + 1}',
    );
    chapter.scenes.add(scene);
    await saveStructure(structure);
    await writeScene(SceneDoc(id: scene.id, title: scene.title));
    return scene;
  }

  Future<ChapterNode> addChapter(ManuscriptStructure structure, ActNode act) async {
    final chapter = ChapterNode(
      id: 'ch-${_uuid.v4()}',
      title: 'Chapter ${act.chapters.length + 1}',
    );
    act.chapters.add(chapter);
    await saveStructure(structure);
    return chapter;
  }

  Future<ActNode> addAct(ManuscriptStructure structure) async {
    final act = ActNode(id: 'act-${_uuid.v4()}', title: 'Act ${structure.acts.length + 1}');
    structure.acts.add(act);
    await saveStructure(structure);
    return act;
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

  Future<void> deleteScene(
    ManuscriptStructure structure,
    ChapterNode chapter,
    SceneRef scene,
  ) async {
    chapter.scenes.remove(scene);
    await saveStructure(structure);
    await deleteSceneFile(scene.id);
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

  Future<void> reorderScene(
    ManuscriptStructure structure,
    ChapterNode chapter,
    int oldIndex,
    int newIndex,
  ) async {
    final scene = chapter.scenes.removeAt(oldIndex);
    chapter.scenes.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, scene);
    await saveStructure(structure);
  }

  /// Total word count across every scene and special section.
  Future<int> totalWordCount(ManuscriptStructure structure) async {
    var total = 0;
    for (final id in structure.allContentIds) {
      total += (await readScene(id)).wordCount;
    }
    return total;
  }
}
