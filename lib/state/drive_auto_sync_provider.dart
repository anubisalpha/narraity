import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sync_log_entry.dart';
import '../services/drive_sync_log_service.dart';
import '../services/drive_sync_service.dart';
import '../services/project_file_watcher.dart';
import 'dictation_provider.dart';
import 'drive_provider.dart';
import 'editor_settings_provider.dart';
import 'library_provider.dart';
import 'spell_check_provider.dart';
import 'theme_provider.dart';
import 'tts_settings_provider.dart';
import 'vault_provider.dart';

const driveImmediateSyncPrefKey = 'driveSync.immediate';
const driveDailySyncPrefKey = 'driveSync.dailyEnabled';
const driveFrequentSyncIntervalPrefKey = 'driveSync.frequentIntervalMinutes';

/// Sync immediately (per-file) after a save — off by default: this is new
/// automatic network activity that didn't exist before Phase 5's follow-up,
/// so it's opt-in rather than silently turned on once Drive is connected.
class DriveImmediateSyncNotifier extends Notifier<bool> {
  @override
  bool build() {
    _restore();
    return false;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(driveImmediateSyncPrefKey) ?? false;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(driveImmediateSyncPrefKey, enabled);
  }
}

final driveImmediateSyncEnabledProvider =
    NotifierProvider<DriveImmediateSyncNotifier, bool>(DriveImmediateSyncNotifier.new);

/// A guaranteed once-a-day full sync + reconciliation check, independent of
/// (and in addition to) the more frequent interval below.
class DriveDailySyncNotifier extends Notifier<bool> {
  @override
  bool build() {
    _restore();
    return false;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(driveDailySyncPrefKey) ?? false;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(driveDailySyncPrefKey, enabled);
  }
}

final driveDailySyncEnabledProvider =
    NotifierProvider<DriveDailySyncNotifier, bool>(DriveDailySyncNotifier.new);

/// Minutes between "frequent" full syncs — 0 means off. A small preset list
/// (5/15/30/60) rather than a free-form number, to keep the Settings UI a
/// simple dropdown.
class DriveFrequentSyncIntervalNotifier extends Notifier<int> {
  @override
  int build() {
    _restore();
    return 0;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(driveFrequentSyncIntervalPrefKey) ?? 0;
  }

  Future<void> set(int minutes) async {
    state = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(driveFrequentSyncIntervalPrefKey, minutes);
  }
}

final driveFrequentSyncIntervalProvider =
    NotifierProvider<DriveFrequentSyncIntervalNotifier, int>(DriveFrequentSyncIntervalNotifier.new);

final driveSyncLogServiceProvider = Provider<DriveSyncLogService>((ref) => DriveSyncLogService());

/// Re-applies `_Settings/settings.json` into the live providers after a
/// sync might have pulled a newer copy from another device — same list
/// `DriveSyncSettingsSection`'s manual "Sync now" tile invalidates, kept in
/// sync with it by hand since `Ref` (providers) and `WidgetRef` (widgets)
/// aren't a shared type to factor this into one function both can call.
Future<void> reapplyAppSettingsAfterSync(Ref ref) async {
  await ref.read(appSettingsServiceProvider).importFromFile();
  ref.invalidate(themeModeProvider);
  ref.invalidate(dictationLanguageProvider);
  ref.invalidate(dictationModelSizeProvider);
  ref.invalidate(spellCheckEnabledProvider);
  ref.invalidate(ttsSettingsProvider);
  ref.invalidate(editorSettingsProvider);
  ref.invalidate(vaultRetentionCountProvider);
  ref.invalidate(vaultAutoRefreshProvider);
  ref.invalidate(driveImmediateSyncEnabledProvider);
  ref.invalidate(driveDailySyncEnabledProvider);
  ref.invalidate(driveFrequentSyncIntervalProvider);
}

class _SyncTarget {
  const _SyncTarget({required this.title, required this.folderName, required this.directory});
  final String title;
  final String folderName;
  final Directory directory;
}

Future<List<_SyncTarget>> _allSyncTargets(Ref ref) async {
  final library = ref.read(libraryServiceProvider);
  final targets = <_SyncTarget>[];

  for (final project in await library.listProjects()) {
    targets.add(_SyncTarget(
      title: project.title,
      folderName: project.folderName,
      directory: await projectDirectory(library, project),
    ));
  }

  targets.add(_SyncTarget(
    title: 'Vault backups',
    folderName: '_Vault',
    directory: await ref.read(vaultRootProvider.future),
  ));

  final settings = ref.read(appSettingsServiceProvider);
  await settings.exportToFile();
  targets.add(_SyncTarget(
    title: 'App settings',
    folderName: '_Settings',
    directory: await settings.settingsRoot(),
  ));

  return targets;
}

