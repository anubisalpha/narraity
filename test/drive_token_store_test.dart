import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/drive_token_store.dart';

/// Exercises the [DriveTokenStore] persistence contract through the public
/// [DriveTokenStore.forPlatform] factory, which selects the real per-platform
/// implementation for the host the suite runs on: DPAPI on Windows (so this
/// round-trips actual `CryptProtectData`/`CryptUnprotectData` and its native
/// memory handling on a Windows dev machine), and the plain-file store on
/// Linux/macOS CI. Either way the observable contract — save, load, clear,
/// overwrite, and the on-disk file being distinct from the raw token on the
/// encrypted platforms — is what these assert.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('narraity_drive_token_'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<DriveTokenStore> store() =>
      DriveTokenStore.forPlatform(rootOverride: root);

  test('load returns null before any token is saved', () async {
    expect(await (await store()).loadRefreshToken(), isNull);
  });

  test('save then load round-trips the refresh token', () async {
    final s = await store();
    await s.saveRefreshToken('refresh-token-abc123');
    expect(await s.loadRefreshToken(), 'refresh-token-abc123');
  });

  test('a fresh store instance reads a token saved by an earlier one', () async {
    // Tokens must survive an app restart, i.e. a brand-new store over the same
    // directory, not just the in-memory instance that wrote them.
    await (await store()).saveRefreshToken('persisted-token');
    expect(await (await store()).loadRefreshToken(), 'persisted-token');
  });

  test('saving again overwrites the previous token', () async {
    final s = await store();
    await s.saveRefreshToken('first');
    await s.saveRefreshToken('second');
    expect(await s.loadRefreshToken(), 'second');
  });

  test('clear removes the token so load returns null again', () async {
    final s = await store();
    await s.saveRefreshToken('to-be-cleared');
    await s.clear();
    expect(await s.loadRefreshToken(), isNull);
  });

  test('clear is a no-op when nothing was ever saved', () async {
    // Sign-out must not throw just because the user was never signed in.
    await (await store()).clear();
    expect(await (await store()).loadRefreshToken(), isNull);
  });

  test('the token is not persisted verbatim in the store directory', () async {
    // On the encrypted platforms (DPAPI/Keystore) the on-disk bytes must be
    // ciphertext, never the raw token. On a plain-file host this assertion is
    // skipped rather than asserted false, so the same test is honest on both.
    // Compared as raw bytes because DPAPI ciphertext is binary and would throw
    // if decoded as UTF-8.
    const token = 'sensitive-refresh-token-value';
    await (await store()).saveRefreshToken(token);

    final files = root.listSync(recursive: true).whereType<File>().toList();
    expect(files, isNotEmpty, reason: 'a token file should exist on disk');

    if (Platform.isWindows || Platform.isAndroid) {
      final tokenBytes = token.codeUnits;
      for (final f in files) {
        expect(
          _containsSubsequence(f.readAsBytesSync(), tokenBytes),
          isFalse,
          reason: 'token must be encrypted at rest on this platform',
        );
      }
    }
  });
}

/// True if [needle] appears as a contiguous subsequence of [haystack].
bool _containsSubsequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}
