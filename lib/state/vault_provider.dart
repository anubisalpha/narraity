import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../services/history_signing_key_manager.dart';
import '../services/scene_history_service.dart';
import '../services/vault_service.dart';
import 'library_provider.dart';

/// Vault artifacts live in a reserved `_Vault/` folder at the library root,
/// deliberately *outside* every project directory: [VaultService.buildVault]
/// zips a whole project folder, so a vault stored inside one would end up
/// sealing previous vaults inside each new generation.
///
/// `LibraryService.listProjects` already skips `_`-prefixed folders, so this
/// never shows up as a project.
final vaultRootProvider = FutureProvider<Directory>((ref) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return Directory(p.join(root.path, '_Vault'));
});

/// One key manager for the whole app session — the derived key lives only in
/// this object's memory, so a per-widget or per-project instance would mean
/// re-entering the password constantly.
final historySigningKeyManagerProvider =
    FutureProvider<HistorySigningKeyManager>((ref) async {
      final vaultRoot = await ref.watch(vaultRootProvider.future);
      return HistorySigningKeyManager(
        saltFile: File(p.join(vaultRoot.path, 'salt')),
        verifierFile: File(p.join(vaultRoot.path, 'verifier')),
      );
    });

final vaultServiceProvider = Provider<VaultService>((ref) => VaultService());

enum VaultStatus {
  /// No vault password has ever been set for this library.
  notConfigured,

  /// A password exists but hasn't been entered this session: new snapshots
  /// are written unsigned and auto-backup is skipped, but nothing is broken
  /// and existing signed history is trusted rather than flagged.
  locked,

  /// Password entered — snapshots are signed and verified, backups run.
  unlocked,
}

/// The password itself for this session, not just the derived signing key.
/// Both are needed: history signing uses the key, but [VaultService] generates
/// a fresh salt per vault file and so must derive its own key from the
/// password — meaning unattended auto-refresh can't work from the signing key
/// alone. Held in memory only, cleared on lock, never written to disk.
final vaultSessionPasswordProvider = StateProvider<String?>((ref) => null);

class VaultStatusNotifier extends AsyncNotifier<VaultStatus> {
  @override
  Future<VaultStatus> build() async {
    final manager = await ref.watch(historySigningKeyManagerProvider.future);
    if (manager.isUnlocked) return VaultStatus.unlocked;
    return await manager.isConfigured
        ? VaultStatus.locked
        : VaultStatus.notConfigured;
  }

  Future<void> setup(String password) async {
    final manager = await ref.read(historySigningKeyManagerProvider.future);
    await manager.setup(password);
    ref.read(vaultSessionPasswordProvider.notifier).state = password;
    state = const AsyncValue.data(VaultStatus.unlocked);
  }

  /// Returns false on a wrong password, leaving the status unchanged.
  Future<bool> unlock(String password) async {
    final manager = await ref.read(historySigningKeyManagerProvider.future);
    final ok = await manager.unlock(password);
    if (ok) {
      ref.read(vaultSessionPasswordProvider.notifier).state = password;
      state = const AsyncValue.data(VaultStatus.unlocked);
    }
    return ok;
  }

  /// Swaps the library to [newPassword]. Call only after existing history has
  /// been re-signed with the new key (see SceneHistoryService.resignAll).
  Future<void> rekey(String newPassword) async {
    final manager = await ref.read(historySigningKeyManagerProvider.future);
    await manager.rekey(newPassword);
    ref.read(vaultSessionPasswordProvider.notifier).state = newPassword;
    state = const AsyncValue.data(VaultStatus.unlocked);
  }

  Future<void> lock() async {
    final manager = await ref.read(historySigningKeyManagerProvider.future);
    manager.lock();
    ref.read(vaultSessionPasswordProvider.notifier).state = null;
    state = const AsyncValue.data(VaultStatus.locked);
  }
}

final vaultStatusProvider =
    AsyncNotifierProvider<VaultStatusNotifier, VaultStatus>(
      VaultStatusNotifier.new,
    );

