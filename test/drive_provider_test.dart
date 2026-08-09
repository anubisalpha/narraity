import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:narraity/services/drive_auth_service.dart';
import 'package:narraity/state/drive_provider.dart';

/// Never resolves `ensureSignedIn` until [failWith] is called — lets tests
/// exercise the "sign-in is stuck, user cancels" case without a real
/// browser/network round trip. `implements` rather than `extends`:
/// `DriveAuthService` is now an abstract interface with platform-specific
/// implementations behind a factory constructor, not a class this fake can
/// subclass directly.
class _HangingDriveAuthService implements DriveAuthService {
  final _completer = Completer<http.Client>();

  @override
  Future<bool> get isSignedIn async => false;

  @override
  Future<http.Client> ensureSignedIn({
    Future<void> Function(String url)? onSignInUrl,
  }) =>
      _completer.future;

  @override
  Future<void> signOut() async {}

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
