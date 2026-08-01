import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/services/release_notes_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_release_notes_test_');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  ReleaseNotesService serviceReturning(String body, {int statusCode = 200}) {
    return ReleaseNotesService(
      client: MockClient((request) async => http.Response(body, statusCode)),
      libraryService: LibraryService(rootOverride: tempDir),
    );
  }

  const releasesJson = '''
[
  {
    "tag_name": "v1.1.0",
    "html_url": "https://github.com/anubisalpha/narraity/releases/tag/v1.1.0",
    "body": "Newer release notes.",
    "published_at": "2026-08-01T10:00:00Z",
    "draft": false
  },
  {
    "tag_name": "v1.0.1",
    "html_url": "https://github.com/anubisalpha/narraity/releases/tag/v1.0.1",
    "body": "First real release.",
    "published_at": "2026-07-31T10:00:00Z",
    "draft": false
  },
  {
    "tag_name": "v1.1.1",
    "html_url": "https://github.com/anubisalpha/narraity/releases/tag/v1.1.1",
    "body": "Not published yet.",
    "published_at": null,
    "draft": true
  }
]
''';

  test('fetchFromGitHub parses releases in the order GitHub returns them, skipping drafts',
      () async {
    final service = serviceReturning(releasesJson);
    final releases = await service.fetchFromGitHub();

    expect(releases, hasLength(2));
    expect(releases[0].version, '1.1.0');
    expect(releases[0].notes, 'Newer release notes.');
    expect(releases[1].version, '1.0.1');
  });

  test('fetchFromGitHub throws on a non-200 response', () async {
    final service = serviceReturning('not found', statusCode: 404);
    expect(() => service.fetchFromGitHub(), throwsException);
  });

  test('loadCached returns empty with no timestamp before any fetch', () async {
    final service = serviceReturning(releasesJson);
    final (releases, fetchedAt) = await service.loadCached();

    expect(releases, isEmpty);
    expect(fetchedAt, isNull);
  });

  test('a successful fetch populates the cache for loadCached to read back', () async {
    final service = serviceReturning(releasesJson);
    await service.fetchFromGitHub();

    final (releases, fetchedAt) = await service.loadCached();
    expect(releases, hasLength(2));
    expect(releases[0].version, '1.1.0');
    expect(fetchedAt, isNotNull);
  });

  test('load() falls back to the cache when the live fetch fails', () async {
    final good = serviceReturning(releasesJson);
    await good.fetchFromGitHub();

    final failing = ReleaseNotesService(
      client: MockClient((request) async => http.Response('error', 500)),
      libraryService: LibraryService(rootOverride: tempDir),
    );
    final (releases, fetchedAt, fromCache) = await failing.load();

    expect(fromCache, isTrue);
    expect(releases, hasLength(2));
    expect(fetchedAt, isNotNull);
  });

  test('load() prefers the live fetch over the cache when it succeeds', () async {
    final service = serviceReturning(releasesJson);
    final (releases, _, fromCache) = await service.load();

    expect(fromCache, isFalse);
    expect(releases, hasLength(2));
  });
}