const _retentionPrefKey = 'vault.retentionCount';
const _autoRefreshPrefKey = 'vault.autoRefresh';

/// How many vault generations to keep per project. More generations means a
/// longer window to notice corruption before the last good backup rotates
/// out — see [VaultService.refreshVault].
class VaultRetentionNotifier extends Notifier<int> {
  static const defaultCount = 10;
  static const minCount = 3;
  static const maxCount = 30;

  @override
  int build() {
    _restore();
    return defaultCount;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(_retentionPrefKey) ?? defaultCount;
  }

  Future<void> set(int count) async {
    state = count.clamp(minCount, maxCount);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_retentionPrefKey, state);
  }
}

final vaultRetentionCountProvider =
    NotifierProvider<VaultRetentionNotifier, int>(VaultRetentionNotifier.new);

class VaultAutoRefreshNotifier extends Notifier<bool> {
  @override
  bool build() {
    _restore();
    return true;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_autoRefreshPrefKey) ?? true;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoRefreshPrefKey, enabled);
  }
}

final vaultAutoRefreshProvider =
    NotifierProvider<VaultAutoRefreshNotifier, bool>(
      VaultAutoRefreshNotifier.new,
    );

const _allowUnencryptedPrefKey = 'vault.allowUnencrypted';

/// Opt-in: run automatic backups even with no vault password set, writing
/// plain (unencrypted) generations instead of skipping backup entirely (see
/// [VaultActions.refreshProject] and [VaultService.buildPlainVault]). Off by
/// default — matches this app's convention for new automatic behavior
/// (e.g. [DriveImmediateSyncNotifier]) being opt-in, and specifically here
/// because turning it on trades away encryption, which shouldn't happen
/// silently.
class VaultAllowUnencryptedNotifier extends Notifier<bool> {
  @override
  bool build() {
    _restore();
    return false;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_allowUnencryptedPrefKey) ?? false;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowUnencryptedPrefKey, enabled);
  }
}

final vaultAllowUnencryptedProvider =
    NotifierProvider<VaultAllowUnencryptedNotifier, bool>(
      VaultAllowUnencryptedNotifier.new,
    );

/// Set once the user dismisses the unlock prompt, so opening several projects
/// in one session doesn't re-ask after they've already declined.
final unlockPromptDismissedProvider = StateProvider<bool>((ref) => false);

/// Vault operations that span several providers (backup, restore location,
/// password change). Held behind a provider rather than exposed as free
/// functions so widgets (`WidgetRef`) and providers (`Ref`) can both reach
/// them — the two ref types share no common supertype in Riverpod 2.
class VaultActions {
  VaultActions(this._ref);

  final Ref _ref;

  /// Builds a new vault generation for [project], pruning old ones past the
  /// configured retention count. Returns null when there's nothing to build
  /// with: no password unlocked this session, and [vaultAllowUnencryptedProvider]
  /// isn't turned on to fall back to a plain (unencrypted) generation —
  /// both expected, user-chosen states, not errors.
  Future<File?> refreshProject(Project project) async {
    final password = _ref.read(vaultSessionPasswordProvider);
    if (password == null) {
      if (!_ref.read(vaultAllowUnencryptedProvider)) return null;

      final libraryRoot = await _ref.read(libraryServiceProvider).libraryRoot();
      final vaultDir = await vaultDirFor(project);
      return _ref
          .read(vaultServiceProvider)
          .refreshPlainVault(
            projectDir: Directory(p.join(libraryRoot.path, project.folderName)),
            vaultDir: vaultDir,
            baseName: project.folderName,
            retainCount: _ref.read(vaultRetentionCountProvider),
          );
    }

    final libraryRoot = await _ref.read(libraryServiceProvider).libraryRoot();
    final vaultDir = await vaultDirFor(project);

    return _ref
        .read(vaultServiceProvider)
        .refreshVault(
          projectDir: Directory(p.join(libraryRoot.path, project.folderName)),
          vaultDir: vaultDir,
          baseName: project.folderName,
          password: password,
          retainCount: _ref.read(vaultRetentionCountProvider),
        );
  }

