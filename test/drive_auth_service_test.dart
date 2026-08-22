import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:narraity/services/drive_auth_service.dart';
import 'package:narraity/services/drive_token_store.dart';

/// In-memory [DriveTokenStore] so the desktop auth service's session-state
/// logic can be exercised without touching real DPAPI/Keystore storage or the
/// network. The interactive consent flow and the `refreshCredentials` network
/// call in `ensureSignedIn` are deliberately out of scope here — they need a
/// live browser and Google's servers — so these tests cover exactly the part
/// that is decidable locally: whether a saved refresh token means "signed in",
/// and that sign-out clears it.
class _FakeDriveTokenStore implements DriveTokenStore {
  String? token;

  @override
  Future<void> saveRefreshToken(String refreshToken) async => token = refreshToken;

  @override
  Future<String?> loadRefreshToken() async => token;

  @override
  Future<void> clear() async => token = null;
}

void main() {
  // The factory branches on platform; the desktop implementation under test is
  // only selected off-Android. Skip on Android hosts (this suite runs on the
  // Windows/Linux dev+CI machine).
  final onAndroid = Platform.isAndroid;

  final clientId = ClientId('test-client-id', 'test-client-secret');

  test('isSignedIn is false when no refresh token is stored', () async {
    final store = _FakeDriveTokenStore();
    final service = DriveAuthService(clientId: clientId, tokenStore: store);
    expect(await service.isSignedIn, isFalse);
  }, skip: onAndroid);

  test('isSignedIn is true when a refresh token is already stored', () async {
    final store = _FakeDriveTokenStore()..token = 'saved-refresh-token';
    final service = DriveAuthService(clientId: clientId, tokenStore: store);
    expect(await service.isSignedIn, isTrue);
  }, skip: onAndroid);

  test('signOut clears the stored token and flips isSignedIn to false', () async {
    final store = _FakeDriveTokenStore()..token = 'saved-refresh-token';
    final service = DriveAuthService(clientId: clientId, tokenStore: store);

    expect(await service.isSignedIn, isTrue);
    await service.signOut();

    expect(store.token, isNull);
    expect(await service.isSignedIn, isFalse);
  }, skip: onAndroid);
}
