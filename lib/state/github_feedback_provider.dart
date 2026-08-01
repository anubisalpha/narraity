import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/github_auth_service.dart';
import '../services/github_discussions_service.dart';

/// Public OAuth App client ID, registered under the `anubisalpha` org with
/// Device Flow enabled (no client secret involved — see
/// `GitHubAuthService`'s doc comment). Safe to ship in the app.
const githubFeedbackClientId = 'Ov23liOBvd1Ln9bJKqdO';

final githubAuthServiceProvider = Provider<GitHubAuthService>(
  (ref) => GitHubAuthService(clientId: githubFeedbackClientId),
);

final githubDiscussionsServiceProvider =
    Provider<GitHubDiscussionsService>((ref) => GitHubDiscussionsService());

/// Whether the user is currently signed in to GitHub for Feedback purposes.
/// `.invalidate(githubSignedInProvider)` after a sign-in or sign-out so the
/// Feedback screen re-renders with the right state.
final githubSignedInProvider = FutureProvider<bool>((ref) async {
  return ref.read(githubAuthServiceProvider).isSignedIn;
});
