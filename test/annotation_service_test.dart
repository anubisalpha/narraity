import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/annotation.dart';
import 'package:narraity/services/annotation_service.dart';

void main() {
  late Directory tempDir;
  late AnnotationService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_annotation_test_');
    service = AnnotationService(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('empty project has no annotations', () async {
    expect(await service.listAll(), isEmpty);
  });

  test('create persists to annotations/annotations.json and round-trips', () async {
    await service.create(
      sceneId: 'scene-1',
      kind: AnnotationKind.comment,
      anchor: const TextAnchor(start: 0, end: 5, quotedText: 'Elena'),
      body: 'Consider a stronger verb here.',
    );

    expect(File('${tempDir.path}/annotations/annotations.json').existsSync(), isTrue);
    final all = await service.listAll();
    expect(all.single.sceneId, 'scene-1');
    expect(all.single.kind, AnnotationKind.comment);
    expect(all.single.body, 'Consider a stronger verb here.');
  });

  test('listForScene filters to only that scene', () async {
    await service.create(
      sceneId: 'scene-1',
      kind: AnnotationKind.highlight,
      anchor: const TextAnchor(start: 0, end: 3, quotedText: 'abc'),
      color: 0xFFFFEE58,
    );
    await service.create(
      sceneId: 'scene-2',
      kind: AnnotationKind.stickyNote,
      anchor: const TextAnchor(start: 0, end: 3, quotedText: 'xyz'),
      body: 'note for scene 2',
    );

    final sceneOne = await service.listForScene('scene-1');
    expect(sceneOne, hasLength(1));
    expect(sceneOne.single.color, 0xFFFFEE58);
  });

  test('update overwrites body and resolved flag in place', () async {
    final created = await service.create(
      sceneId: 'scene-1',
      kind: AnnotationKind.comment,
      anchor: const TextAnchor(start: 0, end: 5, quotedText: 'Elena'),
      body: 'First pass',
    );

    await service.update(created.copyWith(body: 'Revised', resolved: true));

    final reloaded = await service.listAll();
    expect(reloaded.single.body, 'Revised');
    expect(reloaded.single.resolved, isTrue);
  });

  test('delete removes only the targeted annotation', () async {
    final keep = await service.create(
      sceneId: 'scene-1',
      kind: AnnotationKind.footnote,
      anchor: const TextAnchor(start: 3, end: 3, quotedText: ''),
      body: 'Keep me',
    );
    final drop = await service.create(
      sceneId: 'scene-1',
      kind: AnnotationKind.footnote,
      anchor: const TextAnchor(start: 10, end: 10, quotedText: ''),
      body: 'Delete me',
    );

    await service.delete(drop.id);

    final remaining = await service.listAll();
    expect(remaining.single.id, keep.id);
  });

  test('deleteAllForScene cascades, leaves other scenes alone', () async {
    await service.create(
      sceneId: 'scene-1',
      kind: AnnotationKind.comment,
      anchor: const TextAnchor(start: 0, end: 3, quotedText: 'abc'),
    );
    await service.create(
      sceneId: 'scene-2',
      kind: AnnotationKind.comment,
      anchor: const TextAnchor(start: 0, end: 3, quotedText: 'xyz'),
    );

    await service.deleteAllForScene('scene-1');

    final all = await service.listAll();
    expect(all.single.sceneId, 'scene-2');
  });

  group('resolveForScene', () {
    test('self-heals offsets that moved and persists the correction', () async {
      final annotation = await service.create(
        sceneId: 'scene-1',
        kind: AnnotationKind.highlight,
        anchor: const TextAnchor(start: 0, end: 5, quotedText: 'Elena'),
      );

      final edited = 'Long before dawn, Elena stepped through the doorway.';
      final results = await service.resolveForScene('scene-1', edited);

      expect(results, hasLength(1));
      final (resolvedAnnotation, resolution) = results.single;
      expect(resolution.status, AnchorStatus.moved);
      expect(edited.substring(resolution.start, resolution.end), 'Elena');
      expect(resolvedAnnotation.anchor.start, resolution.start);

      // Persisted, not just returned in-memory.
      final reloaded = await service.listAll();
      expect(reloaded.single.id, annotation.id);
      expect(reloaded.single.anchor.start, resolution.start);
    });

    test('leaves stored offsets untouched when the text is orphaned', () async {
      await service.create(
        sceneId: 'scene-1',
        kind: AnnotationKind.comment,
        anchor: const TextAnchor(start: 0, end: 5, quotedText: 'Elena'),
        body: 'Nice image.',
      );

      final edited = 'Marcus stepped through the doorway.';
      final results = await service.resolveForScene('scene-1', edited);

      final (_, resolution) = results.single;
      expect(resolution.status, AnchorStatus.orphaned);

      final reloaded = await service.listAll();
      expect(reloaded.single.anchor.start, 0);
      expect(reloaded.single.anchor.end, 5);
      expect(reloaded.single.anchor.quotedText, 'Elena');
    });

    test('only touches annotations for the requested scene', () async {
      await service.create(
        sceneId: 'scene-1',
        kind: AnnotationKind.highlight,
        anchor: const TextAnchor(start: 0, end: 5, quotedText: 'Elena'),
      );
      await service.create(
        sceneId: 'scene-2',
        kind: AnnotationKind.highlight,
        anchor: const TextAnchor(start: 0, end: 5, quotedText: 'Elena'),
      );

      final results = await service.resolveForScene('scene-1', 'Elena waved.');

      expect(results, hasLength(1));
      expect(results.single.$1.sceneId, 'scene-1');
    });
  });
}
