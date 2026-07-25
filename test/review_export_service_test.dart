import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/services/annotation_service.dart';
import 'package:narraity/services/manuscript_service.dart';
import 'package:narraity/services/review_export_service.dart';
import 'package:narraity/services/review_markdown_parser.dart';

void main() {
  late Directory tempDir;
  late ManuscriptService manuscriptService;
  late AnnotationService annotationService;
  late ReviewExportService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'narraity_review_export_test_',
    );
    manuscriptService = ManuscriptService(tempDir);
    annotationService = AnnotationService(tempDir);
    service = ReviewExportService(manuscriptService, annotationService);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('buildExportMarkdown emits a heading and anchored paragraphs', () async {
    await manuscriptService.writeScene(
      SceneDoc(
        id: 'scene-1',
        title: 'The Doorway',
        content: 'Elena stepped through.\n\nShe hesitated.',
      ),
    );

    final markdown = await service.buildExportMarkdown([
      ('scene-1', 'The Doorway'),
    ], projectTitle: 'Test Project');

    expect(markdown, contains('## The Doorway'));
    expect(markdown, contains('<!-- id: scene-1-p001 -->'));
    expect(markdown, contains('Elena stepped through.'));
    expect(markdown, contains('<!-- id: scene-1-p002 -->'));
    expect(markdown, contains('She hesitated.'));
  });

  test('buildExportMarkdown embeds project title/subtitle/author metadata, parseable back out',
      () async {
    await manuscriptService.writeScene(
      SceneDoc(id: 'scene-1', title: 'One', content: 'Some prose.'),
    );

    final markdown = await service.buildExportMarkdown(
      [('scene-1', 'One')],
      projectTitle: 'My Novel',
      subtitle: 'A Tale',
      author: 'Marc Saunders',
    );

    expect(markdown, contains('# My Novel'));
    expect(markdown, contains('*A Tale*'));
    expect(markdown, contains('**Author:** Marc Saunders'));

    final metadata = parseReviewMetadata(markdown);
    expect(metadata, isNotNull);
    expect(metadata!.projectTitle, 'My Novel');
    expect(metadata.subtitle, 'A Tale');
    expect(metadata.author, 'Marc Saunders');
  });

  test('buildExportMarkdown omits subtitle/author lines when not given', () async {
    await manuscriptService.writeScene(
      SceneDoc(id: 'scene-1', title: 'One', content: 'Some prose.'),
    );

    final markdown = await service.buildExportMarkdown(
      [('scene-1', 'One')],
      projectTitle: 'My Novel',
    );

    final metadata = parseReviewMetadata(markdown);
    expect(metadata!.projectTitle, 'My Novel');
    expect(metadata.subtitle, isNull);
    expect(metadata.author, isNull);
  });

  test(
    'buildExportMarkdown persists a paragraph anchor per scene to review/anchors.json',
    () async {
      await manuscriptService.writeScene(
        SceneDoc(
          id: 'scene-1',
          title: 'The Doorway',
          content: 'Elena stepped through.',
        ),
      );

      await service.buildExportMarkdown([
        ('scene-1', 'The Doorway'),
      ], projectTitle: 'Test Project');

      final anchorsFile = File('${tempDir.path}/review/anchors.json');
      expect(anchorsFile.existsSync(), isTrue);
      final json =
          jsonDecode(await anchorsFile.readAsString()) as Map<String, dynamic>;
      final anchors = json['anchors'] as Map<String, dynamic>;
      expect(anchors.containsKey('scene-1-p001'), isTrue);
      expect(anchors['scene-1-p001']['sceneId'], 'scene-1');
      expect(
        anchors['scene-1-p001']['anchor']['quotedText'],
        'Elena stepped through.',
      );
    },
  );

  test(
    'multiple scenes each get their own id prefix, in the given order',
    () async {
      await manuscriptService.writeScene(
        SceneDoc(id: 'scene-1', title: 'One', content: 'First scene text.'),
      );
      await manuscriptService.writeScene(
        SceneDoc(id: 'scene-2', title: 'Two', content: 'Second scene text.'),
      );

      final markdown = await service.buildExportMarkdown([
        ('scene-1', 'One'),
        ('scene-2', 'Two'),
      ], projectTitle: 'Test Project');

      final firstIndex = markdown.indexOf('## One');
      final secondIndex = markdown.indexOf('## Two');
      expect(firstIndex, greaterThanOrEqualTo(0));
      expect(secondIndex, greaterThan(firstIndex));
      expect(markdown, contains('<!-- id: scene-1-p001 -->'));
      expect(markdown, contains('<!-- id: scene-2-p001 -->'));
    },
  );

  test(
    're-exporting the same scene upserts rather than duplicating anchors',
    () async {
      await manuscriptService.writeScene(
        SceneDoc(id: 'scene-1', title: 'One', content: 'Original text.'),
      );
      await service.buildExportMarkdown([
        ('scene-1', 'One'),
      ], projectTitle: 'Test Project');

      await manuscriptService.writeScene(
        SceneDoc(id: 'scene-1', title: 'One', content: 'Updated text.'),
      );
      await service.buildExportMarkdown([
        ('scene-1', 'One'),
      ], projectTitle: 'Test Project');

      final anchorsFile = File('${tempDir.path}/review/anchors.json');
      final json =
          jsonDecode(await anchorsFile.readAsString()) as Map<String, dynamic>;
      final anchors = json['anchors'] as Map<String, dynamic>;
      expect(
        anchors.keys.where((k) => k.startsWith('scene-1-p')),
        hasLength(1),
      );
      expect(anchors['scene-1-p001']['anchor']['quotedText'], 'Updated text.');
    },
  );

  group('importComments', () {
    test(
      'creates a comment annotation anchored to the right scene and paragraph',
      () async {
        await manuscriptService.writeScene(
          SceneDoc(
            id: 'scene-1',
            title: 'The Doorway',
            content: 'Elena stepped through.\n\nShe hesitated.',
          ),
        );
        await service.buildExportMarkdown([
          ('scene-1', 'The Doorway'),
        ], projectTitle: 'Test Project');

        final result = await service.importComments(
          jsonEncode({
            'comments': [
              {
                'anchorId': 'scene-1-p002',
                'text': 'Good tension here.',
                'category': 'pacing',
              },
            ],
          }),
        );

        expect(result.imported, 1);
        expect(result.unknown, 0);

        final annotations = await annotationService.listForScene('scene-1');
        expect(annotations, hasLength(1));
        expect(annotations.single.body, '[pacing] Good tension here.');
        expect(annotations.single.anchor.quotedText, 'She hesitated.');
      },
    );

    test('omits the category prefix when none is given', () async {
      await manuscriptService.writeScene(
        SceneDoc(id: 'scene-1', title: 'One', content: 'Some prose.'),
      );
      await service.buildExportMarkdown([
        ('scene-1', 'One'),
      ], projectTitle: 'Test Project');

      await service.importComments(
        jsonEncode({
          'comments': [
            {'anchorId': 'scene-1-p001', 'text': 'No category here.'},
          ],
        }),
      );

      final annotations = await annotationService.listForScene('scene-1');
      expect(annotations.single.body, 'No category here.');
    });

    test(
      'counts unrecognized anchor ids as unknown instead of crashing',
      () async {
        await manuscriptService.writeScene(
          SceneDoc(id: 'scene-1', title: 'One', content: 'Some prose.'),
        );
        await service.buildExportMarkdown([
          ('scene-1', 'One'),
        ], projectTitle: 'Test Project');

        final result = await service.importComments(
          jsonEncode({
            'comments': [
              {
                'anchorId': 'scene-1-p099',
                'text': 'This paragraph does not exist.',
              },
            ],
          }),
        );

        expect(result.imported, 0);
        expect(result.unknown, 1);
        expect(await annotationService.listForScene('scene-1'), isEmpty);
      },
    );

    test('imports several comments across scenes in one reply', () async {
      await manuscriptService.writeScene(
        SceneDoc(id: 'scene-1', title: 'One', content: 'First scene prose.'),
      );
      await manuscriptService.writeScene(
        SceneDoc(id: 'scene-2', title: 'Two', content: 'Second scene prose.'),
      );
      await service.buildExportMarkdown([
        ('scene-1', 'One'),
        ('scene-2', 'Two'),
      ], projectTitle: 'Test Project');

      final result = await service.importComments(
        jsonEncode({
          'comments': [
            {'anchorId': 'scene-1-p001', 'text': 'Comment on scene one.'},
            {'anchorId': 'scene-2-p001', 'text': 'Comment on scene two.'},
          ],
        }),
      );

      expect(result.imported, 2);
      expect(await annotationService.listForScene('scene-1'), hasLength(1));
      expect(await annotationService.listForScene('scene-2'), hasLength(1));
    });
  });
}