  /// Directory holding [project]'s vault generations.
  Future<Directory> vaultDirFor(Project project) async {
    final vaultRoot = await _ref.read(vaultRootProvider.future);
    return Directory(p.join(vaultRoot.path, project.folderName));
  }

  /// Changes the library's vault password: verifies the old one, re-signs
  /// every project's scene history under the new key, switches the stored
  /// verifier, then builds a fresh vault generation per project under the new
  /// password.
  ///
  /// Ordering matters. Verification of the whole library happens before any
  /// rewrite, and the verifier only flips *after* every project is re-signed —
  /// otherwise a failure midway would leave the library claiming a password
  /// that can't verify its own history. If a write fails partway through,
  /// already-migrated projects are re-signed back to the old key before
  /// rethrowing.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    void Function(String status)? onProgress,
  }) async {
    final manager = await _ref.read(historySigningKeyManagerProvider.future);
    if (!await manager.unlock(oldPassword)) {
      throw VaultOpenException('Current password is incorrect.');
    }

    final oldKey = await manager.deriveKeyFor(oldPassword);
    final newKey = await manager.deriveKeyFor(newPassword);

    final library = _ref.read(libraryServiceProvider);
    final libraryRoot = await library.libraryRoot();
    final projects = await library.listProjects();

    SceneHistoryService historyFor(Project project) => SceneHistoryService(
      Directory(p.join(libraryRoot.path, project.folderName)),
    );

    for (final project in projects) {
      onProgress?.call('Checking ${project.title}…');
      await historyFor(project).verifyAllSignatures(oldKey);
    }

    final migrated = <Project>[];
    try {
      for (final project in projects) {
        onProgress?.call('Re-signing ${project.title}…');
        await historyFor(project).resignAll(oldKey: oldKey, newKey: newKey);
        migrated.add(project);
      }
    } catch (_) {
      for (final project in migrated) {
        try {
          await historyFor(project).resignAll(oldKey: newKey, newKey: oldKey);
        } catch (_) {
          // Best-effort rollback; the original error is the one to report.
        }
      }
      rethrow;
    }

    await _ref.read(vaultStatusProvider.notifier).rekey(newPassword);

    for (final project in projects) {
      onProgress?.call('Backing up ${project.title}…');
      await refreshProject(project);
      _ref.invalidate(vaultGenerationsProvider(project));
    }
  }
}

final vaultActionsProvider = Provider<VaultActions>(VaultActions.new);

/// Existing vault generations for a project, newest first. Invalidate after
/// building a backup to refresh the settings/restore lists.
final vaultGenerationsProvider = FutureProvider.family<List<File>, Project>((
  ref,
  project,
) async {
  final vaultDir = await ref.read(vaultActionsProvider).vaultDirFor(project);
  final generations = await ref
      .watch(vaultServiceProvider)
      .listGenerations(vaultDir, project.folderName);
  return generations.reversed.toList();
});

/// The timestamp encoded in a generation's filename
/// (`<baseName>.<iso-with-dashes>.vault`), or null if it doesn't parse.
DateTime? vaultGenerationTimestamp(File generation) {
  final name = p.basename(generation.path);
  final withoutExtension = name.substring(0, name.length - '.vault'.length);
  final dot = withoutExtension.indexOf('.');
  if (dot < 0) return null;
  final stamp = withoutExtension.substring(dot + 1);
  // refreshVault writes ISO-8601 with ':' replaced by '-' for filename
  // safety; put them back to parse. Only the two in the time portion are
  // affected — the date's separators are already '-'.
  final parts = stamp.split('T');
  if (parts.length != 2) return null;
  return DateTime.tryParse('${parts[0]}T${parts[1].replaceAll('-', ':')}');
}
