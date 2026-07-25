import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
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
///
/// A second non-secret file, the *verifier*, holds an HMAC of a fixed string
/// under the derived key. It exists so a wrong password can be rejected up
/// front: without it, any password would "unlock" successfully and then
/// silently sign new snapshots with a key that can't verify the existing
/// chain, which reads downstream as tampering.
class HistorySigningKeyManager {
  HistorySigningKeyManager({required File saltFile, required File verifierFile})
      : _saltFile = saltFile,
        _verifierFile = verifierFile;

  final File _saltFile;
  final File _verifierFile;

  static const _argonMemoryKib = 19456;
  static const _argonIterations = 3;
  static const _argonParallelism = 1;

  /// Signed to produce the verifier. Fixed and non-secret — its only job is
  /// to be the same input every time so the resulting HMAC depends purely on
  /// the key.
  static const _verifierPayload = 'narraity-vault-verifier';

  List<int>? _key;

  /// Whether a password has been supplied this session — i.e. whether new
  /// snapshots will be signed and existing signed ones can be verified.
  bool get isUnlocked => _key != null;

  /// Whether a vault password has ever been set for this library. False means
  /// the user hasn't opted into the vault tier at all.
  Future<bool> get isConfigured => _verifierFile.exists();

  /// The current signing key, or null if [unlock] hasn't been called this
  /// session. Never persisted anywhere; the caller must re-supply the
  /// password each time the app starts (or the app can choose to keep this
  /// manager alive for the process lifetime once unlocked).
  List<int>? get currentKey => _key;

  /// Sets the vault password for the first time: creates the salt, derives
  /// the key, writes the verifier, and leaves the manager unlocked.
  Future<void> setup(String password) async {
    final key = await deriveKeyFor(password);
    await _writeVerifier(key);
    _key = key;
  }

  /// Derives the key for [password] and unlocks only if it matches the
  /// stored verifier. Returns false on a wrong password, leaving any
  /// previously unlocked key untouched.
  ///
  /// If no verifier exists yet this is treated as a wrong password rather
  /// than an implicit setup — silently adopting whatever was typed as *the*
  /// password would be a bad surprise for a user who mistyped at a prompt.
  Future<bool> unlock(String password) async {
    if (!await _verifierFile.exists()) return false;
    final expected = (await _verifierFile.readAsString()).trim();
    final key = await deriveKeyFor(password);
    if (_verifierFor(key) != expected) return false;
    _key = key;
    return true;
  }

  /// Derives a key from [password] without changing this manager's state —
  /// needed by the change-password flow, which has to hold the old and new
  /// keys at once to re-sign existing history.
  Future<List<int>> deriveKeyFor(String password) async {
    final salt = await _getOrCreateSalt();
    final argon2id = Argon2id(
      memory: _argonMemoryKib,
      iterations: _argonIterations,
      parallelism: _argonParallelism,
      hashLength: 32,
    );
    final secretKey = await argon2id.deriveKeyFromPassword(password: password, nonce: salt);
    return secretKey.extractBytes();
  }

  /// Switches the library to [newPassword] — rewrites the verifier and swaps
  /// the in-memory key. The salt deliberately stays the same; it's not a
  /// secret, and keeping it stable means only the password changes.
  ///
  /// Call this *after* re-signing existing history with the new key
  /// (see SceneHistoryService.resignAll), never before: the verifier is what
  /// tells the next session which password is current, so flipping it while
  /// history is still signed with the old key would leave the library
  /// unverifiable.
  Future<void> rekey(String newPassword) async {
    final key = await deriveKeyFor(newPassword);
    await _writeVerifier(key);
    _key = key;
  }

  /// Discards the in-memory key — e.g. on app lock or sign-out. Existing
  /// signed history is unaffected; it just can't be verified again until
  /// [unlock] is called with the correct password.
  void lock() => _key = null;

  String _verifierFor(List<int> key) =>
      crypto.Hmac(crypto.sha256, key).convert(utf8.encode(_verifierPayload)).toString();

  Future<void> _writeVerifier(List<int> key) async {
    await _verifierFile.parent.create(recursive: true);
    await _verifierFile.writeAsString(_verifierFor(key));
  }

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
