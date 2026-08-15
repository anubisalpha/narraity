import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

import 'android_secret_cipher.dart';

/// Persists the Google Drive OAuth refresh token to disk, device-locally —
/// never synced (lives under the app support directory, not the
/// `Documents/Narraity/` library root Drive sync itself walks) and never
/// shared across devices, since each device signs in independently.
///
/// `flutter_secure_storage` was deliberately avoided here, same call already
/// made for the vault signing key (see `HistorySigningKeyManager`'s doc
/// comment): its Windows backend needs a Visual Studio ATL component not
/// installed on this machine, and — unlike that package — adding it as a
/// dependency at all would pull the Windows platform implementation into
/// every `flutter build windows`, breaking the build regardless of whether
/// Dart code on this platform ever calls it.
///
/// Windows: encrypted at rest via DPAPI (`CryptProtectData`/
/// `CryptUnprotectData`, tied to the current Windows user account) — pure
/// Win32 FFI calls against `crypt32.dll`, which ships with Windows, so this
/// needs no native library build at all.
///
/// Android: encrypted at rest via a hardware-backed AndroidKeyStore key
/// (AES-256-GCM through [KeystoreFileSecret]/`SecretCipher.kt`), stored under
/// the app's private, sandboxed storage. If the Keystore is somehow
/// unavailable it falls back to a plain file — the pre-Keystore behaviour —
/// so this is strictly an improvement, never a regression that could break
/// sign-in. A legacy plaintext token from before this change is upgraded to
/// encrypted the next time it's read.
abstract class DriveTokenStore {
  Future<void> saveRefreshToken(String refreshToken);
  Future<String?> loadRefreshToken();
  Future<void> clear();

  /// Picks the right implementation for the current platform. Pass
  /// [rootOverride] to point storage at a specific directory (used by tests)
  /// instead of resolving the platform support folder.
  static Future<DriveTokenStore> forPlatform({Directory? rootOverride}) async {
    final root = rootOverride ?? await _defaultRoot();
    if (Platform.isWindows) return _WindowsDpapiTokenStore(root);
    if (Platform.isAndroid) return _AndroidKeystoreTokenStore(root);
    return _PlainFileTokenStore(root);
  }

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'drive_sync'));
  }
}

class _PlainFileTokenStore implements DriveTokenStore {
  _PlainFileTokenStore(this._root);
  final Directory _root;

  File get _file => File(p.join(_root.path, 'refresh_token'));

  @override
  Future<void> saveRefreshToken(String refreshToken) async {
    await _root.create(recursive: true);
    await _file.writeAsString(refreshToken);
  }

  @override
  Future<String?> loadRefreshToken() async {
    if (!await _file.exists()) return null;
    return _file.readAsString();
  }

  @override
  Future<void> clear() async {
    if (await _file.exists()) await _file.delete();
  }
}

class _AndroidKeystoreTokenStore implements DriveTokenStore {
  _AndroidKeystoreTokenStore(Directory root)
      : _secret = KeystoreFileSecret(root: root, fileName: 'refresh_token');

  final KeystoreFileSecret _secret;

  @override
  Future<void> saveRefreshToken(String refreshToken) => _secret.write(refreshToken);

  @override
  Future<String?> loadRefreshToken() => _secret.read();

  @override
  Future<void> clear() => _secret.clear();
}

class _WindowsDpapiTokenStore implements DriveTokenStore {
  _WindowsDpapiTokenStore(this._root);
  final Directory _root;

  File get _file => File(p.join(_root.path, 'refresh_token.dpapi'));

  @override
  Future<void> saveRefreshToken(String refreshToken) async {
    await _root.create(recursive: true);
    final encrypted = _protect(utf8.encode(refreshToken));
    await _file.writeAsBytes(encrypted);
  }

  @override
  Future<String?> loadRefreshToken() async {
    if (!await _file.exists()) return null;
    final encrypted = await _file.readAsBytes();
    return utf8.decode(_unprotect(Uint8List.fromList(encrypted)));
  }

  @override
  Future<void> clear() async {
    if (await _file.exists()) await _file.delete();
  }

  Uint8List _protect(List<int> plaintext) => _withBlob(plaintext, (inBlob, outBlob) {
        final ok = CryptProtectData(inBlob, nullptr, nullptr, nullptr, nullptr, 0, outBlob);
        if (ok == 0) {
          throw StateError('CryptProtectData failed (GetLastError=${GetLastError()})');
        }
      });

  Uint8List _unprotect(List<int> ciphertext) => _withBlob(ciphertext, (inBlob, outBlob) {
        final ok = CryptUnprotectData(inBlob, nullptr, nullptr, nullptr, nullptr, 0, outBlob);
        if (ok == 0) {
          throw StateError('CryptUnprotectData failed (GetLastError=${GetLastError()})');
        }
      });

  /// Shared DATA_BLOB plumbing for both directions: allocates an input blob
  /// from [input], lets [call] fill in an output blob, copies the output
  /// bytes into a managed [Uint8List], and frees every native allocation
  /// (including the output blob's buffer, which DPAPI allocates and expects
  /// the caller to release via `LocalFree`) before returning.
  Uint8List _withBlob(
    List<int> input,
    void Function(Pointer<CRYPT_INTEGER_BLOB> inBlob, Pointer<CRYPT_INTEGER_BLOB> outBlob) call,
  ) {
    final inBlob = calloc<CRYPT_INTEGER_BLOB>();
    final inBuf = calloc<Uint8>(input.length);
    inBuf.asTypedList(input.length).setAll(0, input);
    inBlob.ref.cbData = input.length;
    inBlob.ref.pbData = inBuf;

    final outBlob = calloc<CRYPT_INTEGER_BLOB>();
    try {
      call(inBlob, outBlob);
      return Uint8List.fromList(outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
    } finally {
      calloc.free(inBuf);
      calloc.free(inBlob);
      if (outBlob.ref.pbData != nullptr) LocalFree(outBlob.ref.pbData.cast());
      calloc.free(outBlob);
    }
  }
}
