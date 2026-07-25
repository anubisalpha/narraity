import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/relationship.dart';

const _uuid = Uuid();

/// Reads/writes a project's `relationships/relationship-<id>.json` (edges)
/// and `relationships/layout.json` (node positions, keyed by character id —
/// see [Relationship]'s doc comment for why this is separate from PLAN.md's
/// literal per-edge `position` field).
class RelationshipService {
  RelationshipService(this.projectDir);

  final Directory projectDir;

  Directory get _dir => Directory(p.join(projectDir.path, 'relationships'));
  File get _layoutFile => File(p.join(_dir.path, 'layout.json'));

  // ---- edges --------------------------------------------------------------

  Future<List<Relationship>> listRelationships() async {
    if (!await _dir.exists()) return [];
    final relationships = <Relationship>[];
    await for (final entity in _dir.list()) {
      if (entity is! File || !p.basename(entity.path).startsWith('relationship-')) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        relationships.add(Relationship.fromJson(json));
      } catch (_) {
        continue;
      }
    }
    return relationships;
  }

  Future<Relationship> addRelationship({
    required String characterAId,
    required String characterBId,
    required RelationshipType type,
    String label = '',
  }) async {
    final relationship = Relationship(
      id: 'relationship-${_uuid.v4()}',
      characterAId: characterAId,
      characterBId: characterBId,
      type: type,
      label: label,
    );
    await saveRelationship(relationship);
    return relationship;
  }

  Future<void> saveRelationship(Relationship relationship) async {
    await _dir.create(recursive: true);
    await File(p.join(_dir.path, '${relationship.id}.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(relationship.toJson()));
  }

  Future<void> deleteRelationship(String id) async {
    final file = File(p.join(_dir.path, '$id.json'));
    if (await file.exists()) await file.delete();
  }

  /// Every relationship touching [characterId] — powers the mini
  /// relationship view PLAN.md calls for in the Reference Panel.
  Future<List<Relationship>> relationshipsFor(String characterId) async {
    final all = await listRelationships();
    return all
        .where((r) => r.characterAId == characterId || r.characterBId == characterId)
        .toList();
  }

  // ---- layout ---------------------------------------------------------------

  Future<Map<String, (double x, double y)>> loadLayout() async {
    if (!await _layoutFile.exists()) return {};
    try {
      final json = jsonDecode(await _layoutFile.readAsString()) as Map<String, dynamic>;
      return json.map((id, pos) {
        final map = pos as Map<String, dynamic>;
        return MapEntry(id, ((map['x'] as num).toDouble(), (map['y'] as num).toDouble()));
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> setNodePosition(String characterId, double x, double y) async {
    final layout = await loadLayout();
    layout[characterId] = (x, y);
    await _dir.create(recursive: true);
    await _layoutFile.writeAsString(const JsonEncoder.withIndent('  ').convert(
        layout.map((id, pos) => MapEntry(id, {'x': pos.$1, 'y': pos.$2}))));
  }

  /// Drops [characterId] from the layout (called when a character is
  /// deleted) — otherwise stale positions accumulate forever in
  /// `layout.json` for characters that no longer exist.
  Future<void> removeNodePosition(String characterId) async {
    final layout = await loadLayout();
    if (layout.remove(characterId) == null) return;
    await _dir.create(recursive: true);
    await _layoutFile.writeAsString(const JsonEncoder.withIndent('  ').convert(
        layout.map((id, pos) => MapEntry(id, {'x': pos.$1, 'y': pos.$2}))));
  }
}
