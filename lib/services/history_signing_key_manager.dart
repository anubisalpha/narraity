import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Derives and holds, in memory only, the key used to sign scene-history
/// snapshots (see SceneHistoryService) — a password-derived key rather than
/// one held in OS-specific secure storage.
///
/// This replaces an earlier design that used `flutter_secure_storage`
/// (Windows Credential Locker / Android Keystore). That approach had two
/// real problems: it required a native Windows component (ATL) that isn't
/// installed on every dev machine, and — more fundamentally — a key that
/// lives in *device-local* secure storage is different on every device by
/// definition, so a snapshot signed on a Windows PC could never verify on
/// an Android phone once Drive sync brought the file across, even though
/// nothing was actually wrong with it.
///
/// A password-derived key fixes both: it's pure Dart (no platform channel,
/// no native build step, works identically on every OS), and it's the
/// *same* key everywhere the same password is entered, so genuine
/// cross-device verification becomes possible rather than "trust snapshots
/// from other devices on sight."
///
/// The salt is not secret — it only needs to stay stable so the same
/// password always derives the same key — so it's stored as a plain,
/// unencrypted file. There's nothing to protect there; the security comes
/// entirely from the password plus Argon2id's cost, same as the Vault.
///
/// If no password has ever been set (the user hasn't opted into the vault
/// tier), [currentKey] is null and history snapshots are written/read as
/// legacy-unsigned — trusted but unverifiable, exactly like snapshots
/// written before this feature existed at all.
class HistorySigningKeyManager {
  HistorySigningKeyManager(this._saltFile);

  final File _saltFile;

  static const _argonMemoryKib = 19456;
  static const _argonIterations = 3;
  static const _argonParallelism = 1;

  List<int>? _key;

  /// Whether a password has been supplied this session — i.e. whether new
  /// snapshots will be signed and existing signed ones can be verified.
  bool get isUnlocked => _key != null;

  /// The current signing key, or null if [unlock] hasn't been called this
  /// session. Never persisted anywhere; the caller must re-supply the
  /// password each time the app starts (or the app can choose to keep this
  /// manager alive for the process lifetime once unlocked).
  List<int>? get currentKey => _key;

  /// Derives the signing key from [password] and this library's persisted
  /// (non-secret) salt, creating the salt file on first use.
  Future<void> unlock(String password) async {
    final salt = await _getOrCreateSalt();
    final argon2id = Argon2id(
      memory: _argonMemoryKib,
      iterations: _argonIterations,
      parallelism: _argonParallelism,
      hashLength: 32,
    );
    final secretKey = await argon2id.deriveKeyFromPassword(password: password, nonce: salt);
    _key = await secretKey.extractBytes();
  }

  /// Discards the in-memory key — e.g. on app lock or sign-out. Existing
  /// signed history is unaffected; it just can't be verified again until
  /// [unlock] is called with the correct password.
  void lock() => _key = null;

  Future<List<int>> _getOrCreateSalt() async {
    if (await _saltFile.exists()) {
      return base64Decode(await _saltFile.readAsString());
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    await _saltFile.parent.create(recursive: true);
    await _saltFile.writeAsString(base64Encode(salt));
    return salt;
  }
}
