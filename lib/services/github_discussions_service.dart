import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'library_service.dart';

/// Thrown for any GitHub Discussions API failure.
class GitHubDiscussionsException implements Exception {
  GitHubDiscussionsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Posts feedback to the Narraity repo's GitHub Discussions, "App Feedback"
/// category, using the signed-in user's own OAuth token (from
/// `GitHubAuthService`) — the post is attributed to them, not anonymous or
/// from a shared account. Uses GitHub's **GraphQL** API, since Discussions
/// creation isn't available via the REST API.
///
/// The repository ID and "App Feedback" category ID are resolved once via
/// [resolveIds] and cached to `_Settings/github_feedback_category.json` —
/// they aren't expected to change, so there's no need to re-query on every
/// submission.
class GitHubDiscussionsService {
  GitHubDiscussionsService({http.Client? client, LibraryService? libraryService})
      : _client = client ?? http.Client(),
        _library = libraryService ?? LibraryService();

  final http.Client _client;
  final LibraryService _library;

  static const _graphqlUrl = 'https://api.github.com/graphql';
  static const _owner = 'anubisalpha';
  static const _repo = 'narraity';
  static const _categoryName = 'App Feedback';

  Future<File> _cacheFile() async {
    final root = await _library.libraryRoot();
    final dir = Directory(p.join(root.path, '_Settings'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'github_feedback_category.json'));
  }

  Future<Map<String, Object?>> _graphql(
    String accessToken,
    String query,
    Map<String, Object?> variables,
  ) async {
    final response = await _client
        .post(
          Uri.parse(_graphqlUrl),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
            'Accept': 'application/vnd.github+json',
          },
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw GitHubDiscussionsException('GitHub returned HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['errors'] != null) {
      final messages = (json['errors'] as List).map((e) => e['message']).join('; ');
      throw GitHubDiscussionsException(messages);
    }

    return (json['data'] as Map).cast<String, Object?>();
  }

  /// Repository node ID + "App Feedback" category ID, from cache if present,
  /// otherwise resolved via GraphQL and cached for next time. Requires an
  /// authenticated [accessToken] — GitHub's GraphQL API has no unauthenticated
  /// path, even for public-repo reads.
  Future<(String repositoryId, String categoryId)> resolveIds(String accessToken) async {
    final file = await _cacheFile();
    if (await file.exists()) {
      try {
        final cached = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return (cached['repositoryId'] as String, cached['categoryId'] as String);
      } catch (_) {
        // Corrupt cache — fall through and re-resolve.
      }
    }

    const query = r'''
      query($owner: String!, $repo: String!) {
        repository(owner: $owner, name: $repo) {
          id
          discussionCategories(first: 25) {
            nodes { id name }
          }
        }
      }
    ''';

    final data = await _graphql(accessToken, query, {'owner': _owner, 'repo': _repo});
    final repository = data['repository'] as Map<String, dynamic>?;
    if (repository == null) {
      throw GitHubDiscussionsException('Could not find the $_owner/$_repo repository.');
    }

    final repositoryId = repository['id'] as String;
    final categories = (repository['discussionCategories']['nodes'] as List).cast<Map<String, dynamic>>();
    final matches = categories.where((c) => c['name'] == _categoryName);
    if (matches.isEmpty) {
      throw GitHubDiscussionsException(
        'Could not find a "$_categoryName" Discussions category on $_owner/$_repo.',
      );
    }
    final categoryId = matches.first['id'] as String;

    await file.writeAsString(jsonEncode({'repositoryId': repositoryId, 'categoryId': categoryId}));
    return (repositoryId, categoryId);
  }

  /// The signed-in user's own GitHub username — used to show them exactly
  /// who a post will be attributed to before they confirm sending it.
  Future<String> fetchViewerLogin(String accessToken) async {
    const query = r'''
      query { viewer { login } }
    ''';
    final data = await _graphql(accessToken, query, {});
    return (data['viewer'] as Map)['login'] as String;
  }

  /// Posts a new discussion in the "App Feedback" category, attributed to
  /// the owner of [accessToken]. Returns the created discussion's URL.
  Future<String> postFeedback({
    required String accessToken,
    required String title,
    required String body,
  }) async {
    final (repositoryId, categoryId) = await resolveIds(accessToken);

    const mutation = r'''
      mutation($repositoryId: ID!, $categoryId: ID!, $title: String!, $body: String!) {
        createDiscussion(input: {
          repositoryId: $repositoryId,
          categoryId: $categoryId,
          title: $title,
          body: $body
        }) {
          discussion { url }
        }
      }
    ''';

    final data = await _graphql(accessToken, mutation, {
      'repositoryId': repositoryId,
      'categoryId': categoryId,
      'title': title,
      'body': body,
    });

    final discussion = (data['createDiscussion'] as Map)['discussion'] as Map;
    return discussion['url'] as String;
  }
}
