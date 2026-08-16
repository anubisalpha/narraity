import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../services/history_signing_key_manager.dart';
import '../services/scene_history_service.dart';
import '../services/vault_service.dart';
import 'library_provider.dart';
import 'scene_history_provider.dart';

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

/// A [HistorySigningKeyManager] scoped to one project's *own* vault password,
/// backed by salt/verifier files under `_Vault/<folder>/` (alongside that
/// project's vault generations). A project has "opted in" to its own password
/// iff this manager's verifier exists ([HistorySigningKeyManager.isConfigured]);
/// until then the project uses the library-wide key instead (see
/// [effectiveSigningKeyManagerProvider]).
///
/// One cached instance per project (family, kept alive), so its in-memory
/// unlocked key survives rebuilds the same way the library manager does.
final projectSigningKeyManagerProvider =
    FutureProvider.family<HistorySigningKeyManager, Project>((ref, project) async {
  final vaultRoot = await ref.watch(vaultRootProvider.future);
  final dir = p.join(vaultRoot.path, project.folderName);
  return HistorySigningKeyManager(
    saltFile: File(p.join(dir, 'salt')),
    verifierFile: File(p.join(dir, 'verifier')),
  );
});

/// Whether [project] has opted into its own vault password (rather than using
/// the library-wide one). Invalidate after opting in/out.
final projectHasOwnPasswordProvider =
    FutureProvider.family<bool, Project>((ref, project) async {
  final manager = await ref.watch(projectSigningKeyManagerProvider(project).future);
  return manager.isConfigured;
});

/// The signing-key manager that actually governs [project]'s scene history:
/// the project's own manager if it has opted into a per-project password,
/// otherwise the library-wide manager (the default, backward-compatible path
/// every project uses until it opts in).
final effectiveSigningKeyManagerProvider =
    FutureProvider.family<HistorySigningKeyManager, Project>((ref, project) async {
  final projectManager = await ref.watch(projectSigningKeyManagerProvider(project).future);
  if (await projectManager.isConfigured) return projectManager;
  return ref.watch(historySigningKeyManagerProvider.future);
});

