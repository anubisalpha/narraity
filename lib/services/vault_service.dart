import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

/// Thrown when a vault can't be opened — wrong password, corrupted archive,
/// or a deliberately tampered ciphertext. AES-GCM's authentication tag makes
/// these indistinguishable from each other by design (that's what makes it
/// tamper-evident rather than just "encrypted"): there is no way to tell
/// "wrong password" apart from "someone changed a byte" without the key, and
/// exposing that distinction would leak information to an attacker.
class VaultOpenException implements Exception {
  VaultOpenException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Builds and restores a single-file, password-protected, tamper-evident
/// backup of a Narraity project ("Vault" tier — see PLAN.md "Version
/// History" / data protection).
///
/// This exists to survive corruption that the live, editable project files
/// can't: the vault is one sealed artifact, independent of the many small
/// JSON/markdown files that make up the working project, so a single bad
/// write or sync conflict touching those files has no way to also touch the
/// vault. The password is never stored anywhere by this service — losing it
/// means losing the vault, which is a deliberate trade-off for not needing
/// any per-device or cross-device key distribution — a human-memorized
/// password is identical on every device by construction, which is also why
/// the scene-history signing key (see HistorySigningKeyManager) is derived
/// from this same password rather than held in OS-specific secure storage.
///
/// Format (v1): a JSON header (self-describing, not secret) wrapping a
/// zipped snapshot of the project directory, encrypted with AES-256-GCM
/// using a key derived from the password via Argon2id (memory-hard —
/// resists brute-force far better than a fast KDF like PBKDF2 or a bare
/// hash). GCM's authentication tag is what makes "was this tampered with"
/// answerable without any separate signing scheme: decryption itself fails
/// if a single byte was changed anywhere in the ciphertext.
class VaultService {
  static const _formatId = 'narraity-vault-v1';
  // A distinct format id (not a flag on the same header) so an unencrypted
  // vault can never be mistaken for an encrypted one missing its salt/nonce/
  // mac fields — restore/verify branch on this before touching any of that.
  static const _formatIdPlain = 'narraity-vault-plain-v1';
  static const _saltLength = 16;

  // Argon2id parameters: deliberately expensive (hundreds of ms, tens of MB)
  // so a stolen vault file resists offline password guessing, while staying
  // fast enough for one interactive unlock on a phone or an old laptop.
  static const _argonMemoryKib = 19456; // ~19 MB
  static const _argonIterations = 3;
  static const _argonParallelism = 1;

  final _random = Random.secure();

  Future<SecretKey> _deriveKey(String password, List<int> salt) {
    final argon2id = Argon2id(
      memory: _argonMemoryKib,
      iterations: _argonIterations,
      parallelism: _argonParallelism,
      hashLength: 32,
    );
    return argon2id.deriveKeyFromPassword(password: password, nonce: salt);
  }

