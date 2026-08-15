import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/android_secret_cipher.dart';
import 'package:path/path.dart' as p;

/// A reversible stand-in for the real Keystore cipher: prefixes a marker byte
/// so a test can tell encrypted bytes from plaintext, and reverses it exactly.
/// No real crypto — this exercises [KeystoreFileSecret]'s file/fallback/
/// migration logic, which is all that's testable off-device.
class _FakeCipher implements SecretCipher {
  @override
  Future<Uint8List> encrypt(List<int> plaintext) async =>
      Uint8List.fromList([0xAA, ...plaintext]);

  @override
  Future<Uint8List> decrypt(List<int> ciphertext) async {
    if (ciphertext.isEmpty || ciphertext.first != 0xAA) {
      throw const FormatException('not fake-encrypted');
    }
    return Uint8List.fromList(ciphertext.sublist(1));
  }
}

/// A cipher that always fails, standing in for a device with no working
/// Keystore, to exercise the plain-file fallback.
class _BrokenCipher implements SecretCipher {
  @override
  Future<Uint8List> encrypt(List<int> plaintext) async =>
      throw StateError('no keystore');

  @override
  Future<Uint8List> decrypt(List<int> ciphertext) async =>
      throw StateError('no keystore');
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('narraity_secret_test_'));
  tearDown(() => root.deleteSync(recursive: true));

  File encFile(String name) => File(p.join(root.path, '$name.ks'));
  File plainFile(String name) => File(p.join(root.path, name));

  test('write encrypts to the .ks file and round-trips on read', () async {
    final secret = KeystoreFileSecret(root: root, fileName: 'token', cipher: _FakeCipher());

    await secret.write('s3cret-value');

    expect(await encFile('token').exists(), isTrue);
    expect(await plainFile('token').exists(), isFalse);
    // Stored bytes are the fake-encrypted form, not the plaintext.
    expect(await encFile('token').readAsBytes(), isNot(utf8.encode('s3cret-value')));
    expect(await secret.read(), 's3cret-value');
  });

  test('falls back to a plain file when the cipher is unavailable', () async {
    final secret = KeystoreFileSecret(root: root, fileName: 'token', cipher: _BrokenCipher());

    await secret.write('fallback-value');

    expect(await plainFile('token').exists(), isTrue);
    expect(await encFile('token').exists(), isFalse);
    expect(await plainFile('token').readAsString(), 'fallback-value');
    expect(await secret.read(), 'fallback-value');
  });

  test('reading a legacy plaintext token migrates it to encrypted', () async {
    // Simulate a token written before Keystore encryption existed.
    await plainFile('token').writeAsString('legacy-token');
    final secret = KeystoreFileSecret(root: root, fileName: 'token', cipher: _FakeCipher());

    final value = await secret.read();

    expect(value, 'legacy-token');
    // Upgraded in place: encrypted file now present, plaintext removed.
    expect(await encFile('token').exists(), isTrue);
    expect(await plainFile('token').exists(), isFalse);
  });

  test('clear removes both the encrypted and any legacy plain file', () async {
    await plainFile('token').writeAsString('legacy');
    final secret = KeystoreFileSecret(root: root, fileName: 'token', cipher: _FakeCipher());
    await secret.write('current');
    // Recreate a stray legacy file to prove clear takes both.
    await plainFile('token').writeAsString('stray');

    await secret.clear();

    expect(await encFile('token').exists(), isFalse);
    expect(await plainFile('token').exists(), isFalse);
    expect(await secret.read(), isNull);
  });
}