/// Session password for a project that uses its own vault password, keyed by
/// folder name — needed (like [vaultSessionPasswordProvider]) so unattended
/// backups can derive the per-file vault key. Null when the project is locked
/// or uses the library password. Held in memory only, never persisted.
final projectVaultPasswordProvider =
    StateProvider.family<String?, String>((ref, folderName) => null);

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
  /// The vault password that governs [project] right now: its own session
  /// password if it has opted into a per-project password, otherwise the
  /// library-wide session password. Null means "locked / no password" — the
  /// caller falls back to a plain backup or skips, exactly as before.
  Future<String?> _effectivePasswordFor(Project project) async {
    final projectManager =
        await _ref.read(projectSigningKeyManagerProvider(project).future);
    if (await projectManager.isConfigured) {
      return _ref.read(projectVaultPasswordProvider(project.folderName));
    }
    return _ref.read(vaultSessionPasswordProvider);
  }

  Future<File?> refreshProject(Project project) async {
    final password = await _effectivePasswordFor(project);
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

  /// Scene history for [project], with no key manager attached — enough for
  /// [SceneHistoryService.resignAll]/[verifyAllSignatures], which take keys as
  /// arguments rather than reading them from a manager.
  Future<SceneHistoryService> _historyFor(Project project) async {
    final libraryRoot = await _ref.read(libraryServiceProvider).libraryRoot();
    return SceneHistoryService(
      Directory(p.join(libraryRoot.path, project.folderName)),
    );
  }

  /// Enters [project]'s own vault password for this session, unlocking signing
  /// and encrypted backups for it. Returns false on a wrong password, leaving
  /// state unchanged. A no-op-false if the project hasn't opted into its own
  /// password (nothing to unlock).
  Future<bool> unlockProject(Project project, String password) async {
    final manager =
        await _ref.read(projectSigningKeyManagerProvider(project).future);
    if (!await manager.isConfigured) return false;
    final ok = await manager.unlock(password);
    if (ok) {
      _ref.read(projectVaultPasswordProvider(project.folderName).notifier).state =
          password;
      _ref.invalidate(sceneHistoryServiceProvider(project));
    }
    return ok;
  }

  /// Locks [project]'s own vault (drops its in-memory key/password). Existing
  /// signed history is untouched; it just can't be verified again until
  /// [unlockProject] is called. No-op if the project uses the library password.
  Future<void> lockProject(Project project) async {
    final manager =
        await _ref.read(projectSigningKeyManagerProvider(project).future);
    if (!await manager.isConfigured) return;
    manager.lock();
    _ref.read(projectVaultPasswordProvider(project.folderName).notifier).state = null;
    _ref.invalidate(sceneHistoryServiceProvider(project));
  }

  /// Opts [project] into its *own* vault password, distinct from the library's:
  /// re-signs its existing scene history from whatever key governs it now (the
  /// library key, or nothing if its history is legacy-unsigned) onto a key
  /// derived from [newPassword], writes the per-project verifier, and builds a
  /// fresh backup under the new password.
  ///
  /// If the library itself has a password, it must be unlocked first — that's
  /// the key this project's history is currently signed with, and re-signing
  /// can't happen without it. Ordering mirrors [changePassword]: history is
  /// migrated (verify-all-then-write, so a failure changes nothing on disk)
  /// before the verifier flips, and a failure writing the verifier rolls the
  /// re-sign back so the project stays on its previous key.
  Future<void> setProjectPassword(Project project, String newPassword) async {
    final projectManager =
        await _ref.read(projectSigningKeyManagerProvider(project).future);
    if (await projectManager.isConfigured) {
      throw VaultOpenException(
        'This project already has its own password — use change-password instead.',
      );
    }

    final libraryManager =
        await _ref.read(historySigningKeyManagerProvider.future);
    final libraryConfigured = await libraryManager.isConfigured;

    // oldKey = the key currently signing this project's history.
    final List<int> oldKey;
    if (libraryConfigured) {
      if (!libraryManager.isUnlocked) {
        throw VaultOpenException(
          'Unlock the library vault first so this project\'s history can be '
          're-signed under its new password.',
        );
      }
      oldKey = libraryManager.currentKey!;
    } else {
      // No library password: the history is legacy-unsigned, so resignAll has
      // no signed entries to verify and any key works as the (unused) oldKey.
      oldKey = await projectManager.deriveKeyFor(newPassword);
    }
    final newKey = await projectManager.deriveKeyFor(newPassword);

    final history = await _historyFor(project);
    await history.resignAll(oldKey: oldKey, newKey: newKey);
    try {
      await projectManager.setup(newPassword);
    } catch (_) {
      // Roll the re-sign back so the project stays on its previous key rather
      // than being left signed with a key that has no verifier to prove it.
      try {
        await history.resignAll(oldKey: newKey, newKey: oldKey);
      } catch (_) {/* best effort; the original error is what matters */}
      rethrow;
    }

    _ref.read(projectVaultPasswordProvider(project.folderName).notifier).state =
        newPassword;
    // Deliberately NOT invalidating projectSigningKeyManagerProvider: setup()
    // just unlocked that cached instance, and disposing it would throw the
    // in-memory key away, re-locking a vault we only this moment opened. Only
    // the providers that read its `isConfigured`/routing need to recompute.
    _ref.invalidate(projectHasOwnPasswordProvider(project));
    _ref.invalidate(effectiveSigningKeyManagerProvider(project));
    _ref.invalidate(sceneHistoryServiceProvider(project));
    await refreshProject(project);
    _ref.invalidate(vaultGenerationsProvider(project));
  }

  /// Opts [project] back out of its own password, returning it to the
  /// library-wide key: re-signs its history from the project key onto the
  /// library key, then removes the per-project verifier/salt. Requires both the
  /// project's own vault and the library vault to be unlocked (both keys are
  /// needed for the migration). Refuses if the library has no password, since
  /// there'd be no shared key to hand the history back to.
  Future<void> removeProjectPassword(Project project) async {
    final projectManager =
        await _ref.read(projectSigningKeyManagerProvider(project).future);
    if (!await projectManager.isConfigured) return;
    if (!projectManager.isUnlocked) {
      throw VaultOpenException('Unlock this project\'s vault first.');
    }

    final libraryManager =
        await _ref.read(historySigningKeyManagerProvider.future);
    if (!await libraryManager.isConfigured) {
      throw VaultOpenException(
        'Set a library vault password first, or keep this project\'s own '
        'password — there\'s no shared key to return its history to otherwise.',
      );
    }
    if (!libraryManager.isUnlocked) {
      throw VaultOpenException('Unlock the library vault first.');
    }

    final projectKey = projectManager.currentKey!;
    final libraryKey = libraryManager.currentKey!;

    final history = await _historyFor(project);
    await history.resignAll(oldKey: projectKey, newKey: libraryKey);
    await projectManager.reset();

    _ref.read(projectVaultPasswordProvider(project.folderName).notifier).state = null;
    _ref.invalidate(projectSigningKeyManagerProvider(project));
    _ref.invalidate(projectHasOwnPasswordProvider(project));
    _ref.invalidate(effectiveSigningKeyManagerProvider(project));
    _ref.invalidate(sceneHistoryServiceProvider(project));
    await refreshProject(project);
    _ref.invalidate(vaultGenerationsProvider(project));
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
    // Projects that have opted into their own vault password are signed with
    // their own key, not the library one — a library password change must not
    // touch them (verifying them under the library key would wrongly fail).
    final projects = <Project>[];
    for (final proj in await library.listProjects()) {
      final pm = await _ref.read(projectSigningKeyManagerProvider(proj).future);
      if (!await pm.isConfigured) projects.add(proj);
    }

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