/// Runs a full sync across every project, the Vault, and App Settings —
/// what both the daily and frequent timers do on each tick. Logs one entry
/// per target, success or failure, and re-applies any pulled settings
/// change afterwards. A no-op if not currently signed in (a timer firing
/// while signed out just skips silently rather than erroring).
Future<void> runFullSyncAcrossAllTargets(Ref ref, SyncTrigger trigger) async {
  if (ref.read(driveConnectionProvider) != DriveConnectionStatus.signedIn) return;

  final DriveSyncService service;
  try {
    service = await ref.read(driveSyncServiceProvider.future);
  } catch (_) {
    return;
  }

  final log = ref.read(driveSyncLogServiceProvider);
  for (final target in await _allSyncTargets(ref)) {
    try {
      final result = await service.sync(target.directory, target.folderName);
      await log.append(SyncLogEntry(
        timestamp: DateTime.now(),
        targetTitle: target.title,
        trigger: trigger,
        uploaded: result.uploaded.length,
        downloaded: result.downloaded.length,
        deletedLocal: result.deletedLocal.length,
        deletedRemote: result.deletedRemote.length,
        conflicts: result.conflicts.length,
      ));
    } catch (error) {
      await log.append(SyncLogEntry(
        timestamp: DateTime.now(),
        targetTitle: target.title,
        trigger: trigger,
        error: error.toString(),
      ));
    }
  }

  await reapplyAppSettingsAfterSync(ref);
}

/// Owns the two independent timers (daily / "frequent") and re-schedules
/// them whenever the relevant settings or the connection status change.
class DriveAutoSyncScheduler {
  DriveAutoSyncScheduler(this._ref);
  final Ref _ref;

  Timer? _dailyTimer;
  Timer? _frequentTimer;

  void reschedule() {
    _dailyTimer?.cancel();
    _dailyTimer = null;
    _frequentTimer?.cancel();
    _frequentTimer = null;

    if (_ref.read(driveConnectionProvider) != DriveConnectionStatus.signedIn) return;

    if (_ref.read(driveDailySyncEnabledProvider)) {
      _dailyTimer = Timer.periodic(
        const Duration(hours: 24),
        (_) => runFullSyncAcrossAllTargets(_ref, SyncTrigger.periodic),
      );
    }

    final frequentMinutes = _ref.read(driveFrequentSyncIntervalProvider);
    if (frequentMinutes > 0) {
      _frequentTimer = Timer.periodic(
        Duration(minutes: frequentMinutes),
        (_) => runFullSyncAcrossAllTargets(_ref, SyncTrigger.periodic),
      );
    }
  }

  void dispose() {
    _dailyTimer?.cancel();
    _frequentTimer?.cancel();
  }
}

/// Kept alive for the whole app session by a `ref.watch` in `NarraityApp`'s
/// root build method — timers need to run regardless of which screen is
/// currently open, not just while the Settings screen happens to be
/// mounted.
final driveAutoSyncSchedulerProvider = Provider<DriveAutoSyncScheduler>((ref) {
  final scheduler = DriveAutoSyncScheduler(ref);
  ref
    ..listen(driveDailySyncEnabledProvider, (_, __) => scheduler.reschedule())
    ..listen(driveFrequentSyncIntervalProvider, (_, __) => scheduler.reschedule())
    ..listen(driveConnectionProvider, (_, __) => scheduler.reschedule());
  scheduler.reschedule();
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

/// Active only while a project is open, immediate sync is switched on, and
/// Drive is connected — watches that project's folder and syncs each
/// changed file individually right after it settles. Rebuilds (disposing
/// the old watcher first) whenever any of those three conditions change,
/// via Riverpod's normal `ref.watch`-inside-a-provider re-run semantics.
final projectFileWatcherProvider = FutureProvider.autoDispose<void>((ref) async {
  final project = ref.watch(currentProjectProvider);
  final immediateEnabled = ref.watch(driveImmediateSyncEnabledProvider);
  final connection = ref.watch(driveConnectionProvider);
  if (project == null || !immediateEnabled || connection != DriveConnectionStatus.signedIn) {
    return;
  }

  final library = ref.read(libraryServiceProvider);
  final dir = await projectDirectory(library, project);
  final log = ref.read(driveSyncLogServiceProvider);

  Future<void> handleChange(String relativePath) async {
    try {
      final service = await ref.read(driveSyncServiceProvider.future);
      final result = await service.syncSingleFile(dir, project.folderName, relativePath);
      await log.append(SyncLogEntry(
        timestamp: DateTime.now(),
        targetTitle: project.title,
        trigger: SyncTrigger.immediate,
        uploaded: result.uploaded.length,
        downloaded: result.downloaded.length,
        deletedLocal: result.deletedLocal.length,
        deletedRemote: result.deletedRemote.length,
        conflicts: result.conflicts.length,
      ));
    } catch (error) {
      await log.append(SyncLogEntry(
        timestamp: DateTime.now(),
        targetTitle: project.title,
        trigger: SyncTrigger.immediate,
        error: error.toString(),
      ));
    }
  }

  final watcher = ProjectFileWatcher(dir, onFileChanged: handleChange);
  ref.onDispose(watcher.dispose);
});
