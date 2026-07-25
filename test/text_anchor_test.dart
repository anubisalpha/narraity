import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/annotation.dart';

void main() {
  group('TextAnchor.resolveIn', () {
    test('exact: offsets still match the quoted text', () {
      const content = 'Elena stepped through the doorway.';
      const anchor = TextAnchor(start: 0, end: 5, quotedText: 'Elena');

      final result = anchor.resolveIn(content);

      expect(result.status, AnchorStatus.exact);
      expect(result.start, 0);
      expect(result.end, 5);
    });

    test('moved: text still present verbatim but at a different offset', () {
      const anchor = TextAnchor(start: 0, end: 5, quotedText: 'Elena');
      const edited = 'Long before dawn, Elena stepped through the doorway.';

      final result = anchor.resolveIn(edited);

      expect(result.status, AnchorStatus.moved);
      expect(edited.substring(result.start, result.end), 'Elena');
    });

    test('moved: picks the occurrence nearest the original offset when text repeats', () {
      const content = 'Elena waved. Later, Elena left. Elena returned.';
      // Originally anchored to the *second* "Elena" (index 20).
      const anchor = TextAnchor(start: 20, end: 25, quotedText: 'Elena');
      final edited = 'Prefix. $content';

      final result = anchor.resolveIn(edited);

      // The second occurrence shifts from 20 to 28 once "Prefix. " (8 chars)
      // is prepended; that should win over the first (shifted to 8) or third
      // (shifted to 40) since it's closest to the recorded start of 20.
      expect(result.status, AnchorStatus.moved);
      expect(result.start, 28);
    });

    test('orphaned: quoted text no longer exists anywhere in the content', () {
      const anchor = TextAnchor(start: 0, end: 5, quotedText: 'Elena');
      const edited = 'Marcus stepped through the doorway.';

      final result = anchor.resolveIn(edited);

      expect(result.status, AnchorStatus.orphaned);
      expect(result.start, lessThanOrEqualTo(edited.length));
      expect(result.end, lessThanOrEqualTo(edited.length));
    });

    test('orphaned: clamps out-of-range offsets into the current content length', () {
      const anchor = TextAnchor(start: 100, end: 110, quotedText: 'gone now');
      const edited = 'short';

      final result = anchor.resolveIn(edited);

      expect(result.status, AnchorStatus.orphaned);
      expect(result.start, lessThanOrEqualTo(edited.length));
      expect(result.end, lessThanOrEqualTo(edited.length));
      expect(result.start, lessThanOrEqualTo(result.end));
    });

    test('point anchor (empty quotedText) just clamps, always exact', () {
      const anchor = TextAnchor(start: 3, end: 3, quotedText: '');

      final withinBounds = anchor.resolveIn('hello world');
      expect(withinBounds.status, AnchorStatus.exact);
      expect(withinBounds.start, 3);
      expect(withinBounds.end, 3);

      final shrunk = anchor.resolveIn('hi');
      expect(shrunk.status, AnchorStatus.exact);
      expect(shrunk.start, 2);
      expect(shrunk.end, 2);
    });
  });

  group('Annotation JSON round-trip', () {
    test('toJson/fromJson preserves every field including optional color', () {
      final created = DateTime.parse('2026-07-25T10:00:00.000Z');
      final annotation = Annotation(
        id: 'annotation-1',
        sceneId: 'scene-1',
        kind: AnnotationKind.highlight,
        anchor: const TextAnchor(start: 0, end: 5, quotedText: 'Elena'),
        color: 0xFFFFEE58,
        created: created,
        modified: created,
      );

      final restored = Annotation.fromJson(annotation.toJson());

      expect(restored.id, annotation.id);
      expect(restored.sceneId, annotation.sceneId);
      expect(restored.kind, AnnotationKind.highlight);
      expect(restored.anchor.quotedText, 'Elena');
      expect(restored.color, 0xFFFFEE58);
      expect(restored.resolved, isFalse);
    });

    test('fromJson defaults missing optional fields', () {
      final json = {
        'id': 'annotation-2',
        'sceneId': 'scene-1',
        'kind': 'comment',
        'anchor': {'start': 0, 'end': 3, 'quotedText': 'abc'},
        'created': '2026-07-25T10:00:00.000Z',
        'modified': '2026-07-25T10:00:00.000Z',
      };

      final annotation = Annotation.fromJson(json);

      expect(annotation.body, '');
      expect(annotation.color, isNull);
      expect(annotation.resolved, isFalse);
    });
  });
}
