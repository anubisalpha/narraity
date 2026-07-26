import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:narraity/services/drive_auth_service.dart';
import 'package:narraity/services/drive_token_store.dart';
import 'package:narraity/state/drive_provider.dart';

/// In-memory only — avoids the real `DriveTokenStore.forPlatform()`'s
/// `path_provider` platform channel call, which has no mock registered in
/// this plain (non-widget) test and would otherwise throw asynchronously
/// after the test that triggered it has already finished.
class _InMemoryTokenStore implements DriveTokenStore {
  String? _token;
  @override
  Future<void> saveRefreshToken(String refreshToken) async => _token = refreshToken;
  @override
  Future<String?> loadRefreshToken() async => _token;
  @override
  Future<void> clear() async => _token = null;
}

/// Never resolves `ensureSignedIn` until [failWith] is called — lets tests
/// exercise the "sign-in is stuck, user cancels" case without a real
/// browser/network round trip.
class _HangingDriveAuthService extends DriveAuthService {
  _HangingDriveAuthService()
      : super(
          clientId: ClientId('test-client', 'test-secret'),
          tokenStore: _InMemoryTokenStore(),
        );

  final _completer = Completer<AutoRefreshingAuthClient>();

  @override
  Future<bool> get isSignedIn async => false;

  @override
  Future<AutoRefreshingAuthClient> ensureSignedIn({
    Future<void> Function(String url)? onSignInUrl,
  }) =>
      _completer.future;

  void failWith(Object error) => _completer.completeError(error);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cancelConnect resolves a stuck connect() and resets state, with no error message', () async {
    final hangingAuth = _HangingDriveAuthService();
    final container = ProviderContainer(
      overrides: [driveAuthServiceProvider.overrideWithValue(hangingAuth)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(driveConnectionProvider.notifier);
    // Let the initial _restore() (isSignedIn check) settle first.
    await Future<void>.delayed(Duration.zero);

    final connectFuture = notifier.connect();
    expect(container.read(driveConnectionProvider), DriveConnectionStatus.signingIn);

    notifier.cancelConnect();
    final error = await connectFuture;

    expect(error, isNull); // a deliberate cancel isn't reported as an error
    expect(container.read(driveConnectionProvider), DriveConnectionStatus.signedOut);
  });

  test('a real failure (not a cancel) still surfaces an error message', () async {
    final hangingAuth = _HangingDriveAuthService();
    final container = ProviderContainer(
      overrides: [driveAuthServiceProvider.overrideWithValue(hangingAuth)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(driveConnectionProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final connectFuture = notifier.connect();
    hangingAuth.failWith(StateError('consent denied'));
    final error = await connectFuture;

    expect(error, contains('consent denied'));
    expect(container.read(driveConnectionProvider), DriveConnectionStatus.signedOut);
  });
}
