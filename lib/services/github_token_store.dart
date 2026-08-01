import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

/// Persists the GitHub OAuth access token used by the Feedback feature
/// (Device Flow sign-in, `read:discussion`/`write:discussion` scopes),
/// device-locally — same storage strategy as `DriveTokenStore`, just a
/// separate file/subdirectory since this is a second, independent OAuth
/// provider. See `DriveTokenStore`'s doc comment for why
/// `flutter_secure_storage` is avoided and DPAPI/sandboxed-storage is used
/// instead — identical reasoning applies here.
abstract class GitHubTokenStore {
  Future<void> saveAccessToken(String accessToken);
  Future<String?> loadAccessToken();
  Future<void> clear();

  /// Picks the right implementation for the current platform. Pass
  /// [rootOverride] to point storage at a specific directory (used by tests)
  /// instead of resolving the platform support folder.
  static Future<GitHubTokenStore> forPlatform({Directory? rootOverride}) async {
    final root = rootOverride ?? await _defaultRoot();
    return Platform.isWindows ? _WindowsDpapiTokenStore(root) : _PlainFileTokenStore(root);
  }

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'github_auth'));
  }
}

class _PlainFileTokenStore implements GitHubTokenStore {
  _PlainFileTokenStore(this._root);
  final Directory _root;

  File get _file => File(p.join(_root.path, 'access_token'));

  @override
  Future<void> saveAccessToken(String accessToken) async {
    await _root.create(recursive: true);
    await _file.writeAsString(accessToken);
  }

  @override
  Future<String?> loadAccessToken() async {
    if (!await _file.exists()) return null;
    return _file.readAsString();
  }

  @override
  Future<void> clear() async {
    if (await _file.exists()) await _file.delete();
  }
}

class _WindowsDpapiTokenStore implements GitHubTokenStore {
  _WindowsDpapiTokenStore(this._root);
  final Directory _root;

  File get _file => File(p.join(_root.path, 'access_token.dpapi'));

  @override
  Future<void> saveAccessToken(String accessToken) async {
    await _root.create(recursive: true);
    final encrypted = _protect(utf8.encode(accessToken));
    await _file.writeAsBytes(encrypted);
  }

  @override
  Future<String?> loadAccessToken() async {
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
