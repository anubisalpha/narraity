import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/services/news_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_news_test_');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  NewsService serviceReturning(String body, {int statusCode = 200}) {
    return NewsService(
      client: MockClient((request) async => http.Response(body, statusCode)),
      libraryService: LibraryService(rootOverride: tempDir),
    );
  }

  const newsMarkdown = '''
# Narraity News

Some intro text before the first heading -- should not become an entry.

## 2026-08-01: Second entry

Body of the second (newest) entry.

Spans multiple paragraphs.

## 2026-07-15: First entry

Body of the first entry.
''';

  test('parse extracts entries in source order, ignoring the pre-heading intro', () {
    final service = NewsService();
    final entries = service.parse(newsMarkdown);

    expect(entries, hasLength(2));
    expect(entries[0].title, 'Second entry');
    expect(entries[0].date, DateTime(2026, 8, 1));
    expect(entries[0].body, contains('Spans multiple paragraphs.'));
    expect(entries[1].title, 'First entry');
    expect(entries[1].date, DateTime(2026, 7, 15));
  });

  test('parse returns an empty list for content with no matching headings', () {
    final service = NewsService();
    expect(service.parse('Just plain text, no headings.'), isEmpty);
  });

  test('fetchFromGitHub parses the fetched body and populates the cache', () async {
    final service = serviceReturning(newsMarkdown);
    final entries = await service.fetchFromGitHub();

    expect(entries, hasLength(2));

    final (cached, fetchedAt) = await service.loadCached();
    expect(cached, hasLength(2));
    expect(fetchedAt, isNotNull);
  });

  test('fetchFromGitHub throws on a non-200 response', () async {
    final service = serviceReturning('not found', statusCode: 404);
    expect(() => service.fetchFromGitHub(), throwsException);
  });

  test('load() falls back to the cache when the live fetch fails', () async {
    final good = serviceReturning(newsMarkdown);
    await good.fetchFromGitHub();

    final failing = NewsService(
      client: MockClient((request) async => http.Response('error', 500)),
      libraryService: LibraryService(rootOverride: tempDir),
    );
    final (entries, fetchedAt, fromCache) = await failing.load();

    expect(fromCache, isTrue);
    expect(entries, hasLength(2));
    expect(fetchedAt, isNotNull);
  });
}
