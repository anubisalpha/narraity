import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:narraity/services/github_discussions_service.dart';
import 'package:narraity/services/library_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_gh_discussions_test_');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  GitHubDiscussionsService serviceWith(
    Future<http.Response> Function(http.Request request) handler,
  ) {
    return GitHubDiscussionsService(
      client: MockClient((request) => handler(request)),
      libraryService: LibraryService(rootOverride: tempDir),
    );
  }

  const categoriesResponse = '''
{
  "data": {
    "repository": {
      "id": "R_kgD_repo123",
      "discussionCategories": {
        "nodes": [
          {"id": "DIC_other", "name": "General"},
          {"id": "DIC_feedback", "name": "App Feedback"}
        ]
      }
    }
  }
}
''';

  group('resolveIds', () {
    test('resolves and caches repository + category IDs', () async {
      var callCount = 0;
      final service = serviceWith((request) async {
        callCount++;
        return http.Response(categoriesResponse, 200);
      });

      final (repoId, categoryId) = await service.resolveIds('tok');
      expect(repoId, 'R_kgD_repo123');
      expect(categoryId, 'DIC_feedback');
      expect(callCount, 1);

      // Second call should read the cache, not hit the network again.
      final (repoId2, categoryId2) = await service.resolveIds('tok');
      expect(repoId2, repoId);
      expect(categoryId2, categoryId);
      expect(callCount, 1);
    });

    test('throws when the "App Feedback" category is missing', () async {
      final service = serviceWith((request) async => http.Response('''
{
  "data": {
    "repository": {
      "id": "R_kgD_repo123",
      "discussionCategories": {"nodes": [{"id": "DIC_other", "name": "General"}]}
    }
  }
}
''', 200));

      expect(() => service.resolveIds('tok'), throwsA(isA<GitHubDiscussionsException>()));
    });

    test('throws on a GraphQL error response', () async {
      final service = serviceWith((request) async => http.Response(
            '{"errors":[{"message":"Bad credentials"}]}',
            200,
          ));

      expect(() => service.resolveIds('tok'), throwsA(isA<GitHubDiscussionsException>()));
    });

    test('throws on a non-200 HTTP response', () async {
      final service = serviceWith((request) async => http.Response('error', 401));
      expect(() => service.resolveIds('tok'), throwsA(isA<GitHubDiscussionsException>()));
    });
  });

  group('postFeedback', () {
    test('resolves IDs then creates the discussion, returning its URL', () async {
      final service = serviceWith((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;

        if (query.contains('discussionCategories')) {
          return http.Response(categoriesResponse, 200);
        }

        expect(query, contains('createDiscussion'));
        expect(body['variables']['repositoryId'], 'R_kgD_repo123');
        expect(body['variables']['categoryId'], 'DIC_feedback');
        expect(body['variables']['title'], 'A bug');
        expect(body['variables']['body'], 'It broke.');

        return http.Response('''
{"data": {"createDiscussion": {"discussion": {"url": "https://github.com/anubisalpha/narraity/discussions/42"}}}}
''', 200);
      });

      final url = await service.postFeedback(
        accessToken: 'tok',
        title: 'A bug',
        body: 'It broke.',
      );

      expect(url, 'https://github.com/anubisalpha/narraity/discussions/42');
    });
  });

  group('fetchViewerLogin', () {
    test('returns the signed-in user\'s login', () async {
      final service = serviceWith((request) async => http.Response(
            '{"data": {"viewer": {"login": "octocat"}}}',
            200,
          ));

      expect(await service.fetchViewerLogin('tok'), 'octocat');
    });
  });
}
