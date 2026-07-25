import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/annotation.dart';

const _uuid = Uuid();

/// Reads/writes a project's `annotations/annotations.json` — every comment,
/// highlight, sticky note, and footnote in one array, same convention as
/// `PlotGridService`'s `plotlines.json`/`plotpoints.json`.
class AnnotationService {
  AnnotationService(this.projectDir);

  final Directory projectDir;

  Directory get _dir => Directory(p.join(projectDir.path, 'annotations'));
  File get _file => File(p.join(_dir.path, 'annotations.json'));

  Future<List<Annotation>> listAll() async {
    if (!await _file.exists()) return [];
    try {
      final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return (json['annotations'] as List<dynamic>? ?? [])
          .map((a) => Annotation.fromJson(a as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Annotation>> listForScene(String sceneId) async {
    final all = await listAll();
    return all.where((a) => a.sceneId == sceneId).toList();
  }

  Future<Annotation> create({
    required String sceneId,
    required AnnotationKind kind,
    required TextAnchor anchor,
    String body = '',
    int? color,
  }) async {
    final all = await listAll();
    final now = DateTime.now();
    final annotation = Annotation(
      id: 'annotation-${_uuid.v4()}',
      sceneId: sceneId,
      kind: kind,
      anchor: anchor,
      body: body,
      color: color,
      created: now,
      modified: now,
    );
    all.add(annotation);
    await _save(all);
    return annotation;
  }

  Future<void> update(Annotation updated) async {
    final all = await listAll();
    final index = all.indexWhere((a) => a.id == updated.id);
    if (index == -1) return;
    all[index] = updated;
    await _save(all);
  }

  Future<void> delete(String id) async {
    final all = await listAll();
    all.removeWhere((a) => a.id == id);
    await _save(all);
  }

  /// Drops every annotation on [sceneId] — call when a scene is deleted so
  /// comments/highlights/notes/footnotes don't ride along as dead data
  /// (same lesson as Plot Grid's dangling-point gap: better to cascade from
  /// the start than to leave it for a later fix).
  Future<void> deleteAllForScene(String sceneId) async {
    final all = await listAll();
    all.removeWhere((a) => a.sceneId == sceneId);
    await _save(all);
  }

  /// Re-locates every annotation on [sceneId] against its current [content]
  /// and self-heals offsets that only *moved* (silently persisting the
  /// correction, same pattern as Timeline's degenerate-order re-sequencing).
  /// Annotations whose text is genuinely gone (`orphaned`) are left with
  /// their stored offsets untouched — resolution results still carry a
  /// best-effort clamped position for display, but nothing is guessed into
  /// the saved file.
  ///
  /// Returns each scene annotation paired with its resolution so callers
  /// (a comments panel, highlight renderer, ...) know which ones to flag.
  Future<List<(Annotation, AnchorResolution)>> resolveForScene(
    String sceneId,
    String content,
  ) async {
    final all = await listAll();
    var changed = false;
    final results = <(Annotation, AnchorResolution)>[];

    for (final annotation in all) {
      if (annotation.sceneId != sceneId) continue;
      final resolution = annotation.anchor.resolveIn(content);
      if (resolution.status == AnchorStatus.moved) {
        annotation.anchor = TextAnchor(
          start: resolution.start,
          end: resolution.end,
          quotedText: annotation.anchor.quotedText,
        );
        changed = true;
      }
      results.add((annotation, resolution));
    }

    if (changed) await _save(all);
    return results;
  }

  Future<void> _save(List<Annotation> annotations) async {
    await _dir.create(recursive: true);
    await _file.writeAsString(const JsonEncoder.withIndent('  ')
        .convert({'annotations': annotations.map((a) => a.toJson()).toList()}));
  }
}
