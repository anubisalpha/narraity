import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/github_token_store.dart';

/// Exercises the [GitHubTokenStore] persistence contract through the public
/// [GitHubTokenStore.forPlatform] factory. Same strategy as
/// `drive_token_store_test.dart`: the host platform picks the real
/// implementation, so this round-trips actual DPAPI on a Windows dev machine
/// and the plain-file store on Linux/macOS CI.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('narraity_github_token_'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<GitHubTokenStore> store() =>
      GitHubTokenStore.forPlatform(rootOverride: root);

  test('load returns null before any token is saved', () async {
    expect(await (await store()).loadAccessToken(), isNull);
  });

  test('save then load round-trips the access token', () async {
    final s = await store();
    await s.saveAccessToken('gho_accessTokenValue');
    expect(await s.loadAccessToken(), 'gho_accessTokenValue');
  });

  test('a fresh store instance reads a token saved by an earlier one', () async {
    await (await store()).saveAccessToken('persisted-gh-token');
    expect(await (await store()).loadAccessToken(), 'persisted-gh-token');
  });

  test('saving again overwrites the previous token', () async {
    final s = await store();
    await s.saveAccessToken('first');
    await s.saveAccessToken('second');
    expect(await s.loadAccessToken(), 'second');
  });

  test('clear removes the token so load returns null again', () async {
    final s = await store();
    await s.saveAccessToken('to-be-cleared');
    await s.clear();
    expect(await s.loadAccessToken(), isNull);
  });

  test('clear is a no-op when nothing was ever saved', () async {
    await (await store()).clear();
    expect(await (await store()).loadAccessToken(), isNull);
  });

  test('the token is not persisted verbatim in the store directory', () async {
    // Byte-compared because DPAPI ciphertext is binary. Asserted only on the
    // encrypted platforms; skipped (not failed) on a plain-file host.
    const token = 'gho_sensitiveAccessTokenValue';
    await (await store()).saveAccessToken(token);

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