  /// Zips every file under [projectDir] (recursively), skipping anything in
  /// [exclude] or ending in `.tampered` — shared by [buildVault] and
  /// [buildPlainVault], which differ only in what happens to the resulting
  /// bytes afterward.
  Future<List<int>> _buildZipBytes(
    Directory projectDir,
    Set<String> exclude,
  ) async {
    final archive = Archive();
    await for (final entity in projectDir.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: projectDir.path)
          .replaceAll('\\', '/');
      if (exclude.contains(relative) || relative.endsWith('.tampered')) {
        continue;
      }

      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(relative, bytes.length, bytes));
    }
    return ZipEncoder().encode(archive);
  }

  /// Recursively bundles [projectDir] into a zip, encrypts it under
  /// [password], and writes the sealed result to [vaultFile] (overwriting
  /// any existing file there). [exclude] paths (relative to [projectDir],
  /// posix-style separators) are skipped — use this for anything already
  /// known-bad (e.g. quarantined `.tampered` files) so the vault doesn't
  /// preserve corruption on purpose.
  Future<void> buildVault({
    required Directory projectDir,
    required File vaultFile,
    required String password,
    Set<String> exclude = const {},
  }) async {
    final zipBytes = await _buildZipBytes(projectDir, exclude);

    final salt = List<int>.generate(_saltLength, (_) => _random.nextInt(256));
    final secretKey = await _deriveKey(password, salt);

    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final secretBox = await algorithm.encrypt(
      zipBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    final header = {
      'format': _formatId,
      'kdf': 'argon2id',
      'memoryKib': _argonMemoryKib,
      'iterations': _argonIterations,
      'parallelism': _argonParallelism,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };

    await vaultFile.create(recursive: true);
    await vaultFile.writeAsString(jsonEncode(header));
  }

  /// Same as [buildVault], but with no password and no encryption — the
  /// "back up without a password" opt-in (see `vaultAllowUnencryptedProvider`
  /// and its Settings toggle). Still protects against corruption, accidental
  /// deletion, or hardware failure; just not against someone else reading
  /// the backup file, unlike [buildVault]'s AES-256-GCM output. Written with
  /// a distinct [_formatIdPlain] header rather than silently reusing
  /// [_formatId] with empty crypto fields, so [restoreVault]/[verifyVault]
  /// can never mistake one for the other.
  Future<void> buildPlainVault({
    required Directory projectDir,
    required File vaultFile,
    Set<String> exclude = const {},
  }) async {
    final zipBytes = await _buildZipBytes(projectDir, exclude);
    final header = {'format': _formatIdPlain, 'data': base64Encode(zipBytes)};
    await vaultFile.create(recursive: true);
    await vaultFile.writeAsString(jsonEncode(header));
  }

  /// True if [vaultFile] is password-encrypted, false if it's a plain
  /// (unencrypted) generation from [buildPlainVault] — lets a restore screen
  /// decide whether to prompt for a password *before* asking for one
  /// unnecessarily. Throws [VaultOpenException] if the file can't be read
  /// or isn't a recognized vault at all.
  Future<bool> isEncryptedVault(File vaultFile) async {
    final header = await _readHeader(vaultFile);
    if (header['format'] == _formatId) return true;
    if (header['format'] == _formatIdPlain) return false;
    throw VaultOpenException('Unrecognized vault format.');
  }

  /// Decrypts (or, for a plain generation, simply reads) [vaultFile] and
  /// extracts its contents into [targetDir] (created if missing),
  /// overwriting any files already there. [password] is required for an
  /// encrypted vault and ignored for a plain one — check
  /// [isEncryptedVault] first if the caller needs to know which to expect
  /// before asking the user for a password. Throws [VaultOpenException] if
  /// the password is wrong, no password was given for an encrypted vault, or
  /// the vault is corrupted/tampered — the first two are indistinguishable
  /// by design (see the class doc).
  Future<void> restoreVault({
    required File vaultFile,
    required Directory targetDir,
    String? password,
  }) async {
    final zipBytes = await _extractZipBytes(vaultFile, password);

    final archive = ZipDecoder().decodeBytes(zipBytes);
    await targetDir.create(recursive: true);
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final outFile = File(p.join(targetDir.path, file.name));
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    }
  }

  /// Verifies [vaultFile] is openable (decrypting it if encrypted) without
  /// writing anything to disk — useful for a "check the vault is still
  /// valid" health check that doesn't require picking a restore location.
  /// See [restoreVault] for [password]'s semantics.
  Future<void> verifyVault({required File vaultFile, String? password}) async {
    await _extractZipBytes(vaultFile, password);
  }

  /// Builds a new timestamped vault generation in [vaultDir] and prunes
  /// generations beyond [retainCount] (oldest first) — the entry point for
  /// auto-refresh. [buildVault] is the single-file primitive underneath;
  /// use it directly for a one-off export to an exact path (e.g. a manual
  /// "copy to USB" action) that shouldn't be touched by rotation.
  ///
  /// Rotation exists because a single always-overwritten vault file has a
  /// failure mode of its own: if the live project gets corrupted and the
  /// vault refreshes before anyone notices, an overwrite-in-place design
  /// would seal the corruption into the one artifact meant to survive
  /// everything else failing. Keeping several recent generations gives a
  /// window to notice and recover from an older, still-good one.
  Future<File> refreshVault({
    required Directory projectDir,
    required Directory vaultDir,
    required String baseName,
    required String password,
    int retainCount = 10,
    Set<String> exclude = const {},
  }) async {
    await vaultDir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final vaultFile = File(p.join(vaultDir.path, '$baseName.$stamp.vault'));
    await buildVault(
      projectDir: projectDir,
      vaultFile: vaultFile,
      password: password,
      exclude: exclude,
    );
    await _pruneOldGenerations(vaultDir, baseName, retainCount);
    return vaultFile;
  }

  /// Same as [refreshVault], but for the unencrypted "back up without a
  /// password" path — see [buildPlainVault]. Generations from both this and
  /// [refreshVault] share the same `$baseName.<timestamp>.vault` naming and
  /// rotation, so switching the toggle mid-project doesn't fragment
  /// retention into two separate counts.
  Future<File> refreshPlainVault({
    required Directory projectDir,
    required Directory vaultDir,
    required String baseName,
    int retainCount = 10,
    Set<String> exclude = const {},
  }) async {
    await vaultDir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final vaultFile = File(p.join(vaultDir.path, '$baseName.$stamp.vault'));
    await buildPlainVault(
      projectDir: projectDir,
      vaultFile: vaultFile,
      exclude: exclude,
    );
    await _pruneOldGenerations(vaultDir, baseName, retainCount);
    return vaultFile;
  }

  Future<List<File>> _listGenerations(
    Directory vaultDir,
    String baseName,
  ) async {
    final generations = <File>[];
    if (!await vaultDir.exists()) return generations;
    await for (final entity in vaultDir.list()) {
      final name = p.basename(entity.path);
      if (entity is File &&
          name.startsWith('$baseName.') &&
          name.endsWith('.vault')) {
        generations.add(entity);
      }
    }
    // ISO-8601 timestamps with ':' replaced by '-' still sort correctly as
    // plain strings, so filename order is chronological order.
    generations.sort(
      (a, b) => p.basename(a.path).compareTo(p.basename(b.path)),
    );
    return generations;
  }

  Future<void> _pruneOldGenerations(
    Directory vaultDir,
    String baseName,
    int retainCount,
  ) async {
    final generations = await _listGenerations(vaultDir, baseName);
    final toDelete = generations.length - retainCount;
    for (var i = 0; i < toDelete; i++) {
      await generations[i].delete();
    }
  }

  /// The most recent vault generation for [baseName] in [vaultDir], or null
  /// if none have been built yet — the natural default to offer when the
  /// user opens a "Restore from Vault" screen.
  Future<File?> latestGeneration(Directory vaultDir, String baseName) async {
    final generations = await _listGenerations(vaultDir, baseName);
    return generations.isEmpty ? null : generations.last;
  }

  /// All vault generations for [baseName], oldest first — for a "restore
  /// from an earlier generation" picker, since the most recent one isn't
  /// always the right choice if corruption crept in before it was noticed.
  Future<List<File>> listGenerations(Directory vaultDir, String baseName) =>
      _listGenerations(vaultDir, baseName);

  Future<Map<String, dynamic>> _readHeader(File vaultFile) async {
    if (!await vaultFile.exists()) {
      throw VaultOpenException('No vault file found at ${vaultFile.path}.');
    }
    try {
      return jsonDecode(await vaultFile.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      throw VaultOpenException(
        'Vault file is not readable — it may be corrupted.',
      );
    }
  }

  /// Dispatches to the plain or encrypted extraction path based on
  /// [vaultFile]'s own header — the single entry point [restoreVault] and
  /// [verifyVault] share. Throws [VaultOpenException] for an encrypted
  /// vault opened with no [password].
  Future<List<int>> _extractZipBytes(File vaultFile, String? password) async {
    final header = await _readHeader(vaultFile);
    if (header['format'] == _formatIdPlain) {
      return base64Decode(header['data'] as String);
    }
    if (password == null) {
      throw VaultOpenException(
        'This vault is password-protected — a password is required.',
      );
    }
    return _decryptVault(header, password);
  }

  Future<List<int>> _decryptVault(
    Map<String, dynamic> header,
    String password,
  ) async {
    if (header['format'] != _formatId) {
      throw VaultOpenException('Unrecognized vault format.');
    }

    final salt = base64Decode(header['salt'] as String);
    final secretKey = await _deriveKey(password, salt);

    final secretBox = SecretBox(
      base64Decode(header['ciphertext'] as String),
      nonce: base64Decode(header['nonce'] as String),
      mac: Mac(base64Decode(header['mac'] as String)),
    );

    final algorithm = AesGcm.with256bits();
    try {
      return await algorithm.decrypt(secretBox, secretKey: secretKey);
    } on SecretBoxAuthenticationError {
      throw VaultOpenException(
        'Could not open vault — wrong password, or the file has been corrupted or tampered with.',
      );
    }
  }
}
