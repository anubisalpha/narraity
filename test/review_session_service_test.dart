import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/services/review_markdown_parser.dart';
import 'package:narraity/services/review_session_service.dart';

const _sampleMarkdown = '''
## The Doorway

<!-- id: scene-1-p001 -->
Elena stepped through.

<!-- id: scene-1-p002 -->
She hesitated.
''';

const _sampleMarkdownWithMetadata = '''
# My Novel
**Author:** Marc Saunders
**Exported:** 2026-07-25T10:00:00.000Z

<!-- narraity-review-export {"projectTitle":"My Novel","author":"Marc Saunders","exportedAt":"2026-07-25T10:00:00.000Z"} -->

## The Doorway

<!-- id: scene-1-p001 -->
Elena stepped through.
''';

void main() {
  late Directory tempDir;
  late ReviewSessionService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_review_session_test_');
    service = ReviewSessionService(LibraryService(rootOverride: tempDir));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a fresh library has no review sessions', () async {
    expect(await service.listSessions(), isEmpty);
  });

  test('createFromMarkdown parses paragraphs and persists to _ReviewSessions/', () async {
    final session = await service.createFromMarkdown('My Novel', _sampleMarkdown);

    expect(session.paragraphs, hasLength(2));
    expect(session.title, 'My Novel');
    expect(
      File('${tempDir.path}/_ReviewSessions/review-${session.id}.json').existsSync(),
      isTrue,
    );

    final reloaded = await service.listSessions();
    expect(reloaded.single.id, session.id);
    expect(reloaded.single.paragraphs, hasLength(2));
  });

  test('save persists comment edits and bumps modified', () async {
    final session = await service.createFromMarkdown('My Novel', _sampleMarkdown);
    final originalModified = session.modified;

    session.comments['scene-1-p002'] = const ReviewComment(
      anchorId: 'scene-1-p002',
      text: 'Nice beat.',
      category: 'pacing',
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.save(session);

    final reloaded = (await service.listSessions()).single;
    expect(reloaded.comments['scene-1-p002']!.text, 'Nice beat.');
    expect(reloaded.comments['scene-1-p002']!.category, 'pacing');
    expect(reloaded.modified.isAfter(originalModified), isTrue);
  });

  test('deleteSession removes only the targeted session', () async {
    final keep = await service.createFromMarkdown('Keep Me', _sampleMarkdown);
    final drop = await service.createFromMarkdown('Delete Me', _sampleMarkdown);

    await service.deleteSession(drop);

    final remaining = await service.listSessions();
    expect(remaining.single.id, keep.id);
  });

  test('exportCommentsJson matches the shape ReviewExportService.importComments expects',
      () async {
    final session = await service.createFromMarkdown('My Novel', _sampleMarkdown);
    session.comments['scene-1-p001'] = const ReviewComment(
      anchorId: 'scene-1-p001',
      text: 'Great opening.',
    );

    final json = service.exportCommentsJson(session);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final comments = decoded['comments'] as List<dynamic>;

    expect(comments, hasLength(1));
    expect(comments.single, {'anchorId': 'scene-1-p001', 'text': 'Great opening.'});
  });

  test('createFromMarkdown prefers the embedded project title over the fallback', () async {
    final session =
        await service.createFromMarkdown('some-filename', _sampleMarkdownWithMetadata);

    expect(session.title, 'My Novel');
    expect(session.metadata, isNotNull);
    expect(session.metadata!.author, 'Marc Saunders');
  });

  test('metadata survives a save/reload round-trip', () async {
    final session =
        await service.createFromMarkdown('some-filename', _sampleMarkdownWithMetadata);
    await service.save(session);

    final reloaded = (await service.listSessions()).single;
    expect(reloaded.metadata, isNotNull);
    expect(reloaded.metadata!.projectTitle, 'My Novel');
    expect(reloaded.metadata!.author, 'Marc Saunders');
  });

  test('a file with no metadata comment falls back to the given title, metadata is null',
      () async {
    final session = await service.createFromMarkdown('My Novel', _sampleMarkdown);

    expect(session.title, 'My Novel');
    expect(session.metadata, isNull);
  });

  test('listSessions sorts most recently modified first', () async {
    final first = await service.createFromMarkdown('First', _sampleMarkdown);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await service.createFromMarkdown('Second', _sampleMarkdown);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // Touch the first session again so it becomes the most recently modified.
    await service.save(first);

    final sessions = await service.listSessions();
    expect(sessions.first.id, first.id);
    expect(sessions.last.id, second.id);
  });
}
