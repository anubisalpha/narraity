import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Encrypts/decrypts small secrets with a non-exportable, hardware-backed key.
/// The Android implementation ([AndroidSecretCipher]) bridges to
/// `SecretCipher.kt`, which holds an AES-256-GCM key in the AndroidKeyStore;
/// the key itself never leaves native code. Kept behind an interface so tests
/// can substitute a fake without a live platform channel.
abstract class SecretCipher {
  Future<Uint8List> encrypt(List<int> plaintext);
  Future<Uint8List> decrypt(List<int> ciphertext);
}

/// [SecretCipher] backed by the Android Keystore via a method channel. The
/// returned ciphertext is `iv (12 bytes) || GCM ciphertext+tag`, assembled on
/// the native side; this class treats it as opaque bytes.
class AndroidSecretCipher implements SecretCipher {
  const AndroidSecretCipher();

  static const _channel = MethodChannel('uk.aity.narraity/secret_cipher');

  @override
  Future<Uint8List> encrypt(List<int> plaintext) async {
    final out = await _channel.invokeMethod<Uint8List>(
      'encrypt',
      Uint8List.fromList(plaintext),
    );
    if (out == null) throw StateError('Keystore encrypt returned null');
    return out;
  }

  @override
  Future<Uint8List> decrypt(List<int> ciphertext) async {
    final out = await _channel.invokeMethod<Uint8List>(
      'decrypt',
      Uint8List.fromList(ciphertext),
    );
    if (out == null) throw StateError('Keystore decrypt returned null');
    return out;
  }
}

/// One secret persisted to app-private storage, encrypted at rest via a
/// [SecretCipher] when the device's Keystore is available and falling back to
/// a plain file (the pre-Keystore behaviour) when it isn't — so this is
/// strictly an improvement over plaintext, never a regression that could lock
/// a user out of sign-in on an edge-case device. Reused by both OAuth token
/// stores (Drive, GitHub).
///
/// On disk: `<fileName>.ks` holds the encrypted form, `<fileName>` the legacy
/// plaintext. A legacy plaintext secret is transparently upgraded to encrypted
/// the next time it's read.
class KeystoreFileSecret {
  KeystoreFileSecret({
    required Directory root,
    required String fileName,
    SecretCipher cipher = const AndroidSecretCipher(),
  })  : _root = root,
        _plainFile = File(p.join(root.path, fileName)),
        _encFile = File(p.join(root.path, '$fileName.ks')),
        _cipher = cipher;

  final Directory _root;
  final File _plainFile;
  final File _encFile;
  final SecretCipher _cipher;

  Future<void> write(String value) async {
    await _root.create(recursive: true);
    try {
      final encrypted = await _cipher.encrypt(utf8.encode(value));
      await _encFile.writeAsBytes(encrypted);
      if (await _plainFile.exists()) await _plainFile.delete();
    } catch (_) {
      // Keystore unavailable (ancient device, OEM bug) — preserve the original
      // plain-file behaviour so sign-in still works rather than failing hard.
      await _plainFile.writeAsString(value);
      if (await _encFile.exists()) await _encFile.delete();
    }
  }

  Future<String?> read() async {
    if (await _encFile.exists()) {
      try {
        return utf8.decode(await _cipher.decrypt(await _encFile.readAsBytes()));
      } catch (_) {
        // Undecryptable (e.g. the Keystore key was wiped by a credential
        // reset) — fall through. Worst case is null, i.e. treated as signed
        // out, which is non-destructive: the user re-authenticates.
      }
    }
    if (await _plainFile.exists()) {
      final value = await _plainFile.readAsString();
      // Opportunistically upgrade a legacy plaintext secret to encrypted.
      await write(value);
      return value;
    }
    return null;
  }

  Future<void> clear() async {
    if (await _encFile.exists()) await _encFile.delete();
    if (await _plainFile.exists()) await _plainFile.delete();
  }
}
