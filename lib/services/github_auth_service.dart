import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_token_store.dart';

/// Thrown for any Device Flow failure that isn't "still waiting for the
/// user" — expired code, denied, or a network/HTTP problem.
class GitHubAuthException implements Exception {
  GitHubAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The code/URL to show the user, returned by [GitHubAuthService.requestDeviceCode].
class DeviceCodeRequest {
  const DeviceCodeRequest({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
}

/// GitHub sign-in via OAuth **Device Flow** — the standard flow for apps
/// that can't embed a client secret (desktop/CLI apps; the app's `clientId`
/// is a public value safe to ship). Used only by the Feedback feature to
/// post to GitHub Discussions attributed to the user's real account — see
/// PLAN.md's "Feedback" section. Distinct OAuth provider from Google Drive
/// sync, so this is deliberately its own service/token store rather than
/// generalizing `DriveAuthService` — the two flows (browser+loopback vs.
/// device-code polling) don't share meaningful code.
///
/// Flow: [requestDeviceCode] gets a user code + verification URL to show the
/// user, then [pollForToken] polls GitHub until they've approved it in their
/// browser (or the code expires / they deny it).
class GitHubAuthService {
  GitHubAuthService({
    required this.clientId,
    http.Client? client,
    GitHubTokenStore? tokenStore,
  })  : _client = client ?? http.Client(),
        _tokenStoreFuture = tokenStore != null
            ? Future.value(tokenStore)
            : GitHubTokenStore.forPlatform();

  /// Public OAuth App client ID — safe to ship; Device Flow uses no client
  /// secret.
  final String clientId;
  final http.Client _client;
  final Future<GitHubTokenStore> _tokenStoreFuture;

  // `public_repo` is required by GitHub's `createDiscussion` GraphQL mutation
  // itself (confirmed live, 2026-08-02 — a signed-in token with only the
  // discussion scopes below was rejected with "createDiscussion requires
  // one of the following scopes: ['public_repo']"), not obviously implied by
  // needing to post a Discussion. Scoped to `public_repo` rather than full
  // `repo` since the target repo is public.
  static const _scope = 'public_repo read:discussion write:discussion';

  Future<bool> get isSignedIn async {
    final store = await _tokenStoreFuture;
    return await store.loadAccessToken() != null;
  }

  Future<String?> currentToken() async {
    final store = await _tokenStoreFuture;
    return store.loadAccessToken();
  }

  Future<void> signOut() async {
    final store = await _tokenStoreFuture;
    await store.clear();
  }

  Future<DeviceCodeRequest> requestDeviceCode() async {
    final response = await _client.post(
      Uri.parse('https://github.com/login/device/code'),
      headers: {'Accept': 'application/json'},
      body: {'client_id': clientId, 'scope': _scope},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw GitHubAuthException('GitHub returned HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw GitHubAuthException(json['error_description'] as String? ?? json['error'] as String);
    }

    return DeviceCodeRequest(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUri: json['verification_uri'] as String,
      expiresIn: json['expires_in'] as int,
      interval: json['interval'] as int,
    );
  }

  /// Polls GitHub for the user to approve [request] in their browser,
  /// respecting the server's requested interval (and any `slow_down` bump).
  /// Checks [isCancelled] between polls so the caller can offer a "Cancel"
  /// button — returns via [GitHubAuthException] rather than a bare Future
  /// timeout, since "the user gave up" is a normal outcome here, not a bug.
  /// On success, the token is saved to the platform token store before
  /// returning it.
  ///
  /// Only `expired_token` (the code's real 15-minute lifetime is up) and
  /// `access_denied` (the user explicitly declined) are treated as
  /// immediately fatal — those are genuine terminal states per GitHub's own
  /// device flow spec. Any other error (including `incorrect_client_
  /// credentials`, which live testing showed GitHub can return as a
  /// transient response under its own throttling, not just for a genuinely
  /// wrong client_id) is tolerated for a few consecutive polls before giving
  /// up — a single unexplained hiccup a few seconds after the code first
  /// appears shouldn't kill a flow that still has most of its 15 minutes
  /// left to run.
  Future<String> pollForToken(
    DeviceCodeRequest request, {
    bool Function()? isCancelled,
  }) async {
    const maxConsecutiveUnexpectedErrors = 5;

    var interval = request.interval;
    var consecutiveUnexpectedErrors = 0;
    final deadline = DateTime.now().add(Duration(seconds: request.expiresIn));

    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) {
        throw GitHubAuthException('Sign-in cancelled.');
      }

      await Future.delayed(Duration(seconds: interval));

      final response = await _client.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: {'Accept': 'application/json'},
        body: {
          'client_id': clientId,
          'device_code': request.deviceCode,
          // Exact value per GitHub's own docs (watched by
          // tool/github_docs_watch/check_github_docs_pages.ps1 — a stale
          // reading of this exact string caused a real 100%-reproducible
          // sign-in failure, see BUILD_LOG.md):
          // https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      ).timeout(const Duration(seconds: 10));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final error = json['error'] as String?;

      if (error == null) {
        final token = json['access_token'] as String;
        final store = await _tokenStoreFuture;
        await store.saveAccessToken(token);
        return token;
      }

      switch (error) {
        case 'authorization_pending':
          consecutiveUnexpectedErrors = 0;
          continue;
        case 'slow_down':
          consecutiveUnexpectedErrors = 0;
          interval = (json['interval'] as int?) ?? (interval + 5);
          continue;
        case 'expired_token':
          throw GitHubAuthException('The sign-in code expired before it was approved. Try again.');
        case 'access_denied':
          throw GitHubAuthException('Sign-in was denied.');
        default:
          consecutiveUnexpectedErrors++;
          if (consecutiveUnexpectedErrors >= maxConsecutiveUnexpectedErrors) {
            throw GitHubAuthException(json['error_description'] as String? ?? error);
          }
          continue;
      }
    }

    throw GitHubAuthException('The sign-in code expired before it was approved. Try again.');
  }
}
